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
      node.recordKeyPressHandlerRegistration(identity: identity) { _ in
        marker.hasSuffix("1")
      }
      node.recordPasteHandlerRegistration(identity: identity) { _ in
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
        == [namespace, namespace]
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
    Dictionary(uniqueKeysWithValues: registrations.map { registration in
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
    _ registrations: [Identity: TaskRegistration]
  ) -> [Identity: TaskDescriptor] {
    registrations.mapValues(\.descriptor)
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
