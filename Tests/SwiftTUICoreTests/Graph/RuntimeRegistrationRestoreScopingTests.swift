import Testing

@testable import SwiftTUICore

/// Soundness guard for the scoped `.subtrees` runtime-registration restore
/// (commit_ms Fix 2). A narrow invalidation must leave the live registry
/// **byte-identical** to a full rebuild — including the order of the global
/// append-ordered focus lists, whose `desiredFocusRequest` returns the first
/// matching entry. The changed subtree sorts BEFORE the unchanged one here, so
/// without order normalization the scoped restore would re-append the changed
/// subtree's focus entries last and diverge from a full rebuild.
@MainActor
@Suite
struct RuntimeRegistrationRestoreScopingTests {
  @Test("scoped .subtrees restore is byte-identical to a full rebuild (focus order)")
  func scopedSubtreeRestoreMatchesFullRebuild() {
    let rootIdentity = testIdentity("Root")
    // "A" sorts before "B", and the invalidated subtree is A — the case where a
    // naive append-at-end scoped restore would put A's focus entries last.
    let aIdentity = testIdentity("Root", "A")
    let bIdentity = testIdentity("Root", "B")
    let namespace = MatchedGeometryNamespace(0)

    let graph = ViewGraph()
    seedTwoFocusableSiblings(
      graph: graph,
      rootIdentity: rootIdentity,
      aIdentity: aIdentity,
      bIdentity: bIdentity,
      namespace: namespace
    )

    // Frame 1: full publish into the live registry — the canonical order.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)

    // Frame 2: narrowly re-evaluate ONLY subtree A (B is untouched), then
    // commit with a `.subtrees([A])` publication — the scoped restore path.
    graph.beginFrame()
    let aNode = graph.beginEvaluation(identity: aIdentity, invalidator: nil)
    recordFocus(on: aNode, identity: aIdentity, namespace: namespace)
    graph.finishEvaluation(
      aNode,
      resolved: ResolvedNode(identity: aIdentity, kind: .view("A")),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    graphDraft.recordDirtyEvaluationPlan(.init(frontierIdentities: [aIdentity]))
    graphDraft.commitRuntimeRegistrations(from: graph)

    // Oracle: a full rebuild of the same committed graph.
    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    // Default-focus snapshot is Equatable: this compares scope/candidate ORDER.
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
    // Focus-binding snapshots carry closures (not Equatable); compare the
    // identity ORDER, which is what `desiredFocusRequest` iterates.
    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
    // Both subtrees' candidates must still be present (scoped restore must not
    // drop the unchanged subtree B).
    let candidates = liveRegistrations.defaultFocusRegistry?.snapshot().candidates ?? []
    #expect(candidates.map(\.identity) == [aIdentity, bIdentity])
  }

  @Test(".unchanged commit re-publishes nothing — registry stays byte-identical (no focus dup)")
  func unchangedCommitLeavesRegistryByteIdentical() {
    let rootIdentity = testIdentity("Root")
    let aIdentity = testIdentity("Root", "A")
    let bIdentity = testIdentity("Root", "B")
    let namespace = MatchedGeometryNamespace(0)

    let graph = ViewGraph()
    seedTwoFocusableSiblings(
      graph: graph,
      rootIdentity: rootIdentity,
      aIdentity: aIdentity,
      bIdentity: bIdentity,
      namespace: namespace
    )

    // Full publish into the live registry — the canonical state.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)

    // Commit an `.unchanged` frame: nothing was re-evaluated, so no dirty plan is
    // recorded and the publication stays at its `.unchanged` default. Committing
    // must NOT re-publish (which would append duplicate focus candidates).
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    graphDraft.commitRuntimeRegistrations(from: graph)

    // Oracle: a full rebuild of the same committed graph.
    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
    // No duplication: exactly the two candidates, once each.
    let candidates = liveRegistrations.defaultFocusRegistry?.snapshot().candidates ?? []
    #expect(candidates.map(\.identity) == [aIdentity, bIdentity])
  }

  @MainActor
  private func seedTwoFocusableSiblings(
    graph: ViewGraph,
    rootIdentity: Identity,
    aIdentity: Identity,
    bIdentity: Identity,
    namespace: MatchedGeometryNamespace
  ) {
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let aNode = graph.beginEvaluation(identity: aIdentity, invalidator: nil)
    recordFocus(on: aNode, identity: aIdentity, namespace: namespace)
    graph.finishEvaluation(
      aNode,
      resolved: ResolvedNode(identity: aIdentity, kind: .view("A")),
      accessedStateSlots: 0
    )
    let bNode = graph.beginEvaluation(identity: bIdentity, invalidator: nil)
    recordFocus(on: bNode, identity: bIdentity, namespace: namespace)
    graph.finishEvaluation(
      bNode,
      resolved: ResolvedNode(identity: bIdentity, kind: .view("B")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: aIdentity, kind: .view("A")),
          ResolvedNode(identity: bIdentity, kind: .view("B")),
        ]
      ),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
  }

  @MainActor
  private func recordFocus(
    on node: ViewNode,
    identity: Identity,
    namespace: MatchedGeometryNamespace
  ) {
    node.recordDefaultFocus(
      DefaultFocusCandidateRegistrationSnapshot(namespace: namespace, identity: identity)
    )
    node.recordFocusBindingRegistration(
      FocusBindingRegistrationSnapshot(
        identity: identity,
        bindingID: "binding-\(identity.path)",
        hasPendingRequest: false,
        isSelected: false,
        applyRuntimeFocus: { _ in false }
      )
    )
  }
}
