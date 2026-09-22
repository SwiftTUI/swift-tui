@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct RunLoopSoundnessReportingTests {
  @Test(arguments: [FrameTailJobState.cancelledBeforeStart, .droppedCompleted])
  func skippedFrameReportsWithoutPresentation(state: FrameTailJobState) throws {
    let restore = suppressInjectedViolation()
    defer { restore() }
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 2))
    let loop = makeLoop(surface: surface)
    var issues: [RuntimeIssue] = []
    loop.runtimeIssueSink = RuntimeIssueSink { issues.append($0) }
    loop.lastSeenSoundnessViolationCounts = .currentTotals()
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("discarded frame")
    let frame = ScheduledFrame(
      causes: [.invalidation], invalidatedIdentities: [], signalNames: [],
      externalReasons: [], triggeredDeadline: nil, nextDeadline: nil)
    let outcome = loop.recordSkippedCancellableFrame(
      .init(
        artifacts: nil, runtimeIssues: [], renderGeneration: RenderGeneration(1),
        tailJobState: state),
      scheduledFrame: frame,
      renderIntentDiagnostics: loop.nextRenderIntentDiagnostics(for: frame),
      renderedFrames: 0,
      convergence: .init()
    )
    guard case .skipped = outcome else {
      Issue.record("expected skipped acquisition")
      return
    }
    #expect(surface.frames.isEmpty)
    #expect(issues.map(\.code) == ["soundness.deltaCheckpoint"])
    #expect(issues.first?.message == "1 sampled soundness violation(s): discarded frame")

    loop.scheduler.requestInvalidation(of: [loop.rootIdentity])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(frames > 0)
    #expect(issues.count == 1)
  }

  @Test(arguments: [false, true])
  func emptyDrainReportsAndCleanDrainDoesNotDuplicate(synchronous: Bool) async throws {
    let restore = suppressInjectedViolation()
    defer { restore() }
    let loop = makeLoop()
    var issues: [RuntimeIssue] = []
    loop.runtimeIssueSink = RuntimeIssueSink { issues.append($0) }
    loop.lastSeenSoundnessViolationCounts = .currentTotals()
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("no pending frame")
    var frames = 0
    if synchronous {
      try loop.renderPendingFrames(renderedFrames: &frames)
    } else {
      try await loop.renderPendingFramesAsync(renderedFrames: &frames)
    }
    #expect(frames == 0)
    #expect(issues.count == 1)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(issues.count == 1)
  }

  @Test func reentrantSinkAndCounterReset() {
    let restore = suppressInjectedViolation()
    defer { restore() }
    let loop = makeLoop()
    var issues: [RuntimeIssue] = []
    loop.lastSeenSoundnessViolationCounts = .currentTotals()
    loop.runtimeIssueSink = RuntimeIssueSink { issue in
      issues.append(issue)
      // Without publishing the baseline before delivery this recurses forever.
      loop.reportNewSoundnessProbeViolations()
    }
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("first")
    loop.reportNewSoundnessProbeViolations()
    #expect(issues.count == 1)
    SoundnessProbeConfiguration.deltaCheckpointViolationCount = 0
    loop.reportNewSoundnessProbeViolations()
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("after reset")
    loop.reportNewSoundnessProbeViolations()
    #expect(issues.count == 2)
    #expect(issues.last?.message.contains("after reset") == true)
  }

  @Test func shutdownDeliversViolationAfterLastFrame() async throws {
    let restore = suppressInjectedViolation()
    defer { restore() }
    let identity = testIdentity("SoundnessShutdown")
    let input = InjectedTerminalInputReader()
    input.finish()
    let loop = RunLoop(
      rootIdentity: identity,
      presentationSurface: SoundnessShutdownSurface(),
      terminalInputReader: input,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity])
    ) { _, _ in
      Text("ready")
    }
    var issues: [RuntimeIssue] = []
    loop.runtimeIssueSink = RuntimeIssueSink { issues.append($0) }
    // Pre-session growth must be baselined away by run().
    SoundnessProbeConfiguration.recordDeltaCheckpointViolation("before session")
    _ = try await loop.run()
    #expect(issues.map(\.code) == ["soundness.deltaCheckpoint"])
    #expect(issues.first?.message == "1 sampled soundness violation(s): shutdown")
  }

  private func makeLoop(
    surface: RecordingPresentationSurface = RecordingPresentationSurface(
      surfaceSize: .init(width: 20, height: 2))
  ) -> RunLoop<Int, Text> {
    let identity = testIdentity("SoundnessReporting")
    return RunLoop(
      rootIdentity: identity,
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity])
    ) { _, _ in Text("ready") }
  }

  private func suppressInjectedViolation() -> () -> Void {
    let enabled = SoundnessProbeConfiguration.isEnabled
    let traced = SoundnessProbeConfiguration.isTraceEnabled
    let count = SoundnessProbeConfiguration.deltaCheckpointViolationCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    let details = SoundnessProbeConfiguration.lastViolationDetailByKind
    SoundnessProbeConfiguration.isEnabled = false
    SoundnessProbeConfiguration.isTraceEnabled = false
    return {
      SoundnessProbeConfiguration.isEnabled = enabled
      SoundnessProbeConfiguration.isTraceEnabled = traced
      SoundnessProbeConfiguration.deltaCheckpointViolationCount = count
      SoundnessProbeConfiguration.lastViolationDetail = detail
      SoundnessProbeConfiguration.lastViolationDetailByKind = details
    }
  }
}

private final class SoundnessShutdownSurface: PresentationSurface {
  let surfaceSize = CellSize(width: 20, height: 2)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback

  func enableRawMode() throws {}
  func disableRawMode() throws {
    MainActor.assumeIsolated {
      SoundnessProbeConfiguration.recordDeltaCheckpointViolation("shutdown")
    }
  }
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}
