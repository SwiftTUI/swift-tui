import SwiftTUICore

// Frame-drop blocker derivation for the run loop.
//
// `RunLoop+FrameDiagnosticRecordAssembly.swift` assembles the per-frame
// diagnostic record; this file owns the related question of *why a frame
// cannot be dropped* — collecting the runtime-context blockers that, together
// with the artifact-level signals, decide whether a completed frame is
// visual-only or must commit.
extension RunLoop {
  func frameDropEligibilityBlockers(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    focusGraphChanged: Bool,
    focusBindingChanged: Bool,
    focusedValuesChanged: Bool,
    scrollPositionChanged: Bool,
    preferenceObservationChanged: Bool,
    diagnosticsRequireFullRecord: Bool
  ) -> Set<FrameDropEligibility.Blocker> {
    var additionalBlockers = renderer.internalAnimationController.frameDropEligibilityBlockers
    if focusGraphChanged {
      additionalBlockers.insert(.focusGraph)
    }
    if focusBindingChanged {
      additionalBlockers.insert(.focusBindingSync)
    }
    if focusedValuesChanged {
      additionalBlockers.insert(.focusedValueSync)
    }
    if scrollPositionChanged {
      additionalBlockers.insert(.scrollSync)
    }
    if preferenceObservationChanged {
      additionalBlockers.insert(.preferenceObservationDelta)
    }
    if scheduledFrame.animationRequest != .inherit {
      additionalBlockers.insert(.animationTransaction)
    }
    if diagnosticsRequireFullRecord {
      additionalBlockers.insert(.diagnosticsFullRecord)
    }
    return FrameDropEligibility.classify(
      artifacts,
      additionalBlockers: additionalBlockers
    ).blockers
  }

  func droppedFrameBlockers(
    from decision: CompletedFrameDropDecision?
  ) -> Set<FrameDropEligibility.Blocker> {
    guard let decision else {
      return []
    }
    switch decision.eligibility {
    case .mustCommit(let blockers):
      return blockers
    case .canDropVisualOnly:
      return []
    }
  }
}
