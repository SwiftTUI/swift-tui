@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A toolbar scope above a lazy `TabView` absorbs one item the shell declares
/// and one item the selected tab contributes, so switching tabs changes the
/// strip's item set: the tab's item takes the first slot and the shell's item
/// moves to the second.
///
/// The strip resolves beside the host's content, outside every invalidation
/// cone, so value-blind retained reuse served its interior from the previous
/// item set whenever the host re-resolved it. The late-preference stage then
/// produced the presented strip, but the asynchronous render modes run that
/// stage against the committed graph and discard its graph effects at commit.
/// The screen showed the new items while the first slot's graph node kept the
/// shell's button, which re-registered the shell's action on the next press:
/// clicking the tab's item ran its neighbor (the gallery's "Reset counter"
/// opening the command palette).
///
/// The shell mirrors the gallery's: a presentation modifier above the toolbar
/// scope is what keeps the strip's interior out of the frame's recompute cone.
@MainActor
@Suite(.serialized)
struct ToolbarStripItemSetChangeTests {
  @Test(
    "a toolbar item that joins the strip on a tab switch runs its own action",
    arguments: [RuntimeRenderMode.sync, .async, .asyncNoCancel, .asyncNoDrop]
  )
  func joinedToolbarItemRunsOwnAction(mode: RuntimeRenderMode) async throws {
    let harness = try await ToolbarStripItemSetHarness.start(mode: mode)
    defer { harness.stop() }

    try await harness.click("Counter", thenShows: "Reset counter")
    try await harness.click("Reset counter", thenRuns: ["reset from 0"])
    try await harness.click("Palette", thenRuns: ["reset from 0", "palette"])
    try await harness.finish()
    #expect(
      harness.mismatchedFrames.isEmpty,
      "presented a strip that disagrees with its page:\n\(harness.mismatchedFrames.joined())"
    )
  }

  @Test(
    "a strip item runs the action its tab authored last",
    arguments: [RuntimeRenderMode.sync, .async, .asyncNoCancel, .asyncNoDrop]
  )
  func stripItemRunsLastAuthoredAction(mode: RuntimeRenderMode) async throws {
    let harness = try await ToolbarStripItemSetHarness.start(mode: mode)
    defer { harness.stop() }

    try await harness.click("Counter", thenShows: "Reset counter")
    try await harness.click("Increment", thenShows: "count 1")
    try await harness.click("Increment", thenShows: "count 2")
    try await harness.click("Reset counter", thenRuns: ["reset from 2"])
    try await harness.waitForScreen(showing: "count 0")
    try await harness.click("Increment", thenShows: "count 1")
    try await harness.click("Reset counter", thenRuns: ["reset from 2", "reset from 1"])
    try await harness.click("Palette", thenRuns: ["reset from 2", "reset from 1", "palette"])
    try await harness.finish()
    #expect(
      harness.mismatchedFrames.isEmpty,
      "presented a strip that disagrees with its page:\n\(harness.mismatchedFrames.joined())"
    )
  }

  @Test(
    "a toolbar item that leaves the strip hands its slot back",
    arguments: [RuntimeRenderMode.sync, .async, .asyncNoCancel, .asyncNoDrop]
  )
  func departedToolbarItemHandsSlotBack(mode: RuntimeRenderMode) async throws {
    let harness = try await ToolbarStripItemSetHarness.start(mode: mode)
    defer { harness.stop() }

    try await harness.click("Counter", thenShows: "Reset counter")
    try await harness.click("Home", thenShows: "home page")
    try await harness.click("Palette", thenRuns: ["palette"])
    try await harness.finish()
    #expect(
      harness.mismatchedFrames.isEmpty,
      "presented a strip that disagrees with its page:\n\(harness.mismatchedFrames.joined())"
    )
  }
}

/// Drives a real `RunLoop` with pointer input and synchronises on presented
/// frames and dispatched actions: both pulse one `MainActorConditionSignal`,
/// and every wait is bounded in presented frames rather than wall-clock time.
@MainActor
private final class ToolbarStripItemSetHarness {
  private let host: ToolbarStripItemSetRecordingHost
  private let inputReader: InjectedTerminalInputReader
  private let log: ToolbarStripItemSetActionLog
  private let updates: MainActorConditionSignal
  private var runTask: Task<Void, any Error>?

  /// Presented frames whose strip does not match the page they show.
  var mismatchedFrames: [String] { host.mismatchedFrames }

  private var screen: String {
    host.lastPresentedSurface?.lines.joined(separator: "\n") ?? ""
  }

  private init(
    host: ToolbarStripItemSetRecordingHost,
    inputReader: InjectedTerminalInputReader,
    log: ToolbarStripItemSetActionLog,
    updates: MainActorConditionSignal
  ) {
    self.host = host
    self.inputReader = inputReader
    self.log = log
    self.updates = updates
  }

  static func start(mode: RuntimeRenderMode) async throws -> ToolbarStripItemSetHarness {
    let size = CellSize(width: 60, height: 14)
    let rootIdentity = testIdentity("ToolbarStripItemSetRoot-\(mode.rawValue)")
    var environment = EnvironmentValues()
    environment.terminalSize = size
    let updates = MainActorConditionSignal()
    let host = ToolbarStripItemSetRecordingHost(size: size, updates: updates)
    let inputReader = InjectedTerminalInputReader()
    let log = ToolbarStripItemSetActionLog(updates: updates)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: host,
      terminalInputReader: inputReader,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      environmentValues: environment,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in ToolbarStripItemSetShell(log: log) }
    )
    focusTracker.invalidator = scheduler
    runLoop.renderMode = mode

    let harness = ToolbarStripItemSetHarness(
      host: host, inputReader: inputReader, log: log, updates: updates)
    harness.runTask = Task { _ = try await runLoop.run() }
    try await harness.waitForScreen(showing: "home page")
    return harness
  }

  func click(_ label: String, thenShows expected: String) async throws {
    try click(label)
    try await waitForScreen(showing: expected)
  }

  func click(_ label: String, thenRuns expected: [String]) async throws {
    try click(label)
    try await wait("an action after clicking \(label)") {
      self.log.entries.count >= expected.count
    }
    #expect(
      log.entries == expected,
      "clicking \(label) ran \(log.entries), expected \(expected):\n\(screen)"
    )
  }

  /// Waits for a presented frame that shows `text` under a strip matching the
  /// page it shows.
  func waitForScreen(showing text: String) async throws {
    try await wait("a frame showing \(text)") {
      self.screen.contains(text) && self.host.lastFrameStripMatchesPage
    }
  }

  func finish() async throws {
    inputReader.finish()
    let task = try #require(runTask)
    runTask = nil
    try await task.value
  }

  func stop() {
    inputReader.finish()
    runTask?.cancel()
  }

  private func wait(
    _ label: String,
    until predicate: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    do {
      try await updates.wait(
        until: predicate, for: label,
        within: ProgressBudget(stages: 64), on: host.presentedFrames
      )
    } catch let error as StageBudgetExceeded {
      throw ToolbarStripItemSetWaitFailure(
        expectation: error.description, actions: log.entries, screen: screen)
    }
  }

  private func click(_ label: String) throws {
    let surface = try #require(host.lastPresentedSurface)
    let point = try #require(
      Self.center(of: label, in: surface),
      "could not locate \(label) in:\n\(surface.lines.joined(separator: "\n"))"
    )
    inputReader.send(.mouse(.init(kind: .down(.primary), location: point)))
    inputReader.send(.mouse(.init(kind: .up(.primary), location: point)))
  }

  private static func center(of target: String, in surface: RasterSurface) -> Point? {
    for (row, line) in surface.lines.enumerated() {
      guard let range = line.firstRange(of: target) else { continue }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private struct ToolbarStripItemSetWaitFailure: Error, CustomStringConvertible {
  let expectation: String
  let actions: [String]
  let screen: String

  var description: String {
    "\(expectation) Actions run: \(actions). Last frame:\n\(screen)"
  }
}

@MainActor
private final class ToolbarStripItemSetActionLog {
  private(set) var entries: [String] = []
  private let updates: MainActorConditionSignal

  init(updates: MainActorConditionSignal) {
    self.updates = updates
  }

  func record(_ entry: String) {
    entries.append(entry)
    updates.notify()
  }
}

private struct ToolbarStripItemSetShell: View {
  let log: ToolbarStripItemSetActionLog
  @State private var selection = 0
  @State private var showsPalette = false

  var body: some View {
    ToolbarStripItemSetShellContent(selection: $selection, log: log)
      .toolbarItem(
        .init(
          title: "Palette",
          action: { log.record("palette") }
        )
      )
      .panel(id: "toolbar-strip-item-set")
      .keyCommand(
        "Command palette",
        key: .character("k"),
        modifiers: .ctrl,
        action: { showsPalette = true }
      )
      .paletteCommand(name: "Home", action: { selection = 0 })
      .paletteCommand(name: "Counter", action: { selection = 1 })
      .toolbar().toolbarStyle(.defaultBottom)
      .paletteSheet("Command palette", isPresented: $showsPalette)
  }
}

private struct ToolbarStripItemSetShellContent: View {
  @Binding var selection: Int
  let log: ToolbarStripItemSetActionLog

  var body: some View {
    TabView(selection: $selection) {
      Tab("Home", value: 0) {
        Text("home page")
      }
      Tab("Counter", value: 1) {
        ToolbarStripItemSetCounter(log: log)
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

private struct ToolbarStripItemSetCounter: View {
  let log: ToolbarStripItemSetActionLog
  @State private var count = 0

  var body: some View {
    // Captured by value, so the log names the body that authored the action:
    // only this view re-evaluates on an increment, never the toolbar scope.
    let shownCount = count
    VStack(spacing: 1) {
      Text("count \(count)")
      Button("Increment") {
        count += 1
      }
    }
    .toolbarItem(
      .init(
        title: "Reset counter",
        action: {
          count = 0
          log.record("reset from \(shownCount)")
        }
      )
    )
  }
}

private final class ToolbarStripItemSetRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  /// One stage per presented frame: the budget every harness wait is held to.
  let presentedFrames = ManualStageClock()
  private(set) var lastPresentedSurface: RasterSurface?
  private(set) var lastFrameStripMatchesPage = true
  private(set) var mismatchedFrames: [String] = []
  private let updates: MainActorConditionSignal

  init(size: CellSize, updates: MainActorConditionSignal) {
    surfaceSize = size
    self.updates = updates
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    let frame = surface.lines.joined(separator: "\n")
    // The Counter page contributes "Reset counter"; the Home page does not.
    let showsCounterPage = frame.contains("count ")
    lastFrameStripMatchesPage = frame.contains("Reset counter") == showsCounterPage
    if !lastFrameStripMatchesPage {
      mismatchedFrames.append(frame + "\n")
    }
    presentedFrames.advance()
    let updates = self.updates
    MainActor.assumeIsolated {
      updates.notify()
    }
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}
