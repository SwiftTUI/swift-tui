import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
private final class LeaseCapture {
  var lease: DynamicPropertyInvalidationLease?
  var ownerIdentity: Identity?
  var updateCount = 0
  var bodyCount = 0
  var observedIsEnabled: [Bool] = []
  var result: DynamicPropertyUpdateResult = .unchanged
}

@propertyWrapper
@MainActor
private struct LeaseBackedProperty: DynamicProperty {
  @Environment(\.isEnabled) private var isEnabled
  private let capture: LeaseCapture
  private let result: DynamicPropertyUpdateResult

  init(
    capture: LeaseCapture,
    result: DynamicPropertyUpdateResult = .unchanged
  ) {
    self.capture = capture
    self.result = result
    capture.result = result
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    capture.updateCount += 1
    capture.lease = context.invalidationLease
    capture.ownerIdentity = currentAuthoringContext()?.viewIdentity
    capture.observedIsEnabled.append(isEnabled)
    return capture.result
  }

  var wrappedValue: Int { 0 }
}

@MainActor
private struct LeaseHost: View {
  @LeaseBackedProperty private var value: Int
  private let capture: LeaseCapture
  private let result: DynamicPropertyUpdateResult

  init(
    capture: LeaseCapture,
    result: DynamicPropertyUpdateResult = .unchanged
  ) {
    self.capture = capture
    self.result = result
    _value = LeaseBackedProperty(capture: capture, result: result)
  }

  var body: some View {
    capture.bodyCount += 1
    Text("\(value)")
  }
}

extension LeaseHost: @MainActor Equatable {
  static func == (lhs: LeaseHost, rhs: LeaseHost) -> Bool {
    lhs.capture === rhs.capture && lhs.result == rhs.result
  }
}

@MainActor
private struct LeaseBoundaryRoot<Content: View>: View {
  let content: Content

  var body: some View {
    VStack {
      content
      Text("static sibling")
    }
  }
}

@MainActor
private struct LeaseTransparentMemoModifier: PrimitiveViewModifier, Equatable {
  func dynamicPropertyContentPreparation<Base: View>(
    content _: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveContext? {
    context
  }

  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    content.resolveElements(in: context)
  }
}

@MainActor
private struct LeaseStructuralDefaultModifier: PrimitiveViewModifier {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    content.resolveElements(
      in: context.child(component: .named("custom-base"))
    )
  }
}

@MainActor
private struct BuiltinLeaseHost: View {
  @State private var value = 0

  var body: some View {
    Text("\(value)")
  }
}

@MainActor
private struct LeaseModifier: ViewModifier {
  @LeaseBackedProperty private var value: Int

  init(capture: LeaseCapture) {
    _value = LeaseBackedProperty(capture: capture)
  }

  func body(content: Content) -> some View {
    content
  }
}

private final class LeaseInvalidationRecorder: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}

@MainActor
@Suite("DynamicProperty invalidation lease")
struct DynamicPropertyLeaseTests {
  private func resolve(
    capture: LeaseCapture,
    graph: ViewGraph,
    identity: Identity,
    invalidatedIdentities: Set<Identity> = []
  ) {
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: invalidatedIdentities,
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(LeaseHost(capture: capture), in: context)
  }

  @Test("framework built-ins do not allocate async lease registrations")
  func builtinsKeepTheLeasePathCold() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "builtin")
    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(BuiltinLeaseHost(), in: context)

    let node = try #require(graph.nodeForIdentity(identity))
    #expect(node.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)
  }

  private func drainMainActorJobs() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }

  @Test("a lease can invalidate its exact live owner from another executor")
  func liveLeaseInvalidatesFromAnotherExecutor() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "live")
    graph.beginFrame()
    resolve(capture: capture, graph: graph, identity: identity)

    let recorder = LeaseInvalidationRecorder()
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder
    let lease = try #require(capture.lease)
    await Task.detached { lease.invalidate() }.value
    await drainMainActorJobs()

    #expect(recorder.requests.contains([identity]))
  }

  @Test("a superseded registration generation cannot invalidate the replacement")
  func supersededLeaseIsInert() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "generation")
    graph.beginFrame()
    resolve(capture: capture, graph: graph, identity: identity)
    let first = try #require(capture.lease)

    let recorder = LeaseInvalidationRecorder()
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder
    graph.beginFrame()
    resolve(
      capture: capture,
      graph: graph,
      identity: identity,
      invalidatedIdentities: [identity]
    )
    let second = try #require(capture.lease)
    // The lightweight resolve helper does not install a runtime invalidation
    // proxy, so its fresh evaluation clears the node's weak invalidator. Bind
    // the recorder to the live replacement registration before firing either
    // generation.
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder

    first.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.isEmpty)

    second.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.contains([identity]))
  }

  @Test("a lease becomes inert when a fresh evaluation removes its wrapper")
  func disappearedWrapperLeaseIsInertInSameFrame() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "disappeared")
    graph.beginFrame()
    resolve(capture: capture, graph: graph, identity: identity)
    let departed = try #require(capture.lease)

    let recorder = LeaseInvalidationRecorder()
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: [identity],
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(Text("replacement"), in: context)

    let node = try #require(graph.nodeForIdentity(identity))
    #expect(node.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)

    node.invalidator = recorder
    departed.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.isEmpty)
  }

  @Test("a retained reuse removes a lease absent from the current value")
  func retainedReusePrunesDisappearedWrapperLease() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "reuse-disappeared")
    let unrelated = testIdentity("DynamicPropertyLease", "unrelated")

    graph.beginFrame()
    resolve(capture: capture, graph: graph, identity: identity)
    _ = graph.finalizeFrame(rootIdentity: identity)
    let departed = try #require(capture.lease)
    #expect(capture.updateCount == 1)

    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: [unrelated],
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(Text("replacement"), in: context)
    _ = graph.finalizeFrame(rootIdentity: identity)

    let node = try #require(graph.nodeForIdentity(identity))
    #expect(node.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)
    let recorder = LeaseInvalidationRecorder()
    node.invalidator = recorder
    departed.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.isEmpty)
  }

  @Test("a transparent primitive modifier updates a base lease exactly once")
  func transparentModifierForwardsLeaseUpdateExactlyOnce() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "transparent-modifier")
    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(LeaseHost(capture: capture).disabled(true), in: context)

    #expect(capture.updateCount == 1)
    let lease = try #require(capture.lease)
    let recorder = LeaseInvalidationRecorder()
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder
    lease.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.contains([identity]))
  }

  @Test("a structural primitive updates its base lease once at the declared child node")
  func structuralModifierOwnsTheExactBaseNodeLease() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "structural-overlay")
    let context = leaseContext(graph, identity: identity)
    let baseIdentity = context.child(component: .named("base")).identity

    graph.beginFrame()
    _ = Resolver().resolve(
      LeaseHost(capture: capture).overlay { Text("overlay") },
      in: context
    )

    #expect(capture.updateCount == 1)
    #expect(capture.ownerIdentity == baseIdentity)
    let outerNode = try #require(graph.nodeForIdentity(identity))
    let baseNode = try #require(graph.nodeForIdentity(baseIdentity))
    #expect(outerNode.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)
    #expect(baseNode.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.count == 1)

    let recorder = LeaseInvalidationRecorder()
    baseNode.invalidator = recorder
    try #require(capture.lease).invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests == [[baseIdentity]])
  }

  @Test("an unknown primitive defaults to child-owned DynamicProperty traversal")
  func unknownPrimitiveDefaultsToItsActualContentNode() throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "custom-structural")
    let context = leaseContext(graph, identity: identity)
    let baseIdentity = context.child(component: .named("custom-base")).identity

    graph.beginFrame()
    _ = Resolver().resolve(
      LeaseHost(capture: capture).modifier(LeaseStructuralDefaultModifier()),
      in: context
    )

    #expect(capture.updateCount == 1)
    #expect(capture.ownerIdentity == baseIdentity)
    let outerNode = try #require(graph.nodeForIdentity(identity))
    let baseNode = try #require(graph.nodeForIdentity(baseIdentity))
    #expect(outerNode.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)
    #expect(baseNode.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.count == 1)
  }

  @Test("an ID modifier updates its base lease once at the entity-routed owner")
  func identityModifierOwnsTheEntityRoutedBaseLease() throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "entity-route")
    let routedIdentity = identity.explicitID("lease-entity")
    let entityIdentity = EntityIdentity("lease-entity")

    graph.beginFrame()
    _ = Resolver().resolve(
      LeaseHost(capture: capture).id("lease-entity"),
      in: leaseContext(graph, identity: identity)
    )

    #expect(capture.updateCount == 1)
    #expect(capture.ownerIdentity == routedIdentity)
    let routedNode = try #require(graph.nodeForEntityIdentity(entityIdentity))
    #expect(routedNode.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.count == 1)
  }

  @Test("transparent unchanged reuse pre-updates its transformed base and keeps the new lease live")
  func transparentReuseKeepsSecondFrameBaseLeaseLive() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "transparent-reuse")
    let view = LeaseBoundaryRoot(
      content: LeaseHost(capture: capture)
        .modifier(LeaseTransparentMemoModifier())
        .modifier(LeaseTransparentMemoModifier())
        .environment(\.isEnabled, false)
    )

    graph.beginFrame()
    _ = Resolver().resolve(view, in: leaseContext(graph, identity: identity))
    let firstFrame = graph.snapshot(rootIdentity: identity)
    _ = graph.finalizeFrame(rootIdentity: identity)
    #expect(capture.updateCount == 1)
    #expect(capture.bodyCount == 1)
    #expect(capture.observedIsEnabled == [false])
    #expect(
      capture.ownerIdentity != identity,
      "fixture must place the modifier below the invalidated root")
    let siblingIdentity = try #require(staticSiblingIdentity(in: firstFrame))

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: leaseContext(
        graph,
        identity: identity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    #expect(capture.updateCount == 2)
    #expect(capture.bodyCount == 1)
    #expect(capture.observedIsEnabled == [false, false])
    let ownerIdentity = try #require(capture.ownerIdentity)
    let node = try #require(graph.nodeForIdentity(ownerIdentity))
    #expect(!node.debugTotalStateSnapshot().dynamicPropertyLeaseTokens.isEmpty)
    let recorder = LeaseInvalidationRecorder()
    node.invalidator = recorder
    try #require(capture.lease).invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.contains([ownerIdentity]))

    // The frame-2 memo serve leaves its prepared base entry unconsumed. It
    // must be discarded with that resolve invocation rather than bleed into
    // the next same-identity/same-type occurrence and hide a changed result.
    capture.result = .changed
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: leaseContext(
        graph,
        identity: identity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: identity)
    #expect(capture.updateCount == 3)
    #expect(capture.bodyCount == 2)
  }

  @Test("a changed transparent base result denies the outer reuse door")
  func changedTransparentBaseResultPropagatesBeforeReuse() throws {
    try assertBaseResultDeniesOuterReuse(.changed, suffix: "changed")
  }

  @Test("an uncertified transparent base result denies the outer reuse door")
  func uncertifiedTransparentBaseResultPropagatesBeforeReuse() throws {
    try assertBaseResultDeniesOuterReuse(.uncertified, suffix: "uncertified")
  }

  private func assertBaseResultDeniesOuterReuse(
    _ result: DynamicPropertyUpdateResult,
    suffix: String
  ) throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "transparent-result-\(suffix)")
    let view = LeaseBoundaryRoot(
      content: LeaseHost(capture: capture)
        .modifier(LeaseTransparentMemoModifier())
        .environment(\.isEnabled, false)
    )

    graph.beginFrame()
    _ = Resolver().resolve(view, in: leaseContext(graph, identity: identity))
    let firstFrame = graph.snapshot(rootIdentity: identity)
    _ = graph.finalizeFrame(rootIdentity: identity)
    let siblingIdentity = try #require(staticSiblingIdentity(in: firstFrame))
    capture.result = result
    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: leaseContext(
        graph,
        identity: identity,
        invalidatedIdentities: [siblingIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: identity)

    #expect(capture.updateCount == 2)
    #expect(capture.bodyCount == 2)
    #expect(capture.observedIsEnabled == [false, false])
  }

  private func staticSiblingIdentity(in root: ResolvedNode) -> Identity? {
    var textIdentities: [Identity] = []
    var work = [root]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        textIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    return textIdentities.last
  }

  private func leaseContext(
    _ graph: ViewGraph,
    identity: Identity,
    invalidatedIdentities: Set<Identity> = []
  ) -> ResolveContext {
    var environment = EnvironmentValues()
    environment.isEnabled = false
    var context = ResolveContext(
      identity: identity,
      environmentValues: environment,
      invalidatedIdentities: invalidatedIdentities,
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  @Test("same-type transparent modifiers receive distinct live leases")
  func repeatedModifierLeaseOccurrencesDoNotAlias() async throws {
    let outer = LeaseCapture()
    let inner = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "modifier-occurrences")
    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(
      Text("base")
        .modifier(LeaseModifier(capture: inner))
        .modifier(LeaseModifier(capture: outer)),
      in: context
    )

    #expect(inner.updateCount == 1)
    #expect(outer.updateCount == 1)
    let innerLease = try #require(inner.lease)
    let outerLease = try #require(outer.lease)
    let recorder = LeaseInvalidationRecorder()
    let node = try #require(graph.nodeForIdentity(identity))
    node.invalidator = recorder

    innerLease.invalidate()
    outerLease.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.count == 2)
    #expect(recorder.requests.allSatisfy { $0 == [identity] })
  }

  @Test("checkpoint rollback restores the old lease and revokes the draft lease")
  func abortedDraftLeaseIsInert() async throws {
    let capture = LeaseCapture()
    let graph = ViewGraph()
    let identity = testIdentity("DynamicPropertyLease", "rollback")
    let recorder = LeaseInvalidationRecorder()
    graph.beginFrame()
    resolve(capture: capture, graph: graph, identity: identity)
    try #require(graph.nodeForIdentity(identity)).invalidator = recorder
    let committed = try #require(capture.lease)
    let checkpoint = graph.makeCheckpoint()

    graph.beginFrame()
    resolve(
      capture: capture,
      graph: graph,
      identity: identity,
      invalidatedIdentities: [identity]
    )
    let aborted = try #require(capture.lease)
    graph.restoreCheckpoint(checkpoint)

    aborted.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.isEmpty)

    committed.invalidate()
    await drainMainActorJobs()
    #expect(recorder.requests.contains([identity]))
  }

  @Test("a lease becomes inert when its graph retires")
  func retiredGraphLeaseIsInert() async throws {
    let identity = testIdentity("DynamicPropertyLease", "retired-graph")
    let recorder = LeaseInvalidationRecorder()
    var graph: ViewGraph? = ViewGraph()
    graph?.beginFrame()
    // Issue directly from a graph node rather than through `resolveView`,
    // whose stored dirty-frontier evaluator intentionally keeps its captured
    // resolution session alive. The lease itself must not add such a lifetime
    // edge.
    let node = try #require(
      graph?.prepareDynamicPropertyUpdate(identity: identity, entityIdentity: nil)
    )
    node.invalidator = recorder
    let departed = ViewNodeContext.withCurrentValue(node) {
      DynamicPropertyContext.current(
        containerType: LeaseHost.self,
        structuralPath: "root",
        fieldPath: "0"
      ).invalidationLease
    }

    graph = nil
    departed.invalidate()
    await drainMainActorJobs()

    #expect(recorder.requests.isEmpty)
  }
}
