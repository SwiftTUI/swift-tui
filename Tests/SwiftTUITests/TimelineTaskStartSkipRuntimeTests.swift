import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F43 residual: TermUIPerf's `synthetic-text-shimmer` scenario deterministically
/// drops a `.task` on a Layout-hosted Group ("no task registration at commit") —
/// the silent task-start-skip class the F43 counter exists to surface. This
/// drives the same reduced shape on a real `RunLoop`: a `TimelineView` (whose
/// body attaches `.task(id:)` to its content) inside a padded `VStack`.
///
/// The observable contract: the committed plan's `.taskStart` entries must all
/// find their registration at commit — `taskStartSkipCount` stays zero and the
/// timeline task is live after the first committed frame.
@MainActor
@Suite
struct TimelineTaskStartSkipRuntimeTests {
  @Test("TimelineView content inside a padded VStack starts its task without a start-skip")
  func timelineTaskStartsWithoutSkip() throws {
    let harness = try ShimmerSkipHarness()

    #expect(
      harness.frame.contains("shimmer"),
      "the timeline content must render on the first frame; frame:\n\(harness.frame)"
    )
    #expect(
      harness.taskStartSkipCount == 0,
      "no committed .taskStart may be dropped at commit; skips=\(harness.taskStartSkipCount) issues=\(harness.reportedIssues)"
    )
    #expect(
      harness.activeTaskCount == 1,
      "the timeline task must be running after the first committed frame; count=\(harness.activeTaskCount) descriptors=\(harness.activeDescriptorIDs) registry=\(harness.registeredDescriptorIDs)"
    )
    let firstFrameDescriptors = harness.activeDescriptorIDs

    // A warm re-resolve of the same chain must keep the SAME task descriptor
    // and the same running task — a changed descriptor label would plan a
    // spurious cancel + restart of a task whose `.task(id:)` value never
    // changed.
    harness.invalidateRoot()
    _ = try harness.render()
    #expect(
      harness.taskStartSkipCount == 0,
      "a warm re-resolve must not skip task starts; skips=\(harness.taskStartSkipCount) issues=\(harness.reportedIssues)"
    )
    #expect(
      harness.activeTaskCount == 1,
      "the timeline task must survive a warm re-resolve; count=\(harness.activeTaskCount) descriptors=\(harness.activeDescriptorIDs)"
    )
    #expect(
      harness.activeDescriptorIDs == firstFrameDescriptors,
      "a stable .task(id:) must keep its descriptor across re-resolves; was \(firstFrameDescriptors), now \(harness.activeDescriptorIDs)"
    )
    // F163 zero-oracle: the handler legs share the task path's contract — no
    // committed appear/disappear/change handler may be dropped at commit.
    #expect(harness.lifecycleHandlerSkipCounts == [0, 0, 0])
  }
}

@MainActor
private struct ShimmerSkipProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TimelineView(.animation) { context in
        let millis =
          Int(context.instant.offset.components.attoseconds / 1_000_000_000_000_000)
          &+ Int(context.instant.offset.components.seconds &* 1000)
        Text("shimmer \(millis)")
      }
    }
    .padding(1)
  }
}

@MainActor
private final class ShimmerSkipHarness {
  private let terminal: ShimmerSkipRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, ShimmerSkipProbeView>
  private let scheduler: FrameScheduler
  private var renderedFrames = 0
  private(set) var reportedIssues: [String] = []

  init() throws {
    let size = CellSize(width: 60, height: 8)
    let terminal = ShimmerSkipRecordingHost(surfaceSize: size)
    let rootIdentity = testIdentity("ShimmerSkipRoot")
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: ShimmerSkipEmptyKeyReader(),
      signalReader: ShimmerSkipEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in ShimmerSkipProbeView() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler
    runLoop.runtimeIssueSink = RuntimeIssueSink { [weak self] issue in
      self?.reportedIssues.append(issue.description)
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  var taskStartSkipCount: Int { runLoop.lifecycleCoordinator.taskStartSkipCount }

  var lifecycleHandlerSkipCounts: [Int] {
    [
      runLoop.lifecycleCoordinator.appearHandlerSkipCount,
      runLoop.lifecycleCoordinator.disappearHandlerSkipCount,
      runLoop.lifecycleCoordinator.changeHandlerSkipCount,
    ]
  }

  var activeTaskCount: Int { runLoop.lifecycleCoordinator.activeTaskCount }

  var activeDescriptorIDs: [String] {
    runLoop.lifecycleCoordinator.activeTaskDescriptors.values
      .flatMap { $0.map(\.id) }
      .sorted()
  }

  var registeredDescriptorIDs: [String] {
    runLoop.localTaskRegistry.snapshot().values
      .flatMap { $0.map(\.descriptor.id) }
      .sorted()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  func invalidateRoot() {
    scheduler.requestInvalidation(of: [testIdentity("ShimmerSkipRoot")])
  }
}

private final class ShimmerSkipRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  let frameSignal = MainActorConditionSignal()

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private final class ShimmerSkipEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class ShimmerSkipEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
