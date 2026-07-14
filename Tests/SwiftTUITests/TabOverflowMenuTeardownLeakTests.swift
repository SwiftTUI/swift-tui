import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Gallery tab-strip regression: selecting a tab from the expanded overflow
/// menu (the `▾` trigger) collapses the menu and switches the payload in one
/// gesture. The teardown-coherence census then reported the re-rooted
/// `TabOverflowItem[…]` row subtrees — plus the menu's structural ForEach
/// element — as stored nodes unreachable from the committed root.
@MainActor
@Suite
struct TabOverflowMenuTeardownLeakTests {
  @Test("selecting an overflow tab leaves no teardown-coherence strand")
  func selectingOverflowTabLeavesNoTeardownStrand() throws {
    let harness = try TabOverflowLeakHarness()
    defer { harness.shutdown() }

    #expect(
      harness.frame.contains("alpha-pane"),
      "the first tab must render initially; frame:\n\(harness.frame)"
    )
    #expect(
      harness.frame.contains("▾"),
      "the overflow trigger must be present; frame:\n\(harness.frame)"
    )

    // Expand the overflow menu.
    try harness.clickText("▾")
    #expect(
      harness.frame.contains("Golf"),
      "the expanded overflow menu must list the overflow tabs; frame:\n\(harness.frame)"
    )

    // Select an overflow tab: switches selection AND collapses the menu in
    // the same pointer gesture (the gallery flow).
    try harness.clickText("Golf")
    #expect(
      harness.frame.contains("golf-pane"),
      "the overflow tab's payload must be visible after the switch; frame:\n\(harness.frame)"
    )

    try harness.renderCensusFrames(4)
    let violation = harness.teardownCoherenceViolation()
    #expect(
      violation == nil,
      """
      selecting a tab from the overflow menu stranded stored node(s): \
      \(violation?.detail ?? "")
      """
    )

    // Re-open and re-close the menu without selecting: collapse via the
    // trigger toggle must also stay clean. With an overflow tab selected the
    // trigger renders the selected glyphs (`▼` collapsed, `▲` expanded).
    try harness.clickText("▼")
    try harness.clickText("▲")
    try harness.renderCensusFrames(4)
    let toggleViolation = harness.teardownCoherenceViolation()
    #expect(
      toggleViolation == nil,
      """
      toggling the overflow menu open/closed stranded stored node(s): \
      \(toggleViolation?.detail ?? "")
      """
    )
  }
}

/// Eight tabs in a 44-column terminal: the literal-tabs style fits only the
/// first few in the strip and routes the rest through the overflow menu.
@MainActor
private struct TabOverflowLeakFixture: View {
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("Alpha", value: 0) { Text("alpha-pane") }
      Tab("Bravo", value: 1) { Text("bravo-pane") }
      Tab("Charlie", value: 2) { Text("charlie-pane") }
      Tab("Delta", value: 3) { Text("delta-pane") }
      Tab("Echo", value: 4) { Text("echo-pane") }
      Tab("Foxtrot", value: 5) { Text("foxtrot-pane") }
      Tab("Golf", value: 6) { Text("golf-pane") }
      Tab("Hotel", value: 7) { Text("hotel-pane") }
    }
    .tabViewStyle(.literalTabs)
  }
}

@MainActor
private final class TabOverflowLeakHarness {
  private let terminal: TabOverflowLeakRecordingHost
  let runLoop: SwiftTUIRuntime.RunLoop<Int, TabOverflowLeakFixture>
  private let scheduler: FrameScheduler
  private let rootIdentity = testIdentity("TabOverflowLeakRoot")
  private var renderedFrames = 0
  private var didShutdown = false

  init() throws {
    let size = CellSize(width: 44, height: 16)
    let terminal = TabOverflowLeakRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: TabOverflowLeakEmptyKeyReader(),
      signalReader: TabOverflowLeakEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in TabOverflowLeakFixture() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

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

  /// Renders further frames synchronously so the teardown census re-runs
  /// after a structural change.
  func renderCensusFrames(_ count: Int) throws {
    for _ in 0..<count {
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try render()
    }
  }
}

private final class TabOverflowLeakRecordingHost: PresentationSurface {
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

private final class TabOverflowLeakEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class TabOverflowLeakEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
