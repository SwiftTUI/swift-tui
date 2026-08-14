import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

@MainActor
@Suite("FocusState owner lifetime")
struct FocusStateOwnerLifetimeTests {
  @Test("projected graphless bindings do not retain FocusState wrapper storage")
  func projectedGraphlessBindingDoesNotRetainWrapperStorage() {
    let (binding, weakStorage) = makeDetachedGraphlessBinding()
    let (secondBinding, secondWeakStorage) = makeDetachedGraphlessBinding()

    #expect(
      weakStorage.object == nil,
      "a projected binding may retain its fallback cell, but not the wrapper's owner cache"
    )
    #expect(secondWeakStorage.object == nil)
    #expect(
      binding.bindingKey != secondBinding.bindingKey,
      "a retained binding's fallback cell must keep its local identity unavailable for ABA reuse"
    )
    binding.wrappedValue = true
    #expect(
      binding.wrappedValue,
      "detaching wrapper storage must not make a retained graphless binding immutable"
    )
    #expect(!secondBinding.wrappedValue)
  }

  @Test("discarded graph-owned FocusState owners do not accumulate")
  func discardedGraphOwnedOwnersDoNotAccumulate() {
    let weakStorages = (0..<64).map { _ in
      makeDiscardedGraphOwnedStorageReference()
    }

    #expect(
      weakStorages.allSatisfy { $0.object == nil },
      "stored locations must not keep every retired FocusState owner alive"
    )
  }

  @Test("a retained FocusState binding does not retain its retired owner node")
  func retainedBindingDoesNotRetainRetiredOwnerNode() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let identity = testIdentity("FocusOwnerLifetime", "deallocation")
    let probe = FocusOwnerLifetimeProbe(capture: capture)

    resolve(probe, identity: identity, graph: graph)
    let binding = try #require(capture.binding)
    var owner = graph.nodeForIdentity(identity)
    let weakOwner = try makeWeakFocusOwnerReference(owner)

    graph.beginFrame()
    graph.removeSubtree(rootedAt: try #require(owner))
    owner = nil

    _ = binding
    #expect(
      weakOwner.node == nil,
      "callback-facing FocusState locations must not strongly pin retired graph nodes"
    )
  }

  @Test("a retired FocusState binding does not follow identity into a replacement owner")
  func retiredBindingDoesNotFollowReplacementIdentity() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let identity = testIdentity("FocusOwnerLifetime", "replacement")
    let probe = FocusOwnerLifetimeProbe(capture: capture)

    resolve(probe, identity: identity, graph: graph)
    let retiredBinding = try #require(capture.binding)
    let resolvedOwner = try #require(graph.nodeForIdentity(identity))
    var retiredOwner: SwiftTUICore.ViewNode? = resolvedOwner
    let retiredNodeID = resolvedOwner.viewNodeID

    graph.beginFrame()
    graph.removeSubtree(rootedAt: try #require(retiredOwner))
    retiredOwner = nil
    resolve(probe, identity: identity, graph: graph)

    let liveOwner = try #require(graph.nodeForIdentity(identity))
    let liveBinding = try #require(capture.binding)
    #expect(liveOwner.viewNodeID != retiredNodeID)
    #expect(liveBinding.bindingKey != retiredBinding.bindingKey)
    #expect(liveBinding.registrationValue == false)

    retiredBinding.wrappedValue = true

    #expect(
      liveBinding.registrationValue == false,
      "an authored identity match must not redirect a stale binding into a new owner lifetime"
    )
    #expect(
      retiredBinding.wrappedValue,
      "the stale binding keeps its owner-scoped fallback value after its owner retires"
    )
  }

  @Test("a retired FocusState runtime registration is a strict no-op")
  func retiredRuntimeRegistrationDoesNotMutateFallbackOrReplacement() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let identity = testIdentity("FocusOwnerLifetime", "runtime-no-op")
    let probe = FocusOwnerLifetimeProbe(capture: capture)

    resolve(probe, identity: identity, graph: graph)
    let retiredBinding = try #require(capture.binding)
    let observedGeneration = retiredBinding.requestGeneration
    let resolvedOwner = try #require(graph.nodeForIdentity(identity))
    var retiredOwner: SwiftTUICore.ViewNode? = resolvedOwner

    graph.beginFrame()
    graph.removeSubtree(rootedAt: try #require(retiredOwner))
    retiredOwner = nil
    resolve(probe, identity: identity, graph: graph)
    let liveBinding = try #require(capture.binding)

    #expect(
      !retiredBinding.applyRuntimeValue(
        true,
        observedRequestGeneration: observedGeneration,
        registrationIdentity: identity
      )
    )
    #expect(retiredBinding.registrationValue == false)
    #expect(liveBinding.registrationValue == false)
  }

  @Test("a FocusState authored request and binding key survive checkpoint restoration")
  func authoredRequestAndBindingKeySurviveCheckpointRestore() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let identity = testIdentity("FocusOwnerLifetime", "checkpoint-key")
    let probe = FocusOwnerLifetimeProbe(capture: capture)

    resolve(probe, identity: identity, graph: graph)
    let before = try #require(capture.binding)
    let checkpoint = graph.makeCheckpoint()

    graph.restoreCheckpoint(checkpoint)
    before.wrappedValue = true
    resolve(probe, identity: identity, graph: graph)
    let restored = try #require(capture.binding)

    #expect(restored.bindingKey == before.bindingKey)
    #expect(restored.registrationValue)
    #expect(restored.hasPendingRequest)
  }

  @Test("a runtime FocusState flip invalidates only its registration scope")
  func runtimeFlipInvalidatesOnlyRegistrationScope() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("FocusOwnerLifetime", "runtime-invalidation-owner")
    let registrationIdentity = testIdentity(
      "FocusOwnerLifetime",
      "runtime-invalidation-registration"
    )

    resolve(FocusOwnerLifetimeProbe(capture: capture), identity: ownerIdentity, graph: graph)
    let binding = try #require(capture.binding)
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    let invalidator = FocusOwnerLifetimeInvalidator()
    owner.invalidator = invalidator

    #expect(
      binding.applyRuntimeValue(
        true,
        observedRequestGeneration: binding.requestGeneration,
        registrationIdentity: registrationIdentity
      )
    )

    let invalidated = invalidator.requests.reduce(into: Set<Identity>()) {
      $0.formUnion($1)
    }
    #expect(invalidated == [registrationIdentity])
    #expect(!invalidated.contains(ownerIdentity))
    #expect(
      graph.debugTotalStateSnapshot().stateMutationKeys.contains {
        $0.owner == owner.ownerLifetimeID
      },
      "the scoped runtime write must remain checkpoint-overlay currency"
    )
  }

  @Test("clearing an equal FocusState request does not invalidate its owner")
  func equalRuntimeApplyDoesNotInvalidateOwner() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("FocusOwnerLifetime", "equal-runtime-owner")
    let registrationIdentity = testIdentity(
      "FocusOwnerLifetime",
      "equal-runtime-registration"
    )

    resolve(FocusOwnerLifetimeReadingProbe(capture: capture), identity: ownerIdentity, graph: graph)
    let binding = try #require(capture.binding)
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    let invalidator = FocusOwnerLifetimeInvalidator()
    owner.invalidator = invalidator
    _ = graph.finalizeFrame(rootIdentity: ownerIdentity)

    binding.wrappedValue = false
    let authoredGeneration = binding.requestGeneration
    #expect(binding.hasPendingRequest)
    invalidator.requests.removeAll()
    _ = graph.finalizeFrame(rootIdentity: ownerIdentity)
    #expect(graph.debugTotalStateSnapshot().graphLocalDirtyNodeIDs.isEmpty)

    #expect(
      !binding.applyRuntimeValue(
        false,
        observedRequestGeneration: authoredGeneration,
        registrationIdentity: registrationIdentity
      )
    )
    #expect(!binding.hasPendingRequest)
    #expect(
      invalidator.requests.isEmpty,
      "clearing pending bookkeeping for an equal value must not invalidate the owner cone"
    )
    let state = graph.debugTotalStateSnapshot()
    #expect(
      state.graphLocalDirtyNodeIDs.isEmpty,
      "an equal runtime apply must not leave a genuine value reader graph-dirty"
    )
    #expect(
      state.stateMutationKeys.contains { $0.owner == owner.ownerLifetimeID },
      "pending-bookkeeping mutation must remain checkpoint-overlay currency"
    )
  }

  @Test("a changed FocusState runtime apply dirties its reader exactly once")
  func changedRuntimeApplyInvalidatesReaderExactlyOnce() throws {
    let capture = FocusOwnerLifetimeCapture()
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("FocusOwnerLifetime", "changed-runtime-reader")
    let registrationIdentity = testIdentity(
      "FocusOwnerLifetime",
      "changed-runtime-registration"
    )

    resolve(FocusOwnerLifetimeReadingProbe(capture: capture), identity: ownerIdentity, graph: graph)
    let binding = try #require(capture.binding)
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    let invalidator = FocusOwnerLifetimeInvalidator()
    owner.invalidator = invalidator

    #expect(
      binding.applyRuntimeValue(
        true,
        observedRequestGeneration: binding.requestGeneration,
        registrationIdentity: registrationIdentity
      )
    )

    #expect(invalidator.requests == [[ownerIdentity, registrationIdentity]])
    #expect(graph.debugTotalStateSnapshot().graphLocalDirtyNodeIDs == [owner.viewNodeID])
  }

  private func resolve<Content: View>(
    _ probe: Content,
    identity: Identity,
    graph: ViewGraph
  ) {
    graph.beginFrame()
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
  }
}

@MainActor
private func makeDetachedGraphlessBinding() -> (
  FocusState<Bool>.Binding,
  WeakFocusStorageReference
) {
  let focus = FocusState<Bool>()
  let weakStorage = WeakFocusStorageReference(focus.debugStorageObject)
  return (focus.projectedValue, weakStorage)
}

@MainActor
private func makeDiscardedGraphOwnedStorageReference() -> WeakFocusStorageReference {
  let capture = FocusOwnerLifetimeCapture()
  let probe = FocusOwnerLifetimeProbe(capture: capture)
  let graph = ViewGraph()
  let identity = testIdentity("FocusOwnerLifetime", "discarded-owner")

  graph.beginFrame()
  var context = ResolveContext(
    identity: identity,
    environmentValues: .init(),
    applyEnvironmentValues: true
  )
  context.viewGraph = graph
  _ = Resolver().resolve(probe, in: context)
  let weakStorage = WeakFocusStorageReference(capture.storageObject)
  capture.binding = nil
  if let owner = graph.nodeForIdentity(identity) {
    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)
  }
  return weakStorage
}

@MainActor
private final class FocusOwnerLifetimeCapture {
  var binding: FocusState<Bool>.Binding?
  weak var storageObject: AnyObject?
}

@MainActor
private struct FocusOwnerLifetimeProbe: View {
  @FocusState(line: 901, column: 17) private var focused: Bool
  let capture: FocusOwnerLifetimeCapture

  var body: some View {
    capture.storageObject = _focused.debugStorageObject
    capture.binding = $focused
    return Text("focus")
  }
}

@MainActor
private struct FocusOwnerLifetimeReadingProbe: View {
  @FocusState(line: 902, column: 17) private var focused: Bool
  let capture: FocusOwnerLifetimeCapture

  var body: some View {
    capture.storageObject = _focused.debugStorageObject
    capture.binding = $focused
    return Text("focus \(focused)")
  }
}

@MainActor
private final class WeakFocusOwnerReference {
  weak var node: SwiftTUICore.ViewNode?

  init(_ node: SwiftTUICore.ViewNode) {
    self.node = node
  }
}

@MainActor
private final class WeakFocusStorageReference {
  weak var object: AnyObject?

  init(_ object: AnyObject?) {
    self.object = object
  }
}

private final class FocusOwnerLifetimeInvalidator: Invalidating {
  var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}

@MainActor
private func makeWeakFocusOwnerReference(
  _ node: SwiftTUICore.ViewNode?
) throws -> WeakFocusOwnerReference {
  WeakFocusOwnerReference(try #require(node))
}
