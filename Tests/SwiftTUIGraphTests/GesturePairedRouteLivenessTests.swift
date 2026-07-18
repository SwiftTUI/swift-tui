import Testing

@testable import SwiftTUIGraph

/// The F04 retention leg (gallery fuzzer case-510, palette rows): a
/// mid-interaction teardown spares an ACTIVE recognizer and its paired
/// pointer route (`preservedGestureIdentities`, F101), and when the
/// interaction site genuinely departs, the gesture registry's prune releases
/// the recognizer — but nothing released the spared paired route, so its
/// stale handler survived every scoped publication until the next full
/// reset (`pointer|…#primary live=1 rebuilt=0` on every sampled frame).
/// Pins both halves of the fix: the paired-route sweep in
/// `pruneOrphanedGestures`, and the publication oracle's awareness that the
/// one-interaction preservation window is full-rebuild-contract behavior,
/// not a divergence — an awareness that must die with the interaction.
@MainActor
@Suite("Gesture-paired pointer route liveness")
struct GesturePairedRouteLivenessTests {
  @Test("prune releases the paired route of a departed preserved recognizer")
  func pruneReleasesPairedRouteOfDepartedRecognizer() {
    let root = testIdentity("Root")
    let row = testIdentity("Root", "Row")
    let node = RegistrationKindDriver.makeRecordingNode(identity: row)
    let recognizer = ActivatableProbeGesture()
    recognizer.phase = .began
    ViewNodeContext.withValue(node) {
      node.recordGestureRegistration(
        identity: row,
        recognizer: AnyGestureRecognizer(recognizer)
      )
      node.recordPointerHandlerRegistration(
        routeID: RouteID(identity: row),
        structuralKey: row
      ) { _ in false }
    }

    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: node.registeredHandlers)
    #expect(set.gestureRegistry?.snapshot().count == 1)
    #expect(set.pointerHandlerRegistry?.snapshot().count == 1)

    // Mid-interaction teardown spares the active recognizer AND its paired
    // route — the designed F101 preservation.
    set.removeSubtrees(rootedAt: [root])
    #expect(
      set.gestureRegistry?.snapshot().count == 1,
      "an ACTIVE recognizer must survive its subtree's removal"
    )
    #expect(
      set.pointerHandlerRegistry?.snapshot().count == 1,
      "the active recognizer's paired route must survive with it"
    )

    // While the recognizer's owner lives, the liveness pass keeps both.
    set.pruneOrphanedGestures(keeping: [node.viewNodeID])
    #expect(set.gestureRegistry?.snapshot().count == 1)
    #expect(set.pointerHandlerRegistry?.snapshot().count == 1)

    // The interaction site genuinely departs: the gesture prune releases
    // the recognizer (dead owner), and the paired sweep must release the
    // spared route with it — before the fix it leaked until the next full
    // reset.
    set.pruneOrphanedGestures(keeping: [])
    #expect(set.gestureRegistry?.snapshot().isEmpty == true)
    #expect(
      set.pointerHandlerRegistry?.snapshot().isEmpty == true,
      "a departed recognizer's paired pointer route must not outlive it"
    )
  }

  @Test("publication oracle excuses exactly the active-interaction window")
  func publicationOracleExcusesActiveInteractionWindow() {
    let rootIdentity = testIdentity("Root")
    // Enough siblings that a one-item frontier stays under the half-tree
    // cover threshold — otherwise the `.subtrees` commit escalates onto the
    // fingerprint-delta body and the scoped-restore oracle never runs.
    let itemIdentities = ["A", "B", "C"].map { testIdentity("Root", $0) }

    let graph = ViewGraph()
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    var children: [ResolvedNode] = []
    var itemNodes: [ViewNode] = []
    for identity in itemIdentities {
      let node = graph.beginEvaluation(identity: identity, invalidator: nil)
      node.recordActionRegistration(
        identity: identity,
        handler: { true },
        followUpInvalidationIdentity: nil
      )
      let resolvedChild = ResolvedNode(identity: identity, kind: .view("Item"))
      graph.finishEvaluation(node, resolved: resolvedChild, accessedStateSlots: 0)
      children.append(resolvedChild)
      itemNodes.append(node)
    }
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: children),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    let initialDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil,
      publicationDiagnosticsEnabled: false
    )
    initialDraft.recordDirtyEvaluationPlan(nil)
    _ = initialDraft.commitRuntimeRegistrations(from: graph)

    // The preserved-active shape: the live registries hold a recognizer and
    // its paired route for a row whose node records departed WITH the row
    // (no node record names them), kept alive only because the interaction
    // is in flight.
    let pressedRow = testIdentity("Root", "PressedRow")
    let recognizer = ActivatableProbeGesture()
    recognizer.phase = .began
    liveRegistrations.gestureRegistry?.register(
      identity: pressedRow,
      recognizer: AnyGestureRecognizer(recognizer)
    )
    liveRegistrations.pointerHandlerRegistry?.register(
      routeID: RouteID(identity: pressedRow)
    ) { _ in false }

    let probeEnabled = SoundnessProbeConfiguration.isEnabled
    let probeLatch = SoundnessProbeConfiguration.isSampledFrame
    let violationCount = SoundnessProbeConfiguration.registrationPublicationViolationCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = probeEnabled
      SoundnessProbeConfiguration.isSampledFrame = probeLatch
      SoundnessProbeConfiguration.registrationPublicationViolationCount = violationCount
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }
    SoundnessProbeConfiguration.isEnabled = true
    SoundnessProbeConfiguration.isSampledFrame = true

    func commitScoped() {
      let draft = ViewGraphFrameDraft(
        liveRegistrations: liveRegistrations,
        checkpoint: nil,
        publicationDiagnosticsEnabled: false
      )
      draft.recordDirtyEvaluationPlan(
        DirtyEvaluationPlan(
          frontierNodeIDs: [itemNodes[0].viewNodeID],
          frontierIdentities: [itemIdentities[0]]
        ),
        diagnostics: DirtyEvaluationPlanDiagnostics(result: "formed", frontierRootCount: 1)
      )
      _ = draft.commitRuntimeRegistrations(from: graph)
    }

    // While the recognizer is ACTIVE, the live-side extras are the designed
    // mid-interaction preservation window — a full reset-and-rebuild
    // (`resetAll`) would spare them too, so the oracle must not fire.
    commitScoped()
    #expect(
      SoundnessProbeConfiguration.registrationPublicationViolationCount == violationCount,
      "the active-interaction preservation window must not trip the F04 oracle"
    )

    // The excuse dies with the interaction: once the recognizer is no
    // longer active, the same live-side extras are a genuine retention leak
    // and the oracle must fire.
    recognizer.phase = .ended
    commitScoped()
    #expect(
      SoundnessProbeConfiguration.registrationPublicationViolationCount == violationCount + 1,
      "stale retention past the interaction must still trip the F04 oracle"
    )
  }
}

@MainActor
private final class ActivatableProbeGesture: GestureRecognizer {
  typealias Value = String

  var phase: GestureRecognizerPhase = .possible

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    .ignored
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool {
    false
  }

  func currentValue() -> String? {
    "probe"
  }

  func tearDown() {}

  func reArm() {}
}
