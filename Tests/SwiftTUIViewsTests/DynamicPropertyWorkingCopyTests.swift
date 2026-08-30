import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// The in-place dynamic-property working copy (plan 2026-08-30-001).
//
// `DynamicProperty.update(in:)` is mutating, and the framework runs it through
// the container copy the *next body evaluation consumes*. These pins are all
// written the same way: a wrapper whose evaluation-visible state is a plain
// stored `var`, incremented by its own update. A body that reads `0` is a
// discarded write; a body that reads `1` is the contract.
//
// The pre-2026-08-30 contract could not express this wrapper at all — the pass
// extracted a copy of every field, so a plain stored mutation was dropped and
// the protocol was nonmutating to say so out loud.

@MainActor
private final class WorkingCopyLog {
  private(set) var events: [String] = []
  private(set) var deferredReads: [() -> Void] = []

  func append(_ event: String) {
    events.append(event)
  }

  func deferRead(_ read: @escaping () -> Void) {
    deferredReads.append(read)
  }

  func runDeferredReads() {
    for read in deferredReads {
      read()
    }
  }
}

/// Evaluation-visible state in a plain stored property: the shape the
/// reference-backed contract used to forbid.
@propertyWrapper
@MainActor
private struct Ticking: DynamicProperty {
  private var tick = 0

  init() {}

  var wrappedValue: Int {
    tick
  }

  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    tick += 1
    return .changed
  }
}

/// A wrapper composing another mutating wrapper, so nested-first ordering is
/// observable through values rather than through a log: the outer update reads
/// the inner tick that has already run.
@propertyWrapper
@MainActor
private struct NestedTicking: DynamicProperty {
  private var inner = Ticking()
  private var observedInner = -1

  init() {}

  var wrappedValue: (outerSawInner: Int, inner: Int) {
    (observedInner, inner.wrappedValue)
  }

  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    observedInner = inner.wrappedValue
    return .changed
  }
}

private struct TickingBodyHost: View {
  @Ticking private var tick: Int
  private let log: WorkingCopyLog

  init(log: WorkingCopyLog) {
    self.log = log
  }

  var body: some View {
    log.append("body:\(tick)")
    // Captures `self` — the prepared copy — so firing it later proves the
    // closure carries the mutated value, not the authored one.
    log.deferRead { log.append("closure:\(tick)") }
    return Text("tick")
  }
}

private struct NestedTickingHost: View {
  @NestedTicking private var ticks: (outerSawInner: Int, inner: Int)
  private let log: WorkingCopyLog

  init(log: WorkingCopyLog) {
    self.log = log
  }

  var body: some View {
    log.append("body:outerSaw=\(ticks.outerSawInner),inner=\(ticks.inner)")
    return Text("nested")
  }
}

private struct TickingResolvableHost: PrimitiveView, ResolvableView {
  @Ticking private var tick: Int
  private let log: WorkingCopyLog

  init(log: WorkingCopyLog) {
    self.log = log
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    log.append("resolve:\(tick)")
    return []
  }
}

private struct TickingModifier: ViewModifier {
  @Ticking private var tick: Int
  private let log: WorkingCopyLog

  init(log: WorkingCopyLog) {
    self.log = log
  }

  func body(content: Content) -> some View {
    log.append("modifier:\(tick)")
    return content
  }
}

/// The enum container's log is a static: an enum case with a *tuple* payload
/// reflects as one child holding the tuple, so a two-value payload would hide
/// the wrapper from discovery entirely and the case under test would never run.
@MainActor
private enum EnumProbeLog {
  static var events: [String] = []
}

/// An enum container: no addressable field slot, so the `Mirror` tier runs the
/// update on an extracted copy and the write is dropped — loudly.
private enum EnumTickingHost: View {
  case ticking(Ticking)

  var body: some View {
    guard case .ticking(let ticking) = self else {
      return Text("none")
    }
    EnumProbeLog.events.append("enumBody:\(ticking.wrappedValue)")
    return Text("enum")
  }
}

@MainActor
@Suite("Dynamic-property working copy")
struct DynamicPropertyWorkingCopyTests {
  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: EnvironmentValues(),
      invalidatedIdentities: [],
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  @Test("a stored mutation is visible to the plain body that runs next")
  func mutationReachesPlainBody() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      TickingBodyHost(log: log),
      in: makeContext(graph, identity: testIdentity("WorkingCopyPlainBody"))
    )
    #expect(log.events == ["body:1"])
  }

  @Test("a closure formed in the body carries the prepared copy, not the authored one")
  func closureCapturesPreparedCopy() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      TickingBodyHost(log: log),
      in: makeContext(graph, identity: testIdentity("WorkingCopyClosure"))
    )
    log.runDeferredReads()
    #expect(log.events == ["body:1", "closure:1"])
  }

  @Test("a ResolvableView's resolveElements sees the mutation")
  func mutationReachesResolvableElements() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      TickingResolvableHost(log: log),
      in: makeContext(graph, identity: testIdentity("WorkingCopyResolvable"))
    )
    #expect(log.events == ["resolve:1"])
  }

  @Test("the mutation survives AnyView erasure")
  func mutationSurvivesTypeErasure() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    // AnyView policy: escape hatch under test — erasure is the shape being
    // pinned, not a storage choice.
    _ = Resolver().resolve(
      AnyView(TickingBodyHost(log: log)),
      in: makeContext(graph, identity: testIdentity("WorkingCopyAnyView"))
    )
    #expect(log.events == ["body:1"])
  }

  @Test("nested wrappers update inner-first, and both mutations land")
  func nestedWrappersUpdateInnerFirst() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      NestedTickingHost(log: log),
      in: makeContext(graph, identity: testIdentity("WorkingCopyNested"))
    )
    // outerSaw=1 is the ordering proof: the outer update read the inner tick
    // *after* the inner update ran. inner=1 proves the nested write survived
    // into the body through the same working copy.
    #expect(log.events == ["body:outerSaw=1,inner=1"])
  }

  @Test("two mounts of one view value keep private mutations")
  func mountsDoNotShareTheWorkingCopy() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    let authored = TickingBodyHost(log: log)
    _ = Resolver().resolve(
      authored,
      in: makeContext(graph, identity: testIdentity("WorkingCopyMountA"))
    )
    _ = Resolver().resolve(
      authored,
      in: makeContext(graph, identity: testIdentity("WorkingCopyMountB"))
    )
    // Not ["body:1", "body:2"]: each mount prepares its own copy from the
    // authored value, which the pass never touches.
    #expect(log.events == ["body:1", "body:1"])
  }

  @Test("a composed modifier's wrapper mutation reaches its body")
  func mutationReachesComposedModifierBody() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      Text("base").modifier(TickingModifier(log: log)),
      in: makeContext(graph, identity: testIdentity("WorkingCopyModifier"))
    )
    #expect(log.events == ["modifier:1"])
  }

  @Test("a ScopedBuilder payload's mutation reaches the forwarded body")
  func mutationReachesScopedBuilderPayload() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      ScopedBuilder(scoped: TickingBodyHost(log: log), authoringContext: nil),
      in: makeContext(graph, identity: testIdentity("WorkingCopyScopedBuilder"))
    )
    #expect(log.events == ["body:1"])
  }

  @Test("an enum container cannot write back, and the discard is reported")
  func enumContainerReportsDiscardedMutation() {
    EnumProbeLog.events = []
    let graph = ViewGraph()
    graph.beginFrame()
    // This is a deliberate negative probe, so it suppresses tracing and
    // restores the counter afterwards: the exact-count trace scan treats an
    // unquarantined `dynamic-property-mutation-discarded` as a gate failure,
    // and an alarm raised by a *passing* test would hide a real recurrence.
    // Same idiom as `CommittedHandlerResolutionOracleTests`.
    let probe = DiscardProbeState.capture()
    defer { probe.restore() }
    SoundnessProbeConfiguration.isTraceEnabled = false
    let before = SoundnessProbeConfiguration.dynamicPropertyMutationDiscardedCount

    _ = Resolver().resolve(
      EnumTickingHost.ticking(Ticking()),
      in: makeContext(graph, identity: testIdentity("WorkingCopyEnumContainer"))
    )

    // The contract's boundary: an enum payload has no addressable field slot,
    // so the wrapper updated a copy and the body still reads the authored 0.
    #expect(EnumProbeLog.events == ["enumBody:0"])
    #expect(
      SoundnessProbeConfiguration.dynamicPropertyMutationDiscardedCount == before + 1,
      "a dropped mutation must be loud, not silent"
    )
  }

  @Test("a wrapper that mutates every evaluation leaves the memo witness authored")
  func memoWitnessStaysAuthored() {
    let log = WorkingCopyLog()
    let graph = ViewGraph()
    graph.beginFrame()
    let identity = testIdentity("WorkingCopyMemoWitness")
    _ = Resolver().resolve(TickingBodyHost(log: log), in: makeContext(graph, identity: identity))
    let stashed = graph.nodeForIdentity(identity)?.memoViewValue as? TickingBodyHost
    // The memo comparison witness must be the value the author wrote. If the
    // prepared copy were stashed instead, next frame's authored value would
    // never compare equal and the memo gate would be dead.
    #expect(stashed.map { $0.tickForTesting == 0 } ?? true)
  }
}

extension TickingBodyHost {
  /// Read-only view of the wrapper's stored tick, for the memo-witness pin.
  fileprivate var tickForTesting: Int {
    tick
  }
}

/// Save/restore for the deliberate discarded-mutation probe, so a passing test
/// leaves no soundness alarm behind for the exact-count trace scan.
@MainActor
private struct DiscardProbeState {
  let isTraceEnabled: Bool
  let discardedCount: Int
  let lastViolationDetailByKind: [String: String]

  static func capture() -> Self {
    Self(
      isTraceEnabled: SoundnessProbeConfiguration.isTraceEnabled,
      discardedCount: SoundnessProbeConfiguration.dynamicPropertyMutationDiscardedCount,
      lastViolationDetailByKind: SoundnessProbeConfiguration.lastViolationDetailByKind
    )
  }

  func restore() {
    SoundnessProbeConfiguration.isTraceEnabled = isTraceEnabled
    SoundnessProbeConfiguration.dynamicPropertyMutationDiscardedCount = discardedCount
    SoundnessProbeConfiguration.lastViolationDetailByKind = lastViolationDetailByKind
  }
}
