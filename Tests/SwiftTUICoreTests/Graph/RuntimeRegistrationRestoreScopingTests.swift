import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

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
    let aNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[aIdentity]!
    graphDraft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [aNodeID], frontierIdentities: [aIdentity])
    )
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

  @Test(
    "scoped restore reproduces a full rebuild across a custom-ResolvableView identity rewrite (G7)")
  func scopedRestoreMatchesFullRebuildAcrossIdentityRewrite() {
    // Stage 5 deleted the registration-alias layer that bridged an authored
    // identity to the (different) identity its resolved output re-roots to — the
    // custom-`ResolvableView` identity-rewrite case. This is the gate evidence
    // that the structural restore replacing it reproduces the old alias
    // resolution: a node evaluated at `authored` but committing a resolved
    // identity of `rewritten`, with focus registered at the rewritten identity,
    // must scoped-restore to a registration set byte-identical to a full
    // rebuild — including against an unchanged sibling that sorts after it.
    let rootIdentity = testIdentity("Root")
    let authored = testIdentity("Root", "Custom")
    let rewritten = testIdentity("Root", "Custom", "Rewritten")
    let bIdentity = testIdentity("Root", "Z")
    let namespace = MatchedGeometryNamespace(0)

    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let customNode = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: customNode, identity: rewritten, namespace: namespace)
    graph.finishEvaluation(
      customNode,
      resolved: ResolvedNode(identity: rewritten, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    let bNode = graph.beginEvaluation(identity: bIdentity, invalidator: nil)
    recordFocus(on: bNode, identity: bIdentity, namespace: namespace)
    graph.finishEvaluation(
      bNode,
      resolved: ResolvedNode(identity: bIdentity, kind: .view("Z")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: rewritten, kind: .view("Custom")),
          ResolvedNode(identity: bIdentity, kind: .view("Z")),
        ]
      ),
      accessedStateSlots: 0
    )
    let resolved0 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved0, placed: nil)

    // The rewrite is real: the node authored at `Custom` committed the resolved
    // identity `Custom/Rewritten`.
    #expect(graph.nodeForIdentity(authored)?.resolvedIdentity == rewritten)

    // Frame 1: full publish — the canonical order.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)

    // Frame 2: narrowly re-evaluate ONLY the custom subtree (authored identity),
    // re-applying the same rewrite + focus, then commit with a scoped restore.
    graph.beginFrame()
    let custom2 = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: custom2, identity: rewritten, namespace: namespace)
    graph.finishEvaluation(
      custom2,
      resolved: ResolvedNode(identity: rewritten, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    let resolved2 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved2, placed: nil)

    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    let customNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[authored]!
    graphDraft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [customNodeID], frontierIdentities: [authored])
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
    // Focus resolves at the rewritten identity, ahead of the later sibling —
    // the scoped restore reproduced the alias resolution exactly.
    let candidates = liveRegistrations.defaultFocusRegistry?.snapshot().candidates ?? []
    #expect(candidates.map(\.identity) == [rewritten, bIdentity])
  }

  @Test("scoped restore does not stack detached-identity focus registrations (F04)")
  func scopedRestoreDoesNotStackDetachedIdentityFocusRegistrations() {
    // A publisher can register focus entries at an identity DETACHED from the
    // frontier (an exact `.id(_:)` — an absolute identity that is no
    // descendant of any structural root). `removeSubtrees` prunes by
    // identity-prefix against the frontier roots and misses those entries,
    // while the scoped restore's structural view-node walk still reaches the
    // publisher node and re-appends its snapshots — so every scoped frame
    // stacks one more copy (the publication oracle's live=3 vs rebuilt=1
    // finding), and a churned old generation is never removed at all.
    let rootIdentity = testIdentity("Root")
    let authored = testIdentity("Root", "Custom")
    let detached = testIdentity("Detached", "field")
    let namespace = MatchedGeometryNamespace(0)

    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let customNode = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: customNode, identity: detached, namespace: namespace)
    recordFocusedValues(on: customNode, identity: detached)
    graph.finishEvaluation(
      customNode,
      resolved: ResolvedNode(identity: authored, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [ResolvedNode(identity: authored, kind: .view("Custom"))]
      ),
      accessedStateSlots: 0
    )
    let resolved0 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved0, placed: nil)

    // Frame 1: full publish — the canonical state (one entry per registry).
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)

    // Frame 2: narrowly re-evaluate ONLY the publisher (same registrations),
    // then commit with a `.subtrees([authored])` scoped restore.
    graph.beginFrame()
    let custom2 = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: custom2, identity: detached, namespace: namespace)
    recordFocusedValues(on: custom2, identity: detached)
    graph.finishEvaluation(
      custom2,
      resolved: ResolvedNode(identity: authored, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    let resolved2 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved2, placed: nil)

    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    let customNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[authored]!
    graphDraft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [customNodeID], frontierIdentities: [authored])
    )
    graphDraft.commitRuntimeRegistrations(from: graph)

    // Oracle: a full rebuild of the same committed graph holds exactly ONE
    // registration per focus registry.
    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
    #expect(
      liveRegistrations.focusedValuesRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusedValuesRegistry?.snapshot().map(\.identity)
    )
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
  }

  @Test("scoped restore removes a churned detached-identity focus registration (F04)")
  func scopedRestoreRemovesChurnedDetachedIdentityFocusRegistration() {
    // The churn direction of the same hole: the publisher re-registers at a
    // NEW detached identity each generation (`.id(gen)`), so the previous
    // generation's entry — outside every frontier root — must still leave the
    // live registry on the scoped commit or it stacks forever and can win
    // dispatch ahead of the live generation.
    let rootIdentity = testIdentity("Root")
    let authored = testIdentity("Root", "Custom")
    let firstGeneration = testIdentity("Detached", "generation-0")
    let secondGeneration = testIdentity("Detached", "generation-1")
    let namespace = MatchedGeometryNamespace(0)

    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let customNode = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: customNode, identity: firstGeneration, namespace: namespace)
    recordFocusedValues(on: customNode, identity: firstGeneration)
    graph.finishEvaluation(
      customNode,
      resolved: ResolvedNode(identity: authored, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [ResolvedNode(identity: authored, kind: .view("Custom"))]
      ),
      accessedStateSlots: 0
    )
    let resolved0 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved0, placed: nil)

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)

    // Frame 2: the publisher churns its detached registration identity.
    graph.beginFrame()
    let custom2 = graph.beginEvaluation(identity: authored, invalidator: nil)
    recordFocus(on: custom2, identity: secondGeneration, namespace: namespace)
    recordFocusedValues(on: custom2, identity: secondGeneration)
    graph.finishEvaluation(
      custom2,
      resolved: ResolvedNode(identity: authored, kind: .view("Custom")),
      accessedStateSlots: 0
    )
    let resolved2 = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved2, placed: nil)

    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    let customNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[authored]!
    graphDraft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [customNodeID], frontierIdentities: [authored])
    )
    graphDraft.commitRuntimeRegistrations(from: graph)

    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
    #expect(
      liveRegistrations.focusedValuesRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusedValuesRegistry?.snapshot().map(\.identity)
    )
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
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

  @Test(".all publication skips restore when registration fingerprint is unchanged")
  func allPublicationSkipsRestoreWhenRegistrationFingerprintIsUnchanged() {
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

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    let initialDiagnostics = initialDraft.commitRuntimeRegistrations(from: graph)
    #expect(initialDiagnostics.publication.publicationMode == "all")
    #expect(initialDiagnostics.publication.restoredNodeCount == 3)

    let secondDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    secondDraft.recordDirtyEvaluationPlan(nil)
    let secondDiagnostics = secondDraft.commitRuntimeRegistrations(from: graph)

    #expect(secondDiagnostics.publication.publicationMode == "all")
    #expect(secondDiagnostics.publication.restoredNodeCount == 0)

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
  }

  @Test("in-place action refresh escalates a plan-less commit's publication")
  func inPlaceActionRefreshEscalatesPlanlessCommitPublication() {
    let rootIdentity = testIdentity("Root")
    let itemIdentity = testIdentity("Root", "Item")

    // Seed: one node holding an action registration — the toolbar strip item
    // shape (`<strip>/base/content/Layout[i]`).
    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let itemNode = graph.beginEvaluation(identity: itemIdentity, invalidator: nil)
    itemNode.recordActionRegistration(
      identity: itemIdentity,
      handler: { true },
      followUpInvalidationIdentity: nil
    )
    graph.finishEvaluation(
      itemNode,
      resolved: ResolvedNode(identity: itemIdentity, kind: .view("Item")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [ResolvedNode(identity: itemIdentity, kind: .view("Item"))]
      ),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    // Frame 1: full publish; the commit records the registration fingerprint.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    initialDraft.commitRuntimeRegistrations(from: graph)

    // Between commits: the reused toolbar strip re-captures the item's action
    // in place (late-preference reconciliation). The refresh restores only a
    // frame-scoped resolve-context registry, so the refreshed record reaches
    // the persistent live registry solely through the next commit's
    // publication.
    let contextRegistry = LocalActionRegistry()
    var refreshedHandlerRan = false
    graph.refreshActionRegistration(
      identity: itemIdentity,
      handler: {
        refreshedHandlerRan = true
        return true
      },
      followUpInvalidationIdentity: nil,
      in: contextRegistry
    )

    // Frame 2: nothing re-evaluated — no dirty plan is recorded. The queued
    // refresh root must escalate the publication from `.unchanged` to a
    // narrow `.subtrees`, so (a) the refreshed record reaches the live
    // registry, and (b) the `.unchanged` commit's byte-stable-fingerprint
    // premise (the F63 DEBUG oracle at
    // `recordCommittedRuntimeRegistrationFingerprintForUnchangedFrame`)
    // stays true — pre-fix this commit trapped there (the gallery
    // todo-delete crash).
    let planlessDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    let diagnostics = planlessDraft.commitRuntimeRegistrations(from: graph)
    #expect(diagnostics.publication.publicationMode == "subtrees")

    // The refreshed handler reached BOTH registries: the frame-scoped one the
    // refresh restored directly, and the live one via the escalated commit.
    #expect(contextRegistry.dispatch(identity: itemIdentity))
    #expect(refreshedHandlerRan)
    refreshedHandlerRan = false
    #expect(liveRegistrations.actionRegistry?.dispatch(identity: itemIdentity) == true)
    #expect(refreshedHandlerRan)

    // A follow-up plan-less commit with no interleaved refresh stays
    // `.unchanged` — and must not trap the oracle.
    let unchangedDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    let unchangedDiagnostics = unchangedDraft.commitRuntimeRegistrations(from: graph)
    #expect(unchangedDiagnostics.publication.publicationMode == "unchanged")
  }

  @Test("layout-realized re-install escalates a plan-less commit's publication")
  func layoutRealizedReinstallEscalatesPlanlessCommitPublication() {
    let rootIdentity = testIdentity("Root")
    let boundaryIdentity = testIdentity("Root", "Reader")
    let contentIdentity = testIdentity("Root", "Reader", "content")

    // Seed: a layout-realized boundary (the GeometryReader shape) whose
    // realized content holds an action registration.
    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let boundaryNode = graph.beginEvaluation(identity: boundaryIdentity, invalidator: nil)
    let contentNode = graph.beginEvaluation(identity: contentIdentity, invalidator: nil)
    contentNode.recordActionRegistration(
      identity: contentIdentity,
      handler: { true },
      followUpInvalidationIdentity: nil
    )
    let resolvedContent = ResolvedNode(identity: contentIdentity, kind: .view("Content"))
    graph.finishEvaluation(
      contentNode,
      resolved: resolvedContent,
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      boundaryNode,
      resolved: ResolvedNode(
        identity: boundaryIdentity,
        kind: .view("GeometryReader"),
        children: [resolvedContent]
      ),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: boundaryIdentity,
            kind: .view("GeometryReader"),
            children: [resolvedContent]
          )
        ]
      ),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    // Frame 1: full publish; the commit records the registration fingerprint.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    initialDraft.commitRuntimeRegistrations(from: graph)

    // Between commits: layout re-realizes the boundary content (a terminal
    // resize changes the proposal, so the per-pass realization cache misses).
    // The realize re-resolves the content — re-recording its registrations —
    // and installs the realized children on the graph.
    var refreshedHandlerRan = false
    let reRealizedContent = graph.beginEvaluation(
      identity: contentIdentity,
      invalidator: nil
    )
    reRealizedContent.recordActionRegistration(
      identity: contentIdentity,
      handler: {
        refreshedHandlerRan = true
        return true
      },
      followUpInvalidationIdentity: nil
    )
    graph.finishEvaluation(
      reRealizedContent,
      resolved: resolvedContent,
      accessedStateSlots: 0
    )
    graph.installLayoutRealizedChildren(
      for: boundaryIdentity,
      children: [resolvedContent]
    )

    // Frame 2: nothing re-evaluated — no dirty plan is recorded. The queued
    // boundary root must escalate the publication from `.unchanged` to a
    // narrow `.subtrees`, so (a) the re-realized content's registrations
    // reach the live registry, and (b) the `.unchanged` commit's
    // byte-stable-fingerprint premise (the F63 DEBUG oracle at
    // `recordCommittedRuntimeRegistrationFingerprintForUnchangedFrame`)
    // stays true — pre-fix this commit trapped there (the gallery Life-tab
    // resize crash).
    let planlessDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    let diagnostics = planlessDraft.commitRuntimeRegistrations(from: graph)
    #expect(diagnostics.publication.publicationMode == "subtrees")

    // The refreshed handler reached the live registry via the escalated commit.
    #expect(liveRegistrations.actionRegistry?.dispatch(identity: contentIdentity) == true)
    #expect(refreshedHandlerRan)

    // A follow-up plan-less commit with no interleaved re-realization stays
    // `.unchanged` — and must not trap the oracle.
    let unchangedDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    let unchangedDiagnostics = unchangedDraft.commitRuntimeRegistrations(from: graph)
    #expect(unchangedDiagnostics.publication.publicationMode == "unchanged")
  }

  @Test(".all publication scopes restore to changed registration subtrees")
  func allPublicationScopesRestoreToChangedRegistrationSubtrees() {
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

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    _ = initialDraft.commitRuntimeRegistrations(from: graph)

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

    let rootFrameDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    rootFrameDraft.recordDirtyEvaluationPlan(nil)
    let diagnostics = rootFrameDraft.commitRuntimeRegistrations(from: graph)

    #expect(diagnostics.publication.publicationMode == "all")
    #expect(diagnostics.publication.restoredNodeCount == 1)

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
    let candidates = liveRegistrations.defaultFocusRegistry?.snapshot().candidates ?? []
    #expect(candidates.map(\.identity) == [aIdentity, bIdentity])
  }

  @Test(".all diffed publication is full-rebuild equivalent across registry families")
  func allPublicationDiffMatchesFullRebuildAcrossRegistryFamilies() {
    let rootIdentity = testIdentity("Root")
    let aIdentity = testIdentity("Root", "A")
    let bIdentity = testIdentity("Root", "B")
    let namespace = MatchedGeometryNamespace(0)
    let probe = RuntimeRegistrationProbeSink()

    let graph = ViewGraph()
    seedTwoBroadRegistrationSiblings(
      graph: graph,
      rootIdentity: rootIdentity,
      aIdentity: aIdentity,
      aMarker: "a0",
      bIdentity: bIdentity,
      bMarker: "b0",
      namespace: namespace,
      probe: probe
    )

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    _ = initialDraft.commitRuntimeRegistrations(from: graph)

    graph.beginFrame()
    let aNode = graph.beginEvaluation(identity: aIdentity, invalidator: nil)
    recordBroadRegistrations(
      on: aNode,
      identity: aIdentity,
      marker: "a1",
      namespace: namespace,
      probe: probe
    )
    graph.finishEvaluation(
      aNode,
      resolved: ResolvedNode(identity: aIdentity, kind: .view("A")),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let rootFrameDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    rootFrameDraft.recordDirtyEvaluationPlan(nil)
    let diagnostics = rootFrameDraft.commitRuntimeRegistrations(from: graph)

    #expect(diagnostics.publication.publicationMode == "all")
    #expect(diagnostics.publication.restoredNodeCount == 1)

    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    assertBroadRegistriesMatch(
      liveRegistrations,
      fullRebuild,
      identities: [aIdentity, bIdentity],
      changedIdentity: aIdentity,
      namespace: namespace,
      probe: probe
    )
  }

  // MARK: - Generative property: scoped restore == full rebuild over a shape space

  /// Generative reconciliation harness. The hand-written tests above pin one
  /// fixed two-sibling shape with sibling A invalidated; the dropped-handler
  /// "strand" class instead hides at *some* sibling count / *some* invalidated
  /// position, behind *some* framework seam, and on *some* publication path. This
  /// deterministically enumerates a `(kind, siblingCount, changedIndex,
  /// publication)` product and asserts the universal property — a scoped
  /// `.subtrees`, root-rooted `.subtrees` (fingerprint-delta body), or diffed
  /// `.all` restore must equal a full rebuild across all 15
  /// registry families
  /// (``assertBroadRegistriesMatch``) — for every shape. No RNG: the shapes are
  /// enumerated, so a failure is reproducible by its `SeamCase` argument.
  @Test(
    "scoped restore equals full rebuild across all registries for generated seam cases",
    arguments: RuntimeRegistrationRestoreScopingTests.generatedSeamCases
  )
  func scopedRestoreEqualsFullRebuildAcrossGeneratedSeamCases(_ seamCase: SeamCase) {
    let shape = seamCase.shape
    let rootIdentity = testIdentity("Root")
    let namespace = MatchedGeometryNamespace(0)
    let probe = RuntimeRegistrationProbeSink()

    let siblings = shape.siblings(rootIdentity: rootIdentity)

    let graph = ViewGraph()
    seedBroadRegistrationShape(
      graph: graph,
      rootIdentity: rootIdentity,
      shape: shape,
      siblings: siblings,
      namespace: namespace,
      probe: probe
    )

    // Frame 1: full publish into the live registry — the canonical order.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(liveRegistrations: liveRegistrations, checkpoint: nil)
    initialDraft.recordDirtyEvaluationPlan(nil)
    _ = initialDraft.commitRuntimeRegistrations(from: graph)

    // Frame 2: narrowly re-evaluate ONLY the changed sibling -> scoped restore.
    let changed = siblings[shape.changedIndex]
    graph.beginFrame()
    reEvaluateBroadRegistrationSibling(
      changed,
      in: graph,
      shape: shape,
      namespace: namespace,
      probe: probe
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let rootFrameDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    seamCase.publication.record(
      on: rootFrameDraft,
      graph: graph,
      rootIdentity: rootIdentity,
      changedIdentity: changed.identity
    )
    _ = rootFrameDraft.commitRuntimeRegistrations(from: graph)

    // Oracle: a full rebuild of the same committed graph.
    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)

    assertBroadRegistriesMatch(
      liveRegistrations,
      fullRebuild,
      identities: shape.registrationIdentities(for: siblings),
      changedIdentity: changed.identity,
      namespace: namespace,
      probe: probe
    )
  }

  @Test("a graph-root-rooted publication escalates to a full registration rebuild")
  func rootRootedPublicationEscalatesToFullRebuild() {
    // The portal host wraps the authored tree in a DIFFERENT identity space
    // (`__TerminalUIPortalHost/<root>` vs `<root>/...`), so a publication
    // whose frontier collapsed to the graph root cannot be scoped by identity
    // prefix: capture-island registrations that interaction history removed
    // from the live registry are unreachable by both the ViewNode walk (the
    // capture seam) and the identity-prefix island arm (no shared prefix) —
    // dead controls until the next full publication (the gallery's
    // "scroll-control actions after a tab revisit" report). Root-rooted
    // covers route onto the fingerprint-delta body; with NO committed
    // fingerprint to diff against (this graph never committed through a
    // draft), that body must fall back to the full reset-and-rebuild path
    // and heal the divergence.
    let portalIdentity = testIdentity("__TestPortalHost", "Root")
    let rootIdentity = testIdentity("Root")
    let islandIdentity = testIdentity("Root", "Island")

    let graph = ViewGraph()
    graph.beginFrame()
    let portalNode = graph.beginEvaluation(identity: portalIdentity, invalidator: nil)
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    // Capture-hosted island: evaluated during the frame but committed in no
    // children array — anchored through its evaluation host only.
    let islandNode = graph.beginEvaluation(identity: islandIdentity, invalidator: nil)
    ViewNodeContext.withValue(islandNode) {
      islandNode.recordActionRegistration(
        identity: islandIdentity,
        handler: { true },
        followUpInvalidationIdentity: nil
      )
    }
    graph.finishEvaluation(
      islandNode,
      resolved: ResolvedNode(identity: islandIdentity, kind: .view("Island")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .view("Root")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      portalNode,
      resolved: ResolvedNode(
        identity: portalIdentity,
        kind: .root,
        children: [ResolvedNode(identity: rootIdentity, kind: .view("Root"))]
      ),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: portalIdentity)
    _ = graph.finalizeFrame(rootIdentity: portalIdentity, resolved: resolved, placed: nil)

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    #expect(liveRegistrations.actionRegistry?.hasHandler(identity: islandIdentity) == true)

    // Interaction history diverges the live registry: a narrow frame's reset
    // removed the island's action without a matching restore.
    liveRegistrations.actionRegistry?.removeSubtrees(rootedAt: [islandIdentity])
    #expect(liveRegistrations.actionRegistry?.hasHandler(identity: islandIdentity) == false)

    // A publication whose frontier is the GRAPH ROOT must heal the divergence.
    let draft = ViewGraphFrameDraft(liveRegistrations: liveRegistrations, checkpoint: nil)
    let portalNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[portalIdentity]!
    draft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [portalNodeID], frontierIdentities: [portalIdentity])
    )
    _ = draft.commitRuntimeRegistrations(from: graph)

    #expect(
      liveRegistrations.actionRegistry?.hasHandler(identity: islandIdentity) == true,
      "a graph-root-rooted publication left the capture-island action dead"
    )
    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)
    #expect(
      liveRegistrations.publicationOracleFingerprint()
        == fullRebuild.publicationOracleFingerprint()
    )
  }

  @Test("subtree cover threshold probe dedups overlap and stops at the cap")
  func subtreeCoverProbeDedupsOverlapAndStopsAtCap() {
    // Root → A(A1, A2, A3), B(B1) — 7 live nodes.
    let rootIdentity = testIdentity("Root")
    let aIdentity = testIdentity("Root", "A")
    let aChildIdentities = (1...3).map { testIdentity("Root", "A", "A\($0)") }
    let bIdentity = testIdentity("Root", "B")
    let bChildIdentity = testIdentity("Root", "B", "B1")

    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let aNode = graph.beginEvaluation(identity: aIdentity, invalidator: nil)
    for childIdentity in aChildIdentities {
      let child = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
      graph.finishEvaluation(
        child,
        resolved: ResolvedNode(identity: childIdentity, kind: .view("Leaf")),
        accessedStateSlots: 0
      )
    }
    graph.finishEvaluation(
      aNode,
      resolved: ResolvedNode(
        identity: aIdentity,
        kind: .view("A"),
        children: aChildIdentities.map { ResolvedNode(identity: $0, kind: .view("Leaf")) }
      ),
      accessedStateSlots: 0
    )
    let bNode = graph.beginEvaluation(identity: bIdentity, invalidator: nil)
    let bChild = graph.beginEvaluation(identity: bChildIdentity, invalidator: nil)
    graph.finishEvaluation(
      bChild,
      resolved: ResolvedNode(identity: bChildIdentity, kind: .view("Leaf")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      bNode,
      resolved: ResolvedNode(
        identity: bIdentity,
        kind: .view("B"),
        children: [ResolvedNode(identity: bChildIdentity, kind: .view("Leaf"))]
      ),
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

    #expect(graph.runtimeRegistrationSubtreeCoverReaches(4, rootedAt: [aIdentity]))
    #expect(!graph.runtimeRegistrationSubtreeCoverReaches(5, rootedAt: [aIdentity]))
    // Overlapping roots must not double-count: A1 is inside A's cover.
    #expect(
      !graph.runtimeRegistrationSubtreeCoverReaches(
        5,
        rootedAt: [aIdentity, aChildIdentities[0]]
      )
    )
    #expect(graph.runtimeRegistrationSubtreeCoverReaches(6, rootedAt: [aIdentity, bIdentity]))
    #expect(!graph.runtimeRegistrationSubtreeCoverReaches(7, rootedAt: [aIdentity, bIdentity]))
    // A zero threshold is vacuously reached; a positive one needs live roots.
    #expect(graph.runtimeRegistrationSubtreeCoverReaches(0, rootedAt: []))
    #expect(!graph.runtimeRegistrationSubtreeCoverReaches(1, rootedAt: []))
  }

  @Test("a wide-cover subtrees publication stays byte-identical to a full rebuild")
  func wideCoverSubtreesPublicationMatchesFullRebuild() {
    // A frontier covering most of the live tree escalates to the
    // fingerprint-delta publication (the `.all`-frame body) instead of the
    // per-node scoped restore — the wide-cover commit must stay
    // byte-identical to a full rebuild, including focus-list order.
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

    // Frame 1: an `.all` draft commit publishes the live registry AND records
    // the committed fingerprint the delta path diffs against.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let seedDraft = ViewGraphFrameDraft(liveRegistrations: liveRegistrations, checkpoint: nil)
    seedDraft.recordDirtyEvaluationPlan(nil)
    _ = seedDraft.commitRuntimeRegistrations(from: graph)

    // Frame 2: narrowly re-evaluate ONLY subtree A, then publish with a WIDE
    // frontier [A, B] — 2 of 3 live nodes, past the half-tree threshold.
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
    let nodeIDByIdentity = graph.debugTotalStateSnapshot().nodeIDByIdentity
    graphDraft.recordDirtyEvaluationPlan(
      .init(
        frontierNodeIDs: [nodeIDByIdentity[aIdentity]!, nodeIDByIdentity[bIdentity]!],
        frontierIdentities: [aIdentity, bIdentity]
      )
    )
    _ = graphDraft.commitRuntimeRegistrations(from: graph)

    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)
    #expect(
      liveRegistrations.publicationOracleFingerprint()
        == fullRebuild.publicationOracleFingerprint()
    )
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
  }

  @Test("a root-rooted subtrees publication takes the fingerprint-delta body")
  func rootRootedSubtreesPublicationTakesFingerprintDeltaBody() {
    // With a committed fingerprint to diff against, a frontier that covers
    // the graph root routes onto the fingerprint-delta body instead of the
    // full reset-and-rebuild: F08's focus/press dirty frontier includes the
    // graph root on every interaction frame (the root node is a dirty focus
    // reader's nearest evaluator ancestor), so an unconditional full rebuild
    // is O(live) commit per interaction frame — the sheet-scenario
    // regression that held the 2026-07-03 reland. The commit must restore
    // only the changed entries and stay byte-identical to a full rebuild.
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

    // Frame 1: an `.all` draft commit publishes the live registry AND records
    // the committed fingerprint the delta path diffs against.
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let seedDraft = ViewGraphFrameDraft(liveRegistrations: liveRegistrations, checkpoint: nil)
    seedDraft.recordDirtyEvaluationPlan(nil)
    _ = seedDraft.commitRuntimeRegistrations(from: graph)

    // Frame 2: narrowly re-evaluate ONLY subtree A, then publish with the
    // frontier collapsed to the GRAPH ROOT.
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
      checkpoint: nil,
      publicationDiagnosticsEnabled: true
    )
    let nodeIDByIdentity = graph.debugTotalStateSnapshot().nodeIDByIdentity
    graphDraft.recordDirtyEvaluationPlan(
      .init(
        frontierNodeIDs: [nodeIDByIdentity[rootIdentity]!],
        frontierIdentities: [rootIdentity]
      )
    )
    let diagnostics = graphDraft.commitRuntimeRegistrations(from: graph)

    // The delta body restored only A's changed entry — not the live tree the
    // frontier covers structurally (the pre-fix full rebuild reported the
    // whole live node count here).
    #expect(diagnostics.publication.publicationMode == "subtrees")
    #expect(diagnostics.publication.restoredNodeCount == 1)

    let fullRebuild = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: fullRebuild)
    #expect(
      liveRegistrations.publicationOracleFingerprint()
        == fullRebuild.publicationOracleFingerprint()
    )
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
  }

  @Test("structured lifecycle teardown preserves path-colliding sibling component")
  func structuredLifecycleTeardownPreservesPathCollidingSiblingComponent() {
    let preservedIdentity = Identity(components: ["Root", "A/B"])
    let removedRoot = Identity(components: ["Root", "A"])
    let removedIdentity = Identity(components: ["Root", "A", "B"])
    let registry = LocalLifecycleRegistry()

    _ = ViewNodeContext.withCurrentValue(
      ViewNode(viewNodeID: ViewNodeID(rawValue: 1), identity: preservedIdentity)
    ) {
      registry.registerAppear(identity: preservedIdentity, ordinal: 0) {}
    }
    _ = ViewNodeContext.withCurrentValue(
      ViewNode(viewNodeID: ViewNodeID(rawValue: 2), identity: removedIdentity)
    ) {
      registry.registerAppear(identity: removedIdentity, ordinal: 0) {}
    }

    #expect(Set(registry.snapshot().appearHandlers.keys).count == 1)
    #expect(registry.snapshot().appearRegistrations.count == 2)

    registry.removeSubtrees(rootedAt: [removedRoot])

    let identities = Set(registry.snapshot().appearRegistrations.values.map(\.identity))
    #expect(identities == [preservedIdentity])
  }

  @Test("structured preference teardown preserves path-colliding sibling component")
  func structuredPreferenceTeardownPreservesPathCollidingSiblingComponent() {
    let preservedIdentity = Identity(components: ["Root", "A/B"])
    let removedRoot = Identity(components: ["Root", "A"])
    let removedIdentity = Identity(components: ["Root", "A", "B"])
    let registry = LocalPreferenceObservationRegistry()

    ViewNodeContext.withCurrentValue(
      ViewNode(viewNodeID: ViewNodeID(rawValue: 1), identity: preservedIdentity)
    ) {
      registry.register(
        identity: preservedIdentity,
        key: RuntimeRegistrationPathCollisionPreferenceKey.self,
        value: 1
      ) { _ in }
    }
    ViewNodeContext.withCurrentValue(
      ViewNode(viewNodeID: ViewNodeID(rawValue: 2), identity: removedIdentity)
    ) {
      registry.register(
        identity: removedIdentity,
        key: RuntimeRegistrationPathCollisionPreferenceKey.self,
        value: 2
      ) { _ in }
    }

    #expect(Set(registry.snapshot().map(\.handlerID)).count == 1)
    #expect(registry.snapshot().count == 2)

    registry.removeSubtrees(rootedAt: [removedRoot])

    let identities = Set(registry.snapshot().map(\.identity))
    #expect(identities == [preservedIdentity])
  }

  @Test("structured focus binding keys isolate path-colliding binding IDs")
  func structuredFocusBindingKeysIsolatePathCollidingBindingIDs() {
    let preservedIdentity = Identity(components: ["Root", "A/B"])
    let removedRoot = Identity(components: ["Root", "A"])
    let removedIdentity = Identity(components: ["Root", "A", "B"])
    let bindingID = "\(preservedIdentity)#FocusState[0]"
    let registry = LocalFocusBindingRegistry()

    registry.register(
      identity: preservedIdentity,
      bindingKey: FocusBindingKey(
        ownerNodeID: ViewNodeID(rawValue: 1),
        suffix: .stateSlot(ordinal: 0)
      ),
      bindingID: bindingID,
      hasPendingRequest: false,
      isSelected: true,
      applyRuntimeFocus: { _ in false }
    )
    registry.register(
      identity: removedIdentity,
      bindingKey: FocusBindingKey(
        ownerNodeID: ViewNodeID(rawValue: 2),
        suffix: .stateSlot(ordinal: 0)
      ),
      bindingID: bindingID,
      hasPendingRequest: true,
      isSelected: false,
      applyRuntimeFocus: { _ in false }
    )

    #expect(Set(registry.snapshot().map(\.bindingID)).count == 1)
    #expect(Set(registry.snapshot().map(\.bindingKey)).count == 2)
    #expect(
      registry.desiredFocusRequest(allowedIdentities: [preservedIdentity]) == .clear
    )

    registry.removeSubtrees(rootedAt: [removedRoot])

    #expect(registry.snapshot().map(\.identity) == [preservedIdentity])
    #expect(
      registry.desiredFocusRequest(allowedIdentities: [preservedIdentity]) == .none
    )
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

  @MainActor
  private func recordFocusedValues(
    on node: ViewNode,
    identity: Identity
  ) {
    node.recordFocusedValuesRegistration(
      FocusedValuesRegistrationSnapshot(
        identity: identity,
        descendantIdentities: [identity],
        values: FocusedValues()
      )
    )
  }

  @MainActor
  private func seedTwoBroadRegistrationSiblings(
    graph: ViewGraph,
    rootIdentity: Identity,
    aIdentity: Identity,
    aMarker: String,
    bIdentity: Identity,
    bMarker: String,
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let aNode = graph.beginEvaluation(identity: aIdentity, invalidator: nil)
    recordBroadRegistrations(
      on: aNode,
      identity: aIdentity,
      marker: aMarker,
      namespace: namespace,
      probe: probe
    )
    graph.finishEvaluation(
      aNode,
      resolved: ResolvedNode(identity: aIdentity, kind: .view("A")),
      accessedStateSlots: 0
    )
    let bNode = graph.beginEvaluation(identity: bIdentity, invalidator: nil)
    recordBroadRegistrations(
      on: bNode,
      identity: bIdentity,
      marker: bMarker,
      namespace: namespace,
      probe: probe
    )
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

  /// A generated tree shape: `siblingCount` broadly-registered siblings, an
  /// optional framework seam around/under them, and the sibling at
  /// `changedIndex` invalidated on frame 2.
  struct SeamShape: CustomStringConvertible, Sendable {
    let kind: SeamKind
    let siblingCount: Int
    let changedIndex: Int

    var description: String {
      "\(kind),siblings=\(siblingCount),changed=\(changedIndex)"
    }

    func siblings(rootIdentity: Identity) -> [SeamSibling] {
      (0..<siblingCount).map { index in
        SeamSibling(
          identity: rootIdentity.child("S\(index)"),
          label: "S\(index)",
          marker: "s\(index)-0"
        )
      }
    }

    func registrationIdentities(for siblings: [SeamSibling]) -> [Identity] {
      siblings.flatMap { sibling in
        var identities = [sibling.identity]
        if let islandIdentity = kind.islandIdentity(for: sibling) {
          identities.append(islandIdentity)
        }
        return identities
      }
    }
  }

  struct SeamCase: CustomStringConvertible, Sendable {
    let shape: SeamShape
    let publication: SeamPublication

    var description: String {
      "\(shape),publication=\(publication)"
    }
  }

  enum SeamPublication: String, CaseIterable, CustomStringConvertible, Sendable {
    case diffedAll
    case subtreeFrontier
    // A `.subtrees` frontier collapsed to the graph root — routed onto the
    // fingerprint-delta body (the identity-prefix scoped restore diverges at
    // the portal-host seam for such covers; see
    // `runtimeRegistrationRootsRequireFullPublication`).
    case rootRootedFrontier

    var description: String { rawValue }

    @MainActor
    func record(
      on draft: ViewGraphFrameDraft,
      graph: ViewGraph,
      rootIdentity: Identity,
      changedIdentity: Identity
    ) {
      switch self {
      case .diffedAll:
        draft.recordDirtyEvaluationPlan(nil)
      case .subtreeFrontier:
        let changedNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[changedIdentity]!
        draft.recordDirtyEvaluationPlan(
          .init(
            frontierNodeIDs: [changedNodeID],
            frontierIdentities: [changedIdentity]
          )
        )
      case .rootRootedFrontier:
        let rootNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[rootIdentity]!
        draft.recordDirtyEvaluationPlan(
          .init(
            frontierNodeIDs: [rootNodeID],
            frontierIdentities: [rootIdentity]
          )
        )
      }
    }
  }

  enum SeamKind: String, CaseIterable, CustomStringConvertible, Sendable {
    case flat
    case groupSplice
    case forEachSplice
    case portalIsland
    case overlayIsland
    case lazyTabIsland
    case sheetCapturedIsland
    case lazyViewportIsland
    case identityRerootIsland

    var description: String { rawValue }

    var wrapperLabel: String? {
      switch self {
      case .groupSplice:
        "GroupSplice"
      case .forEachSplice:
        "ForEachSplice"
      case .flat, .portalIsland, .overlayIsland, .lazyTabIsland, .sheetCapturedIsland,
        .lazyViewportIsland, .identityRerootIsland:
        nil
      }
    }

    var islandLabel: String? {
      switch self {
      case .portalIsland:
        "PortalIsland"
      case .overlayIsland:
        "OverlayIsland"
      case .lazyTabIsland:
        "LazyTabIsland"
      case .sheetCapturedIsland:
        "SheetCapturedIsland"
      case .lazyViewportIsland:
        "LazyViewportIsland"
      case .identityRerootIsland:
        "IdentityRerootIsland"
      case .flat, .groupSplice, .forEachSplice:
        nil
      }
    }

    func islandIdentity(for sibling: SeamSibling) -> Identity? {
      islandLabel.map { sibling.identity.child($0) }
    }
  }

  struct SeamSibling {
    let identity: Identity
    let label: String
    let marker: String
  }

  /// Deterministic enumeration of the shape space: every
  /// `(kind, count, changedIndex, publication)` tuple for 2...4 siblings.
  /// Enumerated, not random, so a failure is reproducible by its argument.
  nonisolated static let generatedSeamCases: [SeamCase] = {
    var cases: [SeamCase] = []
    for kind in SeamKind.allCases {
      for siblingCount in 2...4 {
        for changedIndex in 0..<siblingCount {
          let shape = SeamShape(
            kind: kind,
            siblingCount: siblingCount,
            changedIndex: changedIndex
          )
          for publication in SeamPublication.allCases {
            cases.append(
              SeamCase(
                shape: shape,
                publication: publication
              )
            )
          }
        }
      }
    }
    return cases
  }()

  /// N-sibling generalization of ``seedTwoBroadRegistrationSiblings``: seeds
  /// each sibling with the full broad registration set under the root, optionally
  /// wraps it in structural splices or emits live capture-island descendants,
  /// then commits frame 1.
  private func seedBroadRegistrationShape(
    graph: ViewGraph,
    rootIdentity: Identity,
    shape: SeamShape,
    siblings: [SeamSibling],
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)

    for sibling in siblings {
      seedBroadRegistrationNode(
        identity: sibling.identity,
        label: sibling.label,
        marker: sibling.marker,
        in: graph,
        namespace: namespace,
        probe: probe
      )
    }

    for sibling in siblings {
      guard let islandIdentity = shape.kind.islandIdentity(for: sibling),
        let islandLabel = shape.kind.islandLabel
      else {
        continue
      }
      seedBroadRegistrationNode(
        identity: islandIdentity,
        label: islandLabel,
        marker: "\(sibling.marker)-\(islandLabel)-0",
        in: graph,
        namespace: namespace,
        probe: probe
      )
    }

    let siblingResolvedNodes = siblings.map {
      ResolvedNode(identity: $0.identity, kind: .view($0.label))
    }
    let rootChildren: [ResolvedNode]
    if let wrapperLabel = shape.kind.wrapperLabel {
      let wrapperIdentity = rootIdentity.child(wrapperLabel)
      let wrapperNode = graph.beginEvaluation(identity: wrapperIdentity, invalidator: nil)
      graph.finishEvaluation(
        wrapperNode,
        resolved: ResolvedNode(
          identity: wrapperIdentity,
          kind: .view(wrapperLabel),
          children: siblingResolvedNodes
        ),
        accessedStateSlots: 0
      )
      rootChildren = [
        ResolvedNode(
          identity: wrapperIdentity,
          kind: .view(wrapperLabel),
          children: siblingResolvedNodes
        )
      ]
    } else {
      rootChildren = siblingResolvedNodes
    }

    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: rootChildren),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
  }

  private func seedBroadRegistrationNode(
    identity: Identity,
    label: String,
    marker: String,
    in graph: ViewGraph,
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    recordBroadRegistrations(
      on: node,
      identity: identity,
      marker: marker,
      namespace: namespace,
      probe: probe
    )
    graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: identity, kind: .view(label)),
      accessedStateSlots: 0
    )
  }

  private func reEvaluateBroadRegistrationSibling(
    _ sibling: SeamSibling,
    in graph: ViewGraph,
    shape: SeamShape,
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    seedBroadRegistrationNode(
      identity: sibling.identity,
      label: sibling.label,
      marker: "\(sibling.marker)-1",
      in: graph,
      namespace: namespace,
      probe: probe
    )
    guard let islandIdentity = shape.kind.islandIdentity(for: sibling),
      let islandLabel = shape.kind.islandLabel
    else {
      return
    }
    seedBroadRegistrationNode(
      identity: islandIdentity,
      label: islandLabel,
      marker: "\(sibling.marker)-\(islandLabel)-1",
      in: graph,
      namespace: namespace,
      probe: probe
    )
  }

  @MainActor
  private func recordBroadRegistrations(
    on node: ViewNode,
    identity: Identity,
    marker: String,
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    ViewNodeContext.withValue(node) {
      let routeID = RouteID(identity: identity)
      node.recordActionRegistration(
        identity: identity,
        handler: { marker.hasSuffix("1") },
        followUpInvalidationIdentity: identity.child("follow-up-\(marker)")
      )
      node.recordKeyHandlerRegistration(identity: identity) { _ in
        marker.hasSuffix("1")
      }
      node.recordKeyPressHandlerRegistration(identity: identity, ordinal: 0) { _ in
        marker.hasSuffix("1")
      }
      node.recordPasteHandlerRegistration(identity: identity, ordinal: 0) { _ in
        marker.hasSuffix("1")
      }
      node.recordTerminationHandlerRegistration(identity: identity) { _ in
        marker.hasSuffix("1") ? .cancel : .allow
      }
      node.recordPointerHandlerRegistration(routeID: routeID) { _ in
        marker.hasSuffix("1")
      }
      node.recordPointerHoverHandlerRegistration(routeID: routeID) { phase in
        probe.record("hover:\(marker):\(phase)")
      }
      node.recordGestureRegistration(
        identity: identity,
        recognizer: AnyGestureRecognizer(RuntimeRegistrationProbeGesture(marker: marker))
      )
      node.recordGestureStateBinding(
        identity: identity,
        binding: RuntimeRegistrationProbeGestureBinding.binding(marker: marker)
      )
      recordFocus(on: node, identity: identity, namespace: namespace)
      var focusedValues = FocusedValues()
      focusedValues[RuntimeRegistrationFocusedValueKey.self] = marker
      node.recordFocusedValuesRegistration(
        FocusedValuesRegistrationSnapshot(
          identity: identity,
          descendantIdentities: [identity],
          values: focusedValues
        )
      )
      node.recordScrollPositionRegistration(
        ScrollPositionRegistrationSnapshot(
          identity: identity,
          currentOffset: { RuntimeRegistrationProbeValues.scrollOffset(for: marker) },
          applyOffset: { offset in
            probe.record("scroll:\(marker):\(offset.x),\(offset.y)")
          }
        )
      )
      node.recordLifecycleAppearRegistration(
        RuntimeRegistrationProbeValues.lifecycleRegistration(
          identity: identity,
          nodeID: node.viewNodeID,
          suffix: .appear(ordinal: 0),
          marker: marker,
          probe: probe
        )
      )
      node.recordLifecycleDisappearRegistration(
        RuntimeRegistrationProbeValues.lifecycleRegistration(
          identity: identity,
          nodeID: node.viewNodeID,
          suffix: .disappear(ordinal: 0),
          marker: marker,
          probe: probe
        )
      )
      node.recordLifecycleChangeRegistration(
        RuntimeRegistrationProbeValues.lifecycleRegistration(
          identity: identity,
          nodeID: node.viewNodeID,
          suffix: .change(ordinal: 0),
          marker: marker,
          probe: probe
        )
      )
      node.recordTaskRegistration(
        identity: identity,
        registration: TaskRegistration(
          descriptor: TaskDescriptor(id: "task-\(marker)", priority: .medium),
          operation: { probe.record("task:\(marker)") }
        )
      )

      let preferenceRegistry = LocalPreferenceObservationRegistry()
      preferenceRegistry.register(
        identity: identity,
        key: RuntimeRegistrationPathCollisionPreferenceKey.self,
        value: RuntimeRegistrationProbeValues.preferenceValue(for: marker),
        action: { value in probe.record("preference:\(marker):\(value)") }
      )

      let keyBinding = RuntimeRegistrationProbeValues.keyBinding
      node.recordCommandRegistration(
        CommandRegistrySnapshot(
          keyCommandsByScope: [
            identity: [
              keyBinding: RegisteredKeyCommand(
                binding: keyBinding,
                description: "command-\(marker)",
                isEnabled: marker.hasSuffix("1"),
                action: { probe.record("command:\(marker)") }
              )
            ]
          ],
          ownersByScope: [identity: .current(identity: identity)]
        )
      )
      node.recordDropDestinationRegistration(
        DropDestinationRegistrySnapshot(
          handlersByScope: [
            identity: { paths, _ in
              probe.record("drop:\(marker):\(paths.map(\.rawValue).joined(separator: ","))")
              return marker.hasSuffix("1")
            }
          ],
          ownersByScope: [identity: .current(identity: identity)]
        )
      )
    }
  }

  @MainActor
  private func assertBroadRegistriesMatch(
    _ live: RuntimeRegistrationSet,
    _ fullRebuild: RuntimeRegistrationSet,
    identities: [Identity],
    changedIdentity: Identity,
    namespace: MatchedGeometryNamespace,
    probe: RuntimeRegistrationProbeSink
  ) {
    let liveActionSnapshot = live.actionRegistry?.snapshot() ?? [:]
    let fullActionSnapshot = fullRebuild.actionRegistry?.snapshot() ?? [:]
    #expect(Set(liveActionSnapshot.keys) == Set(fullActionSnapshot.keys))
    for identity in identities {
      #expect(live.actionRegistry?.hasHandler(identity: identity) == true)
      #expect(
        live.actionRegistry?.followUpInvalidationIdentity(for: identity)
          == fullRebuild.actionRegistry?.followUpInvalidationIdentity(for: identity)
      )
      #expect(
        live.actionRegistry?.dispatch(identity: identity)
          == fullRebuild.actionRegistry?.dispatch(identity: identity)
      )
    }

    let liveKeyRegistry = live.keyHandlerRegistry
    let fullKeyRegistry = fullRebuild.keyHandlerRegistry
    let liveKeyHandlerKeys = Set((liveKeyRegistry?.snapshot() ?? [:]).keys)
    let fullKeyHandlerKeys = Set((fullKeyRegistry?.snapshot() ?? [:]).keys)
    #expect(liveKeyHandlerKeys == fullKeyHandlerKeys)
    #expect(
      handlerCounts(liveKeyRegistry?.snapshotKeyPressHandlers() ?? [:])
        == handlerCounts(fullKeyRegistry?.snapshotKeyPressHandlers() ?? [:])
    )
    #expect(
      handlerCounts(liveKeyRegistry?.snapshotPasteHandlers() ?? [:])
        == handlerCounts(fullKeyRegistry?.snapshotPasteHandlers() ?? [:])
    )
    for identity in identities {
      #expect(liveKeyRegistry?.hasHandler(identity: identity) == true)
      #expect(liveKeyRegistry?.hasPasteHandler(identity: identity) == true)
      #expect(
        liveKeyRegistry?.dispatch(identity: identity, event: .return)
          == fullKeyRegistry?.dispatch(identity: identity, event: .return)
      )
      #expect(
        liveKeyRegistry?.dispatch(identity: identity, keyPress: KeyPress(.space))
          == fullKeyRegistry?.dispatch(identity: identity, keyPress: KeyPress(.space))
      )
      #expect(
        liveKeyRegistry?.dispatchPaste(identity: identity, content: "payload")
          == fullKeyRegistry?.dispatchPaste(identity: identity, content: "payload")
      )
    }

    #expect(
      handlerCounts(live.terminationRegistry?.snapshot() ?? [:])
        == handlerCounts(fullRebuild.terminationRegistry?.snapshot() ?? [:])
    )
    for identity in identities {
      #expect(
        live.terminationRegistry?.dispatch(.inputEnded, preferredPath: [identity])
          == fullRebuild.terminationRegistry?.dispatch(.inputEnded, preferredPath: [identity])
      )
    }

    let livePointerRegistry = live.pointerHandlerRegistry
    let fullPointerRegistry = fullRebuild.pointerHandlerRegistry
    let livePointerHandlerKeys = Set((livePointerRegistry?.snapshot() ?? [:]).keys)
    let fullPointerHandlerKeys = Set((fullPointerRegistry?.snapshot() ?? [:]).keys)
    #expect(livePointerHandlerKeys == fullPointerHandlerKeys)
    let livePointerHoverKeys = Set((livePointerRegistry?.snapshotHover() ?? [:]).keys)
    let fullPointerHoverKeys = Set((fullPointerRegistry?.snapshotHover() ?? [:]).keys)
    #expect(livePointerHoverKeys == fullPointerHoverKeys)
    for identity in identities {
      let routeID = RouteID(identity: identity)
      let event = LocalPointerEvent(
        kind: .moved,
        location: .cellFallback(CellPoint(x: 0, y: 0)),
        targetRect: CellRect(origin: .zero, size: .init(width: 1, height: 1))
      )
      #expect(
        livePointerRegistry?.dispatch(routeID: routeID, event: event)
          == fullPointerRegistry?.dispatch(routeID: routeID, event: event)
      )
    }
    probe.reset()
    livePointerRegistry?.dispatchHover(
      routeID: RouteID(identity: changedIdentity),
      phase: .moved(Point(x: 0, y: 0))
    )
    let liveHoverEvents = probe.events
    probe.reset()
    fullPointerRegistry?.dispatchHover(
      routeID: RouteID(identity: changedIdentity),
      phase: .moved(Point(x: 0, y: 0))
    )
    #expect(liveHoverEvents == probe.events)

    #expect(
      gestureValues(live.gestureRegistry?.snapshot() ?? [:])
        == gestureValues(fullRebuild.gestureRegistry?.snapshot() ?? [:])
    )
    #expect(
      gestureStateValueTypes(live.gestureStateRegistry?.snapshot() ?? [:])
        == gestureStateValueTypes(fullRebuild.gestureStateRegistry?.snapshot() ?? [:])
    )

    #expect(
      live.defaultFocusRegistry?.snapshot()
        == fullRebuild.defaultFocusRegistry?.snapshot()
    )
    #expect(
      live.focusBindingRegistry?.snapshot().map(\.identity)
        == fullRebuild.focusBindingRegistry?.snapshot().map(\.identity)
    )
    #expect(
      live.defaultFocusRegistry?.snapshot().candidates.map(\.identity)
        == identities
    )
    #expect(
      live.defaultFocusRegistry?.snapshot().candidates.map(\.namespace)
        == Array(repeating: namespace, count: identities.count)
    )

    for identity in identities {
      #expect(
        live.focusedValuesRegistry?
          .focusedValues(for: identity)[RuntimeRegistrationFocusedValueKey.self]
          == fullRebuild.focusedValuesRegistry?
          .focusedValues(for: identity)[RuntimeRegistrationFocusedValueKey.self]
      )
    }
    #expect(
      scrollOffsets(live.scrollPositionRegistry?.snapshot() ?? [])
        == scrollOffsets(fullRebuild.scrollPositionRegistry?.snapshot() ?? [])
    )
    #expect(
      lifecycleHandlerIDs(live.lifecycleRegistry?.snapshot() ?? .init())
        == lifecycleHandlerIDs(fullRebuild.lifecycleRegistry?.snapshot() ?? .init())
    )
    #expect(
      taskDescriptors(live.taskRegistry?.snapshot() ?? [:])
        == taskDescriptors(fullRebuild.taskRegistry?.snapshot() ?? [:])
    )

    let fullPreferenceSnapshot = fullRebuild.preferenceObservationRegistry?.snapshot() ?? []
    #expect(
      preferenceHandlerIDs(live.preferenceObservationRegistry?.snapshot() ?? [])
        == preferenceHandlerIDs(fullPreferenceSnapshot)
    )
    #expect(
      live.preferenceObservationRegistry?.applyChanges(since: fullPreferenceSnapshot)
        == false
    )

    #expect(
      commandSummaries(live.commandRegistry?.snapshot() ?? .init())
        == commandSummaries(fullRebuild.commandRegistry?.snapshot() ?? .init())
    )
    let keyBinding = RuntimeRegistrationProbeValues.keyBinding
    #expect(
      live.commandRegistry?.dispatch(key: keyBinding, along: [changedIdentity])
        == fullRebuild.commandRegistry?.dispatch(key: keyBinding, along: [changedIdentity])
    )

    let liveDropScopes = Set(
      (live.dropDestinationRegistry?.snapshot().handlersByScope ?? [:]).keys
    )
    let fullDropScopes = Set(
      (fullRebuild.dropDestinationRegistry?.snapshot().handlersByScope ?? [:]).keys
    )
    #expect(liveDropScopes == fullDropScopes)
    let droppedPaths = [DroppedPath("/tmp/registration-fixture")]
    #expect(
      live.dropDestinationRegistry?.dispatch(paths: droppedPaths, along: [changedIdentity])
        == fullRebuild.dropDestinationRegistry?.dispatch(
          paths: droppedPaths,
          along: [changedIdentity]
        )
    )
  }

  private func handlerCounts<Value>(
    _ handlers: [Identity: [Value]]
  ) -> [Identity: Int] {
    handlers.mapValues(\.count)
  }

  private func handlerCounts<Value>(
    _ handlers: [Identity: Value]
  ) -> Set<Identity> {
    Set(handlers.keys)
  }

  @MainActor
  private func gestureValues(
    _ recognizers: [Identity: AnyGestureRecognizer]
  ) -> [Identity: String] {
    recognizers.mapValues { recognizer in
      recognizer.currentValue(as: String.self) ?? ""
    }
  }

  private func gestureStateValueTypes(
    _ bindingsByIdentity: [Identity: [AnyGestureStateBinding]]
  ) -> [Identity: [String]] {
    bindingsByIdentity.mapValues { bindings in
      bindings.map { String(reflecting: $0.valueType) }
    }
  }

  @MainActor
  private func scrollOffsets(
    _ registrations: [ScrollPositionRegistrationSnapshot]
  ) -> [Identity: ScrollOffset] {
    Dictionary(
      uniqueKeysWithValues: registrations.map { registration in
        (registration.identity, registration.currentOffset())
      })
  }

  private func lifecycleHandlerIDs(
    _ snapshot: LifecycleHandlerSnapshot
  ) -> [String: Set<String>] {
    [
      "appear": Set(snapshot.appearRegistrations.values.map(\.handlerID)),
      "disappear": Set(snapshot.disappearRegistrations.values.map(\.handlerID)),
      "change": Set(snapshot.changeRegistrations.values.map(\.handlerID)),
    ]
  }

  private func taskDescriptors(
    _ registrations: [Identity: [TaskRegistration]]
  ) -> [Identity: [TaskDescriptor]] {
    registrations.mapValues { $0.map(\.descriptor) }
  }

  private func preferenceHandlerIDs(
    _ registrations: [PreferenceObservationRegistrationSnapshot]
  ) -> [String] {
    registrations.map(\.handlerID)
  }

  private func commandSummaries(
    _ snapshot: CommandRegistrySnapshot
  ) -> [Identity: [KeyBinding: RuntimeRegistrationCommandSummary]] {
    snapshot.keyCommandsByScope.mapValues { commands in
      commands.mapValues { command in
        RuntimeRegistrationCommandSummary(
          description: command.description,
          isEnabled: command.isEnabled
        )
      }
    }
  }
}

private enum RuntimeRegistrationPathCollisionPreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(
    value: inout Int,
    nextValue: () -> Int
  ) {
    value = nextValue()
  }
}

private enum RuntimeRegistrationFocusedValueKey: FocusedValueKey {
  typealias Value = String
}

private struct RuntimeRegistrationCommandSummary: Equatable {
  var description: String
  var isEnabled: Bool
}

@MainActor
private enum RuntimeRegistrationProbeValues {
  static let keyBinding = KeyBinding(
    key: .character("r"),
    modifiers: [.ctrl]
  )

  static func scrollOffset(for marker: String) -> ScrollOffset {
    if marker.hasSuffix("1") {
      return ScrollOffset(x: 11, y: 101)
    }
    if marker.hasPrefix("b") {
      return ScrollOffset(x: 2, y: 20)
    }
    return ScrollOffset(x: 1, y: 10)
  }

  static func preferenceValue(for marker: String) -> Int {
    if marker.hasSuffix("1") {
      return 101
    }
    if marker.hasPrefix("b") {
      return 20
    }
    return 10
  }

  static func lifecycleRegistration(
    identity: Identity,
    nodeID: ViewNodeID,
    suffix: LifecycleHandlerKeySuffix,
    marker: String,
    probe: RuntimeRegistrationProbeSink
  ) -> LifecycleHandlerRegistration {
    LifecycleHandlerRegistration(
      identity: identity,
      key: LifecycleHandlerKey(ownerNodeID: nodeID, suffix: suffix),
      handlerID: "\(identity.path)#\(suffix)-\(marker)",
      handler: { probe.record("lifecycle:\(marker):\(suffix)") }
    )
  }
}

@MainActor
private enum RuntimeRegistrationProbeGestureBinding {
  static func binding(marker: String) -> AnyGestureStateBinding {
    if marker.hasSuffix("1") {
      return AnyGestureStateBinding(
        valueType: String.self,
        setValue: { _ in },
        reset: {}
      )
    }
    return AnyGestureStateBinding(
      valueType: Int.self,
      setValue: { _ in },
      reset: {}
    )
  }
}

@MainActor
private final class RuntimeRegistrationProbeGesture: GestureRecognizer {
  typealias Value = String

  private let marker: String

  init(marker: String) {
    self.marker = marker
  }

  var phase: GestureRecognizerPhase { .possible }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    false
  }

  func currentValue() -> String? {
    marker
  }

  func tearDown() {}
}

@MainActor
private final class RuntimeRegistrationProbeSink {
  private(set) var events: [String] = []

  func record(_ event: String) {
    events.append(event)
  }

  func reset() {
    events.removeAll(keepingCapacity: true)
  }
}
