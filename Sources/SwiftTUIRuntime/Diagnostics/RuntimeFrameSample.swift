import SwiftTUICore

/// Raw, self-contained inputs for one frame's diagnostics, captured at the emit
/// point. Carries already-computed `Sendable` pipeline products plus the few
/// run-loop-resolved scalars that cannot be recomputed downstream (drained
/// input counts, eligibility blockers, animation-controller state). Holds no
/// formatting or derived fields — the profiling product turns this into a
/// `FrameDiagnosticRecord`.
@_spi(Runners) public enum RuntimeFrameSample: Sendable {
  case committed(CommittedFrameSample)
  case zeroArtifact(ZeroArtifactFrameSample)
  case elided(ElidedFrameSample)
}

/// Inputs for an off-screen-elided frame. Like ``ZeroArtifactFrameSample`` it
/// produces no pipeline artifacts, but it is distinct: the frame ran its
/// reduced commit (firing completions, advancing animation state) and is
/// recorded as `elided` rather than cancelled or dropped. The animation
/// controller scalars are captured at the emit point, after the reduced commit
/// has published the advanced live state.
@_spi(Runners) public struct ElidedFrameSample: Sendable {
  package var frameNumber: Int
  package var scheduledFrame: ScheduledFrame
  package var desiredGeneration: UInt64
  package var coalescedEventBatches: Int
  package var coalescedWakeCauses: Set<WakeCause>
  package var intentRequestCount: Int
  package var animationControllerActiveAnimationCount: Int
  package var animationControllerHasPendingWork: Bool
  package var cancelledRenderCount: Int

  package init(
    frameNumber: Int,
    scheduledFrame: ScheduledFrame,
    desiredGeneration: UInt64,
    coalescedEventBatches: Int,
    coalescedWakeCauses: Set<WakeCause>,
    intentRequestCount: Int,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool,
    cancelledRenderCount: Int
  ) {
    self.frameNumber = frameNumber
    self.scheduledFrame = scheduledFrame
    self.desiredGeneration = desiredGeneration
    self.coalescedEventBatches = coalescedEventBatches
    self.coalescedWakeCauses = coalescedWakeCauses
    self.intentRequestCount = intentRequestCount
    self.animationControllerActiveAnimationCount = animationControllerActiveAnimationCount
    self.animationControllerHasPendingWork = animationControllerHasPendingWork
    self.cancelledRenderCount = cancelledRenderCount
  }
}

/// Inputs for a normally committed frame.
///
/// The render-intent coalescing numbers are flattened in (rather than carrying
/// the run-loop-nested `RenderIntentCoalescingDiagnostics`) so the sample stays
/// a free, non-generic value type.
@_spi(Runners) public struct CommittedFrameSample: Sendable {
  package var frameNumber: Int
  package var scheduledFrame: ScheduledFrame
  package var diagnostics: FrameDiagnostics
  package var desiredGeneration: UInt64
  package var coalescedEventBatches: Int
  package var coalescedWakeCauses: Set<WakeCause>
  package var intentRequestCount: Int
  package var focusSyncRerenders: Int
  package var animationControllerActiveAnimationCount: Int
  package var animationControllerHasPendingWork: Bool
  package var cancelledRenderCount: Int
  package var inputEventsQueuedDuringRenderSuspension: Int
  package var dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
  package var completedFrameDropDecision: CompletedFrameDropDecision?
  package var tailJobState: FrameTailJobState
  package var presentationMetrics: PresentationMetrics
  package var presentationDuration: Duration

  package init(
    frameNumber: Int,
    scheduledFrame: ScheduledFrame,
    diagnostics: FrameDiagnostics,
    desiredGeneration: UInt64,
    coalescedEventBatches: Int,
    coalescedWakeCauses: Set<WakeCause>,
    intentRequestCount: Int,
    focusSyncRerenders: Int,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool,
    cancelledRenderCount: Int,
    inputEventsQueuedDuringRenderSuspension: Int,
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>,
    completedFrameDropDecision: CompletedFrameDropDecision?,
    tailJobState: FrameTailJobState,
    presentationMetrics: PresentationMetrics,
    presentationDuration: Duration
  ) {
    self.frameNumber = frameNumber
    self.scheduledFrame = scheduledFrame
    self.diagnostics = diagnostics
    self.desiredGeneration = desiredGeneration
    self.coalescedEventBatches = coalescedEventBatches
    self.coalescedWakeCauses = coalescedWakeCauses
    self.intentRequestCount = intentRequestCount
    self.focusSyncRerenders = focusSyncRerenders
    self.animationControllerActiveAnimationCount = animationControllerActiveAnimationCount
    self.animationControllerHasPendingWork = animationControllerHasPendingWork
    self.cancelledRenderCount = cancelledRenderCount
    self.inputEventsQueuedDuringRenderSuspension = inputEventsQueuedDuringRenderSuspension
    self.dropEligibilityBlockers = dropEligibilityBlockers
    self.completedFrameDropDecision = completedFrameDropDecision
    self.tailJobState = tailJobState
    self.presentationMetrics = presentationMetrics
    self.presentationDuration = presentationDuration
  }
}

/// Inputs for a frame that produced no pipeline artifacts (cancelled tail or
/// dropped completed). The string fields are run-loop facts (enum raw values
/// and fixed policy tags), captured verbatim at the emit point.
@_spi(Runners) public struct ZeroArtifactFrameSample: Sendable {
  package var frameNumber: Int
  package var scheduledFrame: ScheduledFrame
  package var desiredGeneration: UInt64
  package var coalescedEventBatches: Int
  package var coalescedWakeCauses: Set<WakeCause>
  package var intentRequestCount: Int
  package var renderGeneration: RenderGeneration
  package var runtimeIssues: [RuntimeIssue]
  package var staleFramePolicy: String
  package var tailJobState: String
  package var tailCancelReason: String
  package var newestDesiredAtTailResult: UInt64
  package var animationControllerActiveAnimationCount: Int
  package var animationControllerHasPendingWork: Bool
  package var cancelledRenderCount: Int
  package var inputEventsQueuedDuringRenderSuspension: Int
  package var dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
  package var dropDecision: String
  package var dropGeneration: UInt64?
  package var newestDesiredAtDrop: UInt64?
  package var dropReconciliationMode: String
  package var dropReconciliationEffects: String

  package init(
    frameNumber: Int,
    scheduledFrame: ScheduledFrame,
    desiredGeneration: UInt64,
    coalescedEventBatches: Int,
    coalescedWakeCauses: Set<WakeCause>,
    intentRequestCount: Int,
    renderGeneration: RenderGeneration,
    runtimeIssues: [RuntimeIssue],
    staleFramePolicy: String,
    tailJobState: String,
    tailCancelReason: String,
    newestDesiredAtTailResult: UInt64,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool,
    cancelledRenderCount: Int,
    inputEventsQueuedDuringRenderSuspension: Int,
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>,
    dropDecision: String,
    dropGeneration: UInt64?,
    newestDesiredAtDrop: UInt64?,
    dropReconciliationMode: String,
    dropReconciliationEffects: String
  ) {
    self.frameNumber = frameNumber
    self.scheduledFrame = scheduledFrame
    self.desiredGeneration = desiredGeneration
    self.coalescedEventBatches = coalescedEventBatches
    self.coalescedWakeCauses = coalescedWakeCauses
    self.intentRequestCount = intentRequestCount
    self.renderGeneration = renderGeneration
    self.runtimeIssues = runtimeIssues
    self.staleFramePolicy = staleFramePolicy
    self.tailJobState = tailJobState
    self.tailCancelReason = tailCancelReason
    self.newestDesiredAtTailResult = newestDesiredAtTailResult
    self.animationControllerActiveAnimationCount = animationControllerActiveAnimationCount
    self.animationControllerHasPendingWork = animationControllerHasPendingWork
    self.cancelledRenderCount = cancelledRenderCount
    self.inputEventsQueuedDuringRenderSuspension = inputEventsQueuedDuringRenderSuspension
    self.dropEligibilityBlockers = dropEligibilityBlockers
    self.dropDecision = dropDecision
    self.dropGeneration = dropGeneration
    self.newestDesiredAtDrop = newestDesiredAtDrop
    self.dropReconciliationMode = dropReconciliationMode
    self.dropReconciliationEffects = dropReconciliationEffects
  }
}
