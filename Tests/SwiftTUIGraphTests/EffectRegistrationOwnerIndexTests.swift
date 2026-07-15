import Testing

@testable import SwiftTUIGraph

/// Coverage for the F148 effect-owner index: `republishAllEffectRegistrations`
/// iterates `effectRegistrationOwnerNodeIDs` — a maintained superset of the
/// nodes whose recorded handlers hold a lifecycle/task/preference-observation
/// registration — instead of every live node. The contract is byte-equivalence
/// with the historical every-live-node walk, which the first test pins
/// VERBATIM as its reference; the remaining tests pin the index maintenance
/// seams (liveness gating, removal prune, adoption enrollment, and
/// capture-session resets leaving harmless superset entries).
@MainActor
@Suite
struct EffectRegistrationOwnerIndexTests {
  private static let effectKinds: [RuntimeRegistrationKind] = [
    .lifecycle, .task, .preferenceObservation,
  ]

  @Test("scoped republication matches the historical every-live-node walk")
  func republicationMatchesTheHistoricalWalk() {
    let graph = ViewGraph()
    graph.beginFrame()
    let lifecycleOwner = graph.beginEvaluation(
      identity: testIdentity("Root", "Lifecycle"), invalidator: nil)
    let taskOwner = graph.beginEvaluation(
      identity: testIdentity("Root", "Task"), invalidator: nil)
    let preferenceOwner = graph.beginEvaluation(
      identity: testIdentity("Root", "Preference"), invalidator: nil)
    let actionOnly = graph.beginEvaluation(
      identity: testIdentity("Root", "ActionOnly"), invalidator: nil)
    let empty = graph.beginEvaluation(
      identity: testIdentity("Root", "Empty"), invalidator: nil)

    ViewNodeContext.withValue(lifecycleOwner) {
      RegistrationKindDriver.record(.lifecycle, on: lifecycleOwner, identity: lifecycleOwner.identity)
    }
    ViewNodeContext.withValue(taskOwner) {
      RegistrationKindDriver.record(.task, on: taskOwner, identity: taskOwner.identity)
    }
    ViewNodeContext.withValue(preferenceOwner) {
      RegistrationKindDriver.record(
        .preferenceObservation, on: preferenceOwner, identity: preferenceOwner.identity)
    }
    ViewNodeContext.withValue(actionOnly) {
      RegistrationKindDriver.record(.action, on: actionOnly, identity: actionOnly.identity)
    }

    let allNodes = [lifecycleOwner, taskOwner, preferenceOwner, actionOnly, empty]
    graph.liveNodeIDs = Set(allNodes.map(\.viewNodeID))

    // The index enrolls exactly the effect owners: action-only and empty
    // nodes never note ownership.
    #expect(
      graph.effectRegistrationOwnerNodeIDs
        == Set([lifecycleOwner, taskOwner, preferenceOwner].map(\.viewNodeID))
    )

    // The historical walk, verbatim: reset the three effect registries, then
    // restore from EVERY live node.
    let historical = RuntimeRegistrationSet.scratch()
    historical.lifecycleRegistry?.reset()
    historical.taskRegistry?.reset()
    historical.preferenceObservationRegistry?.reset()
    for nodeID in graph.liveNodeIDs {
      graph.nodesByNodeID[nodeID]?.restoreOwnEffectRegistrations(into: historical)
    }

    let scoped = RuntimeRegistrationSet.scratch()
    graph.republishAllEffectRegistrations(into: scoped)

    let historicalFingerprint = historical.publicationOracleFingerprint()
    // Non-vacuity anchor: the reference walk must project all three effect
    // families' namespaces before the equality below means anything.
    #expect(
      RegistrationKindDriver.fingerprintNamespaces(historicalFingerprint).count
        >= Self.effectKinds.count
    )
    #expect(scoped.publicationOracleFingerprint() == historicalFingerprint)
  }

  @Test("a map-resident owner outside the live set restores nothing, matching the historical walk")
  func nonLiveOwnerRestoresNothing() {
    let graph = ViewGraph()
    graph.beginFrame()
    let detachedOwner = graph.beginEvaluation(
      identity: testIdentity("Root", "Detached"), invalidator: nil)
    let liveEmpty = graph.beginEvaluation(
      identity: testIdentity("Root", "LiveEmpty"), invalidator: nil)

    ViewNodeContext.withValue(detachedOwner) {
      RegistrationKindDriver.record(.task, on: detachedOwner, identity: detachedOwner.identity)
    }
    // The owner stays in `nodesByNodeID` (detached-hosted shape) but is not
    // live this frame; membership in the index is independent of liveness.
    graph.liveNodeIDs = [liveEmpty.viewNodeID]
    #expect(graph.effectRegistrationOwnerNodeIDs.contains(detachedOwner.viewNodeID))

    let scoped = RuntimeRegistrationSet.scratch()
    graph.republishAllEffectRegistrations(into: scoped)
    #expect(scoped.publicationOracleFingerprint().isEmpty)

    // Returning to the live set re-exposes the owner without re-recording —
    // the index kept it while the node was resident.
    graph.liveNodeIDs = [detachedOwner.viewNodeID, liveEmpty.viewNodeID]
    let relive = RuntimeRegistrationSet.scratch()
    graph.republishAllEffectRegistrations(into: relive)
    #expect(!relive.publicationOracleFingerprint().isEmpty)
  }

  @Test("subtree removal prunes the owner index with the node store")
  func subtreeRemovalPrunesTheIndex() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = graph.beginEvaluation(
      identity: testIdentity("Root", "Removed"), invalidator: nil)
    ViewNodeContext.withValue(owner) {
      RegistrationKindDriver.record(.task, on: owner, identity: owner.identity)
    }
    graph.liveNodeIDs = [owner.viewNodeID]
    #expect(graph.effectRegistrationOwnerNodeIDs.contains(owner.viewNodeID))

    // A node visited in the CURRENT frame that owns its identity index entry
    // is deliberately spared by the removal cascade (the stranded same-frame
    // mint keep-guard). Advance a frame so the node reads as genuinely
    // departing before tearing it down.
    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)

    #expect(graph.nodesByNodeID[owner.viewNodeID] == nil)
    #expect(!graph.effectRegistrationOwnerNodeIDs.contains(owner.viewNodeID))
  }

  @Test("registration adoption enrolls the absorber as an effect owner")
  func adoptionEnrollsTheAbsorber() {
    let graph = ViewGraph()
    graph.beginFrame()
    let departing = graph.beginEvaluation(
      identity: testIdentity("Root", "Departing"), invalidator: nil)
    let absorber = graph.beginEvaluation(
      identity: testIdentity("Root", "Absorber"), invalidator: nil)

    ViewNodeContext.withValue(departing) {
      RegistrationKindDriver.record(.task, on: departing, identity: departing.identity)
    }
    #expect(!graph.effectRegistrationOwnerNodeIDs.contains(absorber.viewNodeID))

    absorber.adoptRuntimeRegistrations(from: departing)
    #expect(graph.effectRegistrationOwnerNodeIDs.contains(absorber.viewNodeID))

    // Only the absorber is live (the departing node is being reclaimed); its
    // adopted task entries must still reach the republication.
    graph.liveNodeIDs = [absorber.viewNodeID]
    let scoped = RuntimeRegistrationSet.scratch()
    graph.republishAllEffectRegistrations(into: scoped)
    #expect(!scoped.publicationOracleFingerprint().isEmpty)
  }

  @Test("a capture-session reset leaves a superset entry that restores nothing")
  func captureSessionResetLeavesHarmlessSupersetEntry() {
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(
      identity: testIdentity("Root", "Reset"), invalidator: nil)

    ViewNodeContext.withValue(node) {
      RegistrationKindDriver.record(.task, on: node, identity: node.identity)
    }
    // Entering a new capture session resets the node's recorded registrations
    // (publication replaces, not accumulates); the re-capture records no
    // effect family.
    ViewNodeContext.withValue(node) {
      RegistrationKindDriver.record(.action, on: node, identity: node.identity)
    }
    #expect(!node.registeredHandlers.hasEffectRegistrations)
    // The index deliberately keeps the node — membership is a superset and
    // only decides which nodes are looked at.
    #expect(graph.effectRegistrationOwnerNodeIDs.contains(node.viewNodeID))

    graph.liveNodeIDs = [node.viewNodeID]
    let scoped = RuntimeRegistrationSet.scratch()
    graph.republishAllEffectRegistrations(into: scoped)
    #expect(scoped.publicationOracleFingerprint().isEmpty)
  }
}
