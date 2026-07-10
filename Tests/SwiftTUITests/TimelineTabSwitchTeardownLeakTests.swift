import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Gallery pointer-tab regression: switching away from a tab whose payload
/// hosts a live `TimelineView(.animation)` (the task-progress shimmer shape)
/// stranded the timeline's value-dropped `EmptyView` mint — a stored node with
/// no parent, no evaluation host, and no hosted-detached ledger edge,
/// unreachable from the committed root. The F04/F91 teardown-coherence census
/// reported it as `teardown coherence: 1 stored node(s) unreachable from the
/// committed root: … TabContentPayload[…]/…/Group[0] [parent=nil evalHost=nil
/// ledger=none lifecycle=alive]` — the runtime warning users saw in the
/// gallery.
///
/// The strand: `TimelineView.timelineBody`'s `_ = hasAdvanced` statement
/// becomes an `EmptyView` element via `ViewBuilder.buildExpression(_: ())`,
/// so the body is a two-element tuple whose `Group[0]` mint is value-dropped
/// by `appendDeclaredChildNodes`. The mint lived in no children array and no
/// hosted ledger, so the tab payload's teardown cascade could never reach it.
/// The fix anchors value-dropped `EmptyView`/spliced-`Group` mints to their
/// evaluating host with hosted-detached edges at the drop site.
@MainActor
@Suite
struct TimelineTabSwitchTeardownLeakTests {
  @Test("leaving a tab with a live TimelineView leaves no teardown-coherence strand")
  func leavingTimelineTabLeavesNoTeardownStrand() async throws {
    let harness = try TimelineTabLeakHarness()
    defer { harness.shutdown() }

    #expect(
      harness.frame.contains("shimmer-pane"),
      "the shimmer tab must render first; frame:\n\(harness.frame)"
    )

    // Let the timeline task advance the instant at least once so the
    // content island is live (bounded condition wait, not a fixed sleep).
    try await harness.waitForTimelineAdvance()

    // Switch to the plain tab via the strip — tears down the shimmer payload.
    try harness.clickText("PlainTab")
    #expect(
      harness.frame.contains("plain-pane"),
      "the plain tab must be visible after the switch; frame:\n\(harness.frame)"
    )

    // Render further frames so the census re-runs post-teardown, then run it
    // against THIS harness's graph. The process-global probe counters
    // interleave with other suites' known residual violations under parallel
    // test execution, so the assertion must stay instance-scoped.
    try harness.renderCensusFrames(4)
    let violation = harness.teardownCoherenceViolation()
    #expect(
      violation == nil,
      """
      switching away from the TimelineView tab stranded stored node(s): \
      \(violation?.detail ?? "")
      """
    )

    // Returning to the shimmer tab must also stay clean (re-adoption path).
    try harness.clickText("ShimmerTab")
    try await harness.waitForTimelineAdvance()
    try harness.renderCensusFrames(4)
    let roundTripViolation = harness.teardownCoherenceViolation()
    #expect(
      roundTripViolation == nil,
      """
      returning to the TimelineView tab left stranded stored node(s): \
      \(roundTripViolation?.detail ?? "")
      """
    )
  }
}

/// Mirrors the gallery task-progress panel shape at minimum depth: the tab
/// payload hosts a VStack whose header row embeds a `TimelineView(.animation)`
/// (the shimmering title) next to plain text.
@MainActor
private struct TimelineTabLeakFixture: View {
  @State private var selection = 1

  var body: some View {
    TabView(selection: $selection) {
      Tab("PlainTab", value: 0) {
        Text("plain-pane")
      }
      Tab("ShimmerTab", value: 1) {
        ShimmerPane()
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

@MainActor
private struct ShimmerPane: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text("shimmer-pane")
        TimelineView(.animation) { context in
          let millis =
            Int(context.instant.offset.components.attoseconds / 1_000_000_000_000_000)
            &+ Int(context.instant.offset.components.seconds &* 1000)
          HStack(spacing: 0) {
            Text("tick \(millis)")
          }
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
    }
  }
}

@MainActor
private final class TimelineTabLeakHarness {
  private let terminal: TimelineTabLeakRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, TimelineTabLeakFixture>
  private let scheduler: FrameScheduler
  private let rootIdentity = testIdentity("TimelineTabLeakRoot")
  private var renderedFrames = 0
  private var didShutdown = false

  /// Pulsed from the scheduler's wake handler: the timeline `.task`'s state
  /// writes request invalidations, and the wake is the poll-free signal that
  /// a pending frame is ready to render.
  private let schedulerWake = MainActorConditionSignal()

  init() throws {
    let size = CellSize(width: 72, height: 10)
    let terminal = TimelineTabLeakRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: TimelineTabLeakEmptyKeyReader(),
      signalReader: TimelineTabLeakEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in TimelineTabLeakFixture() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    let schedulerWake = self.schedulerWake
    scheduler.setWakeHandler {
      Task { @MainActor in
        schedulerWake.notify()
      }
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String { terminal.frames.last ?? "" }

  /// Instance-scoped teardown-coherence census (see
  /// `ViewGraph.debugTeardownCoherenceViolation()`).
  func teardownCoherenceViolation()
    -> (isOverRemoval: Bool, detail: String, unreachableCount: Int)?
  {
    runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()
  }

  func shutdown() {
    guard !didShutdown else { return }
    didShutdown = true
    scheduler.setWakeHandler(nil)
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return terminal.frames.last ?? ""
  }

  @discardableResult
  func clickText(_ label: String) throws -> String {
    let point = try #require(
      terminal.centerOfText(label),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }

  /// Poll-free wait until the timeline task has written a new instant (the
  /// rendered tick text changes): each iteration suspends on the scheduler's
  /// wake signal until a frame is pending, renders it, and re-checks. The
  /// animation schedule keeps producing ticks, so progress is guaranteed
  /// while the timeline is mounted.
  func waitForTimelineAdvance() async throws {
    let before = frame
    while frame == before {
      let scheduler = self.scheduler
      await schedulerWake.wait(until: { scheduler.hasPendingFrame() })
      _ = try render()
    }
  }

  /// Renders further frames synchronously so the teardown census re-runs
  /// after a structural change.
  func renderCensusFrames(_ count: Int) throws {
    for _ in 0..<count {
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try render()
    }
  }
}

private final class TimelineTabLeakRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []

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
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
  }

  func centerOfText(_ target: String) -> Point? {
    guard let frame = frames.last else { return nil }
    for (row, line) in frame.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let text = String(line)
      guard let range = text.range(of: target) else { continue }
      let column = text.distance(from: text.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class TimelineTabLeakEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class TimelineTabLeakEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
