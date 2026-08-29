import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Bound-at-capture state ownership (plan 2026-08-20-001, Stages 1–3).
//
// Stage-1 unit coverage drives the capture slot and read-path rungs directly
// with hand-injected bindings; Stage-2/3 coverage resolves real views through
// the central resolver with the gate on and exercises the closures their
// bodies captured — outside any ambient dispatch context, the exact shape
// that used to bottom out at the authored seed.
//
// The no-invalidator resolver harness mirrors imperative writes into the box
// seed (the triage's false-green trap), so these tests distinguish routing by
// the DEBUG census counters, not by value alone; the live invalidator-backed
// behavioral A/B lives in SwiftTUITests/CaptureBindingLiveStateTests.swift.
@MainActor
@Suite("State capture binding", .serialized)
struct StateCaptureBindingTests {
  @MainActor
  private final class ClosureLog {
    var read: (@MainActor () -> String)?
    var write: (@MainActor (String) -> Void)?
    var bodyObserved: [String] = []
  }

  private struct CaptureHost: View {
    @State private var value = "seed"
    let log: ClosureLog

    var body: some View {
      let _ = stash()
      Text(value)
    }

    private func stash() {
      log.bodyObserved.append(value)
      log.read = { value }
      log.write = { value = $0 }
    }
  }

  @MainActor
  private struct ComposedStorage: DynamicProperty {
    @State private var storage = "seed"

    var value: String {
      get { storage }
      nonmutating set { storage = newValue }
    }
  }

  private struct ComposedHost: View {
    let log: ClosureLog
    private var composed = ComposedStorage()

    init(log: ClosureLog) {
      self.log = log
    }

    var body: some View {
      let _ = stash()
      Text(composed.value)
    }

    private func stash() {
      log.bodyObserved.append(composed.value)
      log.read = { composed.value }
      log.write = { composed.value = $0 }
    }
  }

  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: [],
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  private func withCaptureBinding<Result>(
    enabled: Bool,
    _ body: () throws -> Result
  ) rethrows -> Result {
    let saved = StateCaptureBindingConfiguration.isEnabled
    StateCaptureBindingConfiguration.isEnabled = enabled
    #if DEBUG
      StateCaptureCensus.resetForTesting()
    #endif
    defer { StateCaptureBindingConfiguration.isEnabled = saved }
    return try body()
  }

  /// Resolves a throwaway stateless view at `identity` so the graph holds a
  /// live node there, and returns that node's owner handle.
  private func makeLiveOwner(
    in graph: ViewGraph,
    identity: Identity
  ) throws -> StateOwnerHandle {
    _ = Resolver().resolve(Text("owner"), in: makeContext(graph, identity: identity))
    let node = try #require(graph.nodeForIdentity(identity))
    return try #require(node.stateOwnerHandle)
  }

  /// An owner handle (and its scope) whose graph has been discarded — the
  /// weak registry drops it, so the handle can never resolve again. The node
  /// is minted directly (no resolve) so no runtime registry retains the
  /// throwaway graph past this scope.
  private func makeDeadOwner() throws -> (owner: StateOwnerHandle, scope: StateGraphScopeID) {
    func discardedGraphOwner() throws -> (StateOwnerHandle, StateGraphScopeID) {
      let graph = ViewGraph()
      let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("DiscardedOwner"))
      return (try #require(node.stateOwnerHandle), graph.stateGraphScopeID)
    }
    let (owner, scope) = try discardedGraphOwner()
    #expect(LiveViewGraphRegistry.node(for: owner) == nil)
    return (owner, scope)
  }

  private func binding(
    owner: StateOwnerHandle,
    identity: Identity,
    scope: StateGraphScopeID,
    path: StateSlotPath = .root
  ) -> StateCaptureBinding {
    StateCaptureBinding(owner: owner, identity: identity, graphScope: scope, path: path)
  }

  // MARK: - Stage 1: capture slot + read-path rungs (hand-injected)

  @Test("a bound capture serves imperative access with no ambient context")
  func captureServesImperativeAccessWithoutAmbientContext() throws {
    try withCaptureBinding(enabled: false) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("CaptureServe")
      let owner = try makeLiveOwner(in: graph, identity: identity)

      var state = State(wrappedValue: "seed")
      state.bindCapture(
        binding(owner: owner, identity: identity, scope: graph.stateGraphScopeID),
        sharedMutableContainer: false
      )

      state.wrappedValue = "typed"
      #expect(state.wrappedValue == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 2)
        #expect(StateCaptureCensus.count(of: .captureMiss) == 0)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      #endif
    }
  }

  @Test("a dead captured owner refreshes through the live identity index")
  func captureRefreshesDeadOwnerThroughLiveIdentity() throws {
    try withCaptureBinding(enabled: false) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("CaptureRefresh")
      _ = try makeLiveOwner(in: graph, identity: identity)
      let (deadOwner, _) = try makeDeadOwner()

      var state = State(wrappedValue: "seed")
      state.bindCapture(
        binding(owner: deadOwner, identity: identity, scope: graph.stateGraphScopeID),
        sharedMutableContainer: false
      )

      state.wrappedValue = "refreshed"
      #expect(state.wrappedValue == "refreshed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureRefreshedOwner) >= 2)
        #expect(StateCaptureCensus.count(of: .captureMiss) == 0)
      #endif
    }
  }

  @Test("the refresh never crosses graph scopes and requires a live occupant")
  func captureRefreshGuardsScopeAndCommittedRemoval() throws {
    try withCaptureBinding(enabled: false) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("CaptureGuard")
      _ = try makeLiveOwner(in: graph, identity: identity)
      let (deadOwner, deadScope) = try makeDeadOwner()

      // Dead scope: the identity exists in a DIFFERENT live graph, but the
      // capture's own scope is gone — the refresh must miss, not borrow the
      // foreign graph.
      var crossScope = State(wrappedValue: "seed")
      crossScope.bindCapture(
        binding(owner: deadOwner, identity: identity, scope: deadScope),
        sharedMutableContainer: false
      )
      #expect(crossScope.wrappedValue == "seed")

      // Committed removal: same live scope, but no node occupies the
      // identity — the refresh must fall through.
      var removed = State(wrappedValue: "seed")
      removed.bindCapture(
        binding(
          owner: deadOwner,
          identity: testIdentity("NeverResolved"),
          scope: graph.stateGraphScopeID
        ),
        sharedMutableContainer: false
      )
      #expect(removed.wrappedValue == "seed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureMiss) == 2)
        #expect(StateCaptureCensus.count(of: .captureRefreshedOwner) == 0)
      #endif
    }
  }

  @Test("the bind plan builder traps on a class container")
  func classContainerTrapsOnBindPlanBuild() async {
    // The capture-bind pass's half of the value-type invariant's runtime
    // floor (plan 2026-08-29-001 §3.3). No conformance is needed to reach
    // the builder — and none is possible: the authoring protocols reject
    // class conformers at compile time.
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        @MainActor final class ClassContainer {
          @State var value = "seed"
        }
        _ = unsafe DynamicPropertyCaptureBindPlanCache.plan(for: ClassContainer.self)
      }
    }
  }

  @Test("struct-copy binds overwrite freely — copies are private to their mount")
  func structOverwriteNeverConflicts() throws {
    try withCaptureBinding(enabled: false) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identityA = testIdentity("StructMountA")
      let identityB = testIdentity("StructMountB")
      let ownerA = try makeLiveOwner(in: graph, identity: identityA)
      let ownerB = try makeLiveOwner(in: graph, identity: identityB)
      let scope = graph.stateGraphScopeID

      var state = State(wrappedValue: "seed")
      state.bindCapture(
        binding(owner: ownerA, identity: identityA, scope: scope),
        sharedMutableContainer: false
      )
      state.bindCapture(
        binding(owner: ownerB, identity: identityB, scope: scope),
        sharedMutableContainer: false
      )
      #if DEBUG
        guard case .bound(let bound) = state.captureSlotForTesting else {
          Issue.record("expected the second bind to overwrite")
          return
        }
        #expect(bound.owner == ownerB)
        #expect(StateCaptureCensus.count(of: .classConflictDemoted) == 0)
      #endif
    }
  }

  // MARK: - Stage 2/3: the bind pass through the central resolver

  @Test("body-captured closures carry their owner when the gate is on")
  func bindPassBindsBodyCapturedClosures() throws {
    try withCaptureBinding(enabled: true) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("BindPassHost")
      let log = ClosureLog()
      _ = Resolver().resolve(CaptureHost(log: log), in: makeContext(graph, identity: identity))
      let write = try #require(log.write)
      let read = try #require(log.read)

      #if DEBUG
        #expect(StateCaptureCensus.count(of: .bindBound) >= 1)
        StateCaptureCensus.resetForTesting()
      #endif
      write("typed")
      #expect(read() == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 2)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
        #expect(StateCaptureCensus.count(of: .ladderExactOwner) == 0)
      #endif

      // Path fidelity: a fresh body evaluation must observe the value the
      // capture-routed write landed — same owner, same slot.
      _ = Resolver().resolve(CaptureHost(log: log), in: makeContext(graph, identity: identity))
      #expect(log.bodyObserved.last == "typed")
    }
  }

  @Test("the bind pass is inert when the gate is off")
  func bindPassInertWhenGateOff() throws {
    try withCaptureBinding(enabled: false) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("BindPassGateOff")
      let log = ClosureLog()
      _ = Resolver().resolve(CaptureHost(log: log), in: makeContext(graph, identity: identity))
      let read = try #require(log.read)

      #if DEBUG
        #expect(StateCaptureCensus.count(of: .bindBound) == 0)
      #endif
      // Today's semantics, pinned: a body-captured closure fired with no
      // dispatch context bottoms out at the authored seed — loudly.
      #expect(read() == "seed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) == 0)
        #expect(StateCaptureCensus.count(of: .seedFallback) >= 1)
      #endif
    }
  }

  @Test("a composed wrapper's nested state binds with its qualified slot path")
  func composedWrapperBindsPathQualifiedCapture() throws {
    try withCaptureBinding(enabled: true) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("ComposedBind")
      let log = ClosureLog()
      _ = Resolver().resolve(ComposedHost(log: log), in: makeContext(graph, identity: identity))
      let write = try #require(log.write)
      let read = try #require(log.read)

      write("typed")
      #expect(read() == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 1)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      #endif

      // The capture-routed write must have landed in the same path-qualified
      // slot resolve-time binding reads: a fresh body evaluation sees it.
      _ = Resolver().resolve(ComposedHost(log: log), in: makeContext(graph, identity: identity))
      #expect(log.bodyObserved.last == "typed")
    }
  }

  // MARK: - Stage 3: remaining body-evaluation edges (§2.5)

  private struct StatefulCaptureModifier: ViewModifier, DynamicProperty {
    @State private var value = "seed"
    let log: ClosureLog

    func body(content: Content) -> some View {
      log.bodyObserved.append(value)
      log.read = { value }
      log.write = { value = $0 }
      return content
    }
  }

  @Test("a composed modifier's state binds as its own root, not a nested field")
  func composedModifierBindsAsOwnRoot() throws {
    try withCaptureBinding(enabled: true) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("ComposedModifierBind")
      let log = ClosureLog()
      _ = Resolver().resolve(
        Text("base").modifier(StatefulCaptureModifier(log: log)),
        in: makeContext(graph, identity: identity)
      )
      let write = try #require(log.write)
      let read = try #require(log.read)

      write("typed")
      #expect(read() == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 2)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      #endif

      // Root-relative path fidelity: the forwarded update pass claims the
      // modifier's slots as its own root, so a capture carrying a nested
      // field path would fork the write into a phantom slot the resolve
      // pass never reads. A fresh body evaluation must observe the
      // capture-routed write.
      _ = Resolver().resolve(
        Text("base").modifier(StatefulCaptureModifier(log: log)),
        in: makeContext(graph, identity: identity)
      )
      #expect(log.bodyObserved.last == "typed")
    }
  }

  @MainActor
  private struct StatefulCaptureButtonStyle: ButtonStyle {
    @State private var value = "seed"
    let log: ClosureLog

    init(log: ClosureLog) {
      self.log = log
    }

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
      log.bodyObserved.append(value)
      log.read = { value }
      log.write = { value = $0 }
      return configuration.label
    }
  }

  private struct StyledHost: View {
    let log: ClosureLog

    var body: some View {
      Button("styled") {}.buttonStyle(StatefulCaptureButtonStyle(log: log))
    }
  }

  @Test("a style struct's state binds before its makeBody runs")
  func styleStructBindsBeforeMakeBody() throws {
    try withCaptureBinding(enabled: true) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("StyleBind")
      let log = ClosureLog()
      // The style seam evaluates under the enclosing body's ambient scope
      // (the owner its `@State` binds against), so the styled control is
      // mounted through a host body, as every real mount is.
      _ = Resolver().resolve(
        StyledHost(log: log),
        in: makeContext(graph, identity: identity)
      )
      let write = try #require(log.write)
      let read = try #require(log.read)

      write("typed")
      #expect(read() == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 2)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      #endif

      _ = Resolver().resolve(
        StyledHost(log: log),
        in: makeContext(graph, identity: identity)
      )
      #expect(log.bodyObserved.last == "typed")
    }
  }

  private struct ResolvableCaptureHost: PrimitiveView, ResolvableView {
    @State private var value = "seed"
    let log: ClosureLog

    func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
      withDynamicPropertyUpdateScope(self, for: context) {
        log.bodyObserved.append(value)
        log.read = { value }
        log.write = { value = $0 }
        return resolveViewElements(Text(value), in: context)
      }
    }
  }

  @Test("a resolvable output forwarded by ScopedBuilder binds before resolving")
  func scopedBuilderResolvableOutputBinds() throws {
    try withCaptureBinding(enabled: true) {
      let graph = ViewGraph()
      graph.beginFrame()
      let identity = testIdentity("ScopedResolvableBind")
      let log = ClosureLog()
      _ = Resolver().resolve(
        ScopedBuilder(scoped: ResolvableCaptureHost(log: log), authoringContext: nil),
        in: makeContext(graph, identity: identity)
      )
      let write = try #require(log.write)
      let read = try #require(log.read)

      write("typed")
      #expect(read() == "typed")
      #if DEBUG
        #expect(StateCaptureCensus.count(of: .captureHit) >= 2)
        #expect(StateCaptureCensus.count(of: .seedFallback) == 0)
      #endif

      _ = Resolver().resolve(
        ScopedBuilder(scoped: ResolvableCaptureHost(log: log), authoringContext: nil),
        in: makeContext(graph, identity: identity)
      )
      #expect(log.bodyObserved.last == "typed")
    }
  }
}
