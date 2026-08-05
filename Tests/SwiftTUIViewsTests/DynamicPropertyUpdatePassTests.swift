import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Stage 0 contract pins for DynamicProperty support (plan
// 2026-08-04-003): update() runs once per discovered property before every
// body evaluation, on every body-evaluation surface, under the ambient
// authoring context the body observes; the pass is skipped when a subtree is
// served from reuse; composed built-ins keep their dependency wiring.
//
// Frozen against real SwiftUI (scratch probe, 2026-08-04): SwiftUI calls
// update() once per property per body evaluation including the first, nested
// properties update before their container, and two instances of one
// composed wrapper hold distinct @State storage. SwiftUI persists update()
// mutations of plain stored fields into that one body evaluation; SwiftTUI
// runs update() on a discarded copy instead — the ratified copy-semantics
// divergence (reference-backed effects persist either way).
@MainActor
private final class PassEventLog {
  private(set) var events: [String] = []

  func append(_ event: String) {
    events.append(event)
  }
}

@propertyWrapper
@MainActor
private struct UpdateRecorder: DynamicProperty {
  private let log: PassEventLog
  private let tag: String

  init(log: PassEventLog, tag: String) {
    self.log = log
    self.tag = tag
  }

  mutating func update() {
    log.append("update:\(tag)")
  }

  var wrappedValue: String {
    tag
  }
}

/// A wrapper composing another dynamic property, to pin nested-first update
/// ordering (the container's update() must observe updated composed state).
@propertyWrapper
@MainActor
private struct NestingRecorder: DynamicProperty {
  private let log: PassEventLog
  private var inner: UpdateRecorder

  init(log: PassEventLog) {
    self.log = log
    inner = UpdateRecorder(log: log, tag: "inner")
  }

  mutating func update() {
    log.append("update:outer")
  }

  var wrappedValue: String {
    inner.wrappedValue
  }
}

/// A wrapper composing `@State`, for the reuse-invalidation pin: a composed
/// state write must deny reuse for the reading subtree exactly like a
/// directly-declared `@State` write.
@propertyWrapper
@MainActor
private struct ComposedTick: DynamicProperty {
  private let state: State<Int>
  private let log: PassEventLog

  init(log: PassEventLog) {
    self.log = log
    state = State(wrappedValue: 0, line: 90, column: 9)
  }

  mutating func update() {
    log.append("update:composed-tick")
  }

  var wrappedValue: Int {
    state.wrappedValue
  }

  func write(_ value: Int) {
    state.wrappedValue = value
  }
}

private enum PassProbeEnvironmentKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var passProbeValue: String {
    get { self[PassProbeEnvironmentKey.self] }
    set { self[PassProbeEnvironmentKey.self] = newValue }
  }
}

/// A wrapper composing `@Environment`, pinning that composed environment
/// reads resolve against the injected ambient values and stay
/// reader-attributed.
@propertyWrapper
@MainActor
private struct EnvironmentProbeReader: DynamicProperty {
  @Environment(\.passProbeValue) private var value

  init() {}

  var wrappedValue: String {
    value
  }
}

@MainActor
struct DynamicPropertyUpdatePassTests {
  private struct PlainBodyHost: View {
    @UpdateRecorder private var recorder: String
    private let log: PassEventLog

    init(log: PassEventLog) {
      self.log = log
      _recorder = UpdateRecorder(log: log, tag: "plain")
    }

    var body: some View {
      log.append("body")
      return Text(recorder)
    }
  }

  private struct NestedHost: View {
    @NestingRecorder private var recorder: String
    private let log: PassEventLog

    init(log: PassEventLog) {
      self.log = log
      _recorder = NestingRecorder(log: log)
    }

    var body: some View {
      log.append("body")
      return Text(recorder)
    }
  }

  private struct RecorderModifier: ViewModifier {
    @UpdateRecorder private var recorder: String
    private let log: PassEventLog

    init(log: PassEventLog) {
      self.log = log
      _recorder = UpdateRecorder(log: log, tag: "modifier")
    }

    func body(content: Content) -> some View {
      log.append("modifierBody")
      return content
    }
  }

  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity,
    environmentValues: EnvironmentValues = .init(),
    invalidatedIdentities: Set<Identity> = []
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: environmentValues,
      invalidatedIdentities: invalidatedIdentities,
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  @Test("update() runs once before a plain body evaluation")
  func updateRunsBeforePlainBody() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      PlainBodyHost(log: log),
      in: makeContext(graph, identity: testIdentity("PlainBody"))
    )
    #expect(log.events == ["update:plain", "body"])
  }

  @Test("nested dynamic properties update before their container")
  func nestedPropertiesUpdateBeforeContainer() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      NestedHost(log: log),
      in: makeContext(graph, identity: testIdentity("NestedOrdering"))
    )
    #expect(log.events == ["update:inner", "update:outer", "body"])
  }

  @Test("the pass covers ResolvableView primitives' dynamic-property scopes")
  func updatePassCoversPrimitiveDynamicScopes() {
    var updated: [String] = []
    DynamicPropertyUpdatePassProbe.onUpdate = { container, property in
      updated.append("\(container):\(property)")
    }
    defer { DynamicPropertyUpdatePassProbe.onUpdate = nil }

    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      TextEditor(text: .constant("hello")),
      in: makeContext(graph, identity: testIdentity("PrimitiveScope"))
    )
    // TextEditor stores a `Binding<String>` plus three `@State` — the pass
    // must reach the primitive's stored wrappers through its own
    // dynamic-property authoring scope.
    #expect(
      updated.contains { $0.hasPrefix("TextEditor:") },
      "no update() ran for TextEditor's stored dynamic properties; saw \(updated)"
    )
  }

  @Test("update() runs before a ViewModifier's composed body")
  func updateRunsBeforeViewModifierBody() {
    let log = PassEventLog()
    let graph = ViewGraph()
    graph.beginFrame()
    _ = Resolver().resolve(
      Text("base").modifier(RecorderModifier(log: log)),
      in: makeContext(graph, identity: testIdentity("ModifierSurface"))
    )
    #expect(log.events == ["update:modifier", "modifierBody"])
  }

  @Test("a reused subtree skips the update pass; invalidation re-runs it")
  func reuseSkipsUpdatePassAndInvalidationRerunsIt() throws {
    let log = PassEventLog()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("ReuseSkip")

    let view = VStack {
      PlainBodyHost(log: log)
      Text("static sibling")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let firstFrame = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(resolved: firstFrame, placed: nil)
    #expect(log.events == ["update:plain", "body"])

    // Collect the two Text leaves from the committed tree (document order):
    // the recorder host collapses onto the first, the static sibling is the
    // second.
    var leafIdentities: [Identity] = []
    var work: [ResolvedNode] = [firstFrame]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        leafIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    #expect(leafIdentities.count == 2)
    let hostIdentity = try #require(leafIdentities.first)
    let siblingIdentity = try #require(leafIdentities.last)

    // Frame 2: invalidation names only the static sibling. Under retained
    // reuse the recorder host is served from the committed subtree — its
    // update() must not run (the reuse door returns before any ambient
    // install; every wrapper-expressible dependency already denies reuse
    // when it changes).
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: [siblingIdentity])
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    let retainedReuseActive = !stackLeanResolveProfile || leanRetainedReuse
    if retainedReuseActive {
      #expect(
        log.events == ["update:plain", "body"],
        "a reused subtree must not re-run the update pass; saw \(log.events)"
      )
    } else {
      #expect(log.events == ["update:plain", "body", "update:plain", "body"])
    }

    // Frame 3: invalidating the host re-runs update() before its body.
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: [hostIdentity])
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)
    #expect(log.events.suffix(2) == ["update:plain", "body"])
  }

  private struct ComposedTickHost: View {
    @ComposedTick private var tick: Int
    private let log: PassEventLog
    private let capture: ComposedTickCapture

    init(log: PassEventLog, capture: ComposedTickCapture) {
      self.log = log
      self.capture = capture
      _tick = ComposedTick(log: log)
    }

    var body: some View {
      log.append("body:\(tick)")
      capture.write = { [_tick] value in _tick.write(value) }
      capture.snapshot = currentImperativeAuthoringContextSnapshot()
      return Text("tick \(tick)")
    }
  }

  @MainActor
  private final class ComposedTickCapture {
    var write: ((Int) -> Void)?
    var snapshot: ImperativeAuthoringContextSnapshot?
  }

  private final class RecordingInvalidator: Invalidating {
    private(set) var requests: [Set<Identity>] = []

    func requestInvalidation(of identities: Set<Identity>) {
      requests.append(identities)
    }
  }

  @Test("a composed @State write invalidates the reader and re-runs its update")
  func composedStateWriteInvalidatesReader() throws {
    let log = PassEventLog()
    let capture = ComposedTickCapture()
    let graph = ViewGraph()
    let rootIdentity = testIdentity("ComposedInvalidation")
    let view = ComposedTickHost(log: log, capture: capture)

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let firstFrame = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(resolved: firstFrame, placed: nil)
    #expect(log.events == ["update:composed-tick", "body:0"])

    let ownerNode = try #require(graph.nodeForIdentity(rootIdentity))
    let spy = RecordingInvalidator()
    ownerNode.invalidator = spy

    let snapshot = try #require(capture.snapshot)
    withImperativeAuthoringContext(snapshot) {
      capture.write?(3)
    }

    let invalidated = spy.requests.reduce(into: Set<Identity>()) { $0.formUnion($1) }
    #expect(!invalidated.isEmpty, "the composed state write scheduled no invalidation")

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(graph, identity: rootIdentity, invalidatedIdentities: invalidated)
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)
    #expect(log.events.suffix(2) == ["update:composed-tick", "body:3"])
  }

  private struct EnvironmentReaderHost: View {
    @EnvironmentProbeReader private var probe: String
    private let capture: EnvironmentCapture

    init(capture: EnvironmentCapture) {
      self.capture = capture
    }

    var body: some View {
      capture.seen = probe
      return Text(probe)
    }
  }

  @MainActor
  private final class EnvironmentCapture {
    var seen: String?
  }

  @Test("@Environment inside a custom wrapper resolves and is reader-attributed")
  func environmentInsideCustomWrapperResolves() throws {
    let capture = EnvironmentCapture()
    let graph = ViewGraph()
    let identity = testIdentity("WrappedEnvironment")
    var environment = EnvironmentValues()
    environment.passProbeValue = "injected"

    graph.beginFrame()
    _ = Resolver().resolve(
      EnvironmentReaderHost(capture: capture),
      in: makeContext(graph, identity: identity, environmentValues: environment)
    )

    #expect(capture.seen == "injected")
    let dependencies = try #require(graph.dependencies(for: identity))
    #expect(
      dependencies.environmentReads.contains(ObjectIdentifier(PassProbeEnvironmentKey.self)),
      "the composed environment read was not attributed to the reading node"
    )
  }
}
