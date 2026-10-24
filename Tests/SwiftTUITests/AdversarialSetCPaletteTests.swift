@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCPaletteTests {
  @Test(arguments: [9, 10, 11])
  func setC130ShortTerminalsShowHeightMinusEightRows(height: Int) throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC130", "\(height)"),
      size: .init(width: 72, height: height)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    #expect(SetCPalette.visibleCommands(h.frame).count == height - 8, "\(h.frame)")
    #expect(h.frame.contains("> Command 00"), "\(h.frame)")
  }

  @Test func setC131ShrinkKeepsLastVisibleSelection() throws {
    let probe = SetCPaletteProbe()
    let host = SetCPaletteSurface()
    host.size = CellSize(width: 72, height: 14)
    let loop = try SetCPalette.loop(probe: probe, host: host, name: "setC131")
    defer { loop.lifecycleCoordinator.shutdown() }
    for _ in 0..<5 { try SetCPalette.press(KeyPress(.arrowDown), loop) }
    try #require(host.frame.contains("> Command 05"), "\(host.frame)")
    try #require(SetCPalette.visibleCommands(host.frame) == Array(0...5), "\(host.frame)")
    host.size = CellSize(width: 72, height: 10)
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try SetCPalette.drain(loop)
    #expect(host.frame.contains("> Command 05"), "\(host.frame)")
    #expect(SetCPalette.visibleCommands(host.frame).count == 2, "\(host.frame)")
  }

  @Test func setC132DisabledRowsSkippedAndNotPerformed() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC132"),
      size: .init(width: 72, height: 30)
    ) { SetCPaletteFixture(probe: probe, disabled: [1, 2]) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.arrowDown))
    #expect(h.frame.contains("> Command 03"), "\(h.frame)")
    // Only disabled matches remain: the fallback selection is disabled and inert.
    _ = try h.paste("Command 01")
    try #require(SetCPalette.visibleCommands(h.frame) == [1], "\(h.frame)")
    _ = try h.pressKey(.init(.return))
    #expect(probe.activated.isEmpty)
    #expect(h.frame.contains("Command 01"), "palette stays open: \(h.frame)")
  }

  @Test func setC133FuzzyRankingPrefersTighterMatch() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC133"),
      size: .init(width: 72, height: 30)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    _ = try h.paste("Command 1")
    let visible = SetCPalette.visibleOrder(h.frame)
    #expect(visible.first == 10, "\(visible): \(h.frame)")
    #expect(visible.last == 1, "\(visible)")
    #expect(h.frame.contains("> Command 10"), "\(h.frame)")
  }

  @Test func setC134ClickOnVisibleRowPerformsThatCommand() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC134"),
      size: .init(width: 72, height: 30)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    try #require(h.frame.contains("> Command 00"))
    _ = try h.clickText("Command 03")
    #expect(probe.activated == [3])
    #expect(!h.frame.contains("Command 0"), "\(h.frame)")
  }

  @Test func setC135ClickInScrolledWindowMapsToRow() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC135"),
      size: .init(width: 72, height: 12)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    for _ in 0..<7 { _ = try h.pressKey(.init(.arrowDown)) }
    try #require(SetCPalette.visibleCommands(h.frame) == Array(4...7), "\(h.frame)")
    _ = try h.clickText("Command 05")
    #expect(probe.activated == [5])
  }

  @Test func setC136ReversalKeepsWindow() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC136"),
      size: .init(width: 72, height: 12)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    for _ in 0..<6 { _ = try h.pressKey(.init(.arrowDown)) }
    try #require(SetCPalette.visibleCommands(h.frame) == Array(3...6), "\(h.frame)")
    for _ in 0..<2 { _ = try h.pressKey(.init(.arrowUp)) }
    #expect(SetCPalette.visibleCommands(h.frame) == Array(3...6), "\(h.frame)")
    #expect(h.frame.contains("> Command 04"), "\(h.frame)")
  }

  @Test func setC137RemovedSelectedCommandFallsBackToFirst() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC137"),
      size: .init(width: 72, height: 30)
    ) { SetCPaletteFixture(probe: probe) }
    defer { h.shutdown() }
    for _ in 0..<5 { _ = try h.pressKey(.init(.arrowDown)) }
    try #require(h.frame.contains("> Command 05"), "\(h.frame)")
    probe.removed = [5]
    _ = try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("Command 05"), "\(h.frame)")
    #expect(h.frame.contains("> Command 00"), "\(h.frame)")
    _ = try h.pressKey(.init(.return))
    #expect(probe.activated == [0])
  }

  @Test func setC138NoWrapAtEnds() throws {
    let probe = SetCPaletteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC138"),
      size: .init(width: 72, height: 30)
    ) { SetCPaletteFixture(probe: probe, commandCount: 6) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.arrowUp))
    #expect(h.frame.contains("> Command 00"), "\(h.frame)")
    for _ in 0..<8 { _ = try h.pressKey(.init(.arrowDown)) }
    #expect(h.frame.contains("> Command 05"), "\(h.frame)")
    _ = try h.pressKey(.init(.return))
    #expect(probe.activated == [5])
  }
}

private func setCCommandName(_ index: Int) -> String {
  "Command " + String(("00" + String(index)).suffix(2))
}

@MainActor
private final class SetCPaletteProbe {
  var activated: [Int] = []
  var removed: Set<Int> = []
}

@MainActor
private struct SetCPaletteFixture: View {
  let probe: SetCPaletteProbe
  var disabled: Set<Int> = []
  var commandCount = 20
  @State private var isPresented = true

  var body: some View {
    Panel(id: "commands") {
      ForEach((0..<commandCount).filter { !probe.removed.contains($0) }, id: \.self) { index in
        Panel(id: index) { EmptyView() }
          .paletteCommand(
            name: setCCommandName(index), isEnabled: !disabled.contains(index),
            action: { probe.activated.append(index) })
      }
    }
    .paletteSheet("Commands", isPresented: $isPresented)
  }
}

private final class SetCPaletteSurface: PresentationSurface {
  var size = CellSize(width: 72, height: 30)
  var surfaceSize: CellSize { size }
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frame = ""

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ output: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to point: CellPoint) throws {}

  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frame = surface.lines.joined(separator: "\n")
    return TerminalPresentationMetrics(
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height, strategy: .fullRepaint)
  }
}

private final class SetCPaletteInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

@MainActor
private enum SetCPalette {
  static func visibleCommands(_ frame: String) -> [Int] {
    (0..<20).filter { frame.contains(setCCommandName($0)) }
  }

  /// Visible command rows in display order (top to bottom).
  static func visibleOrder(_ frame: String) -> [Int] {
    frame.split(separator: "\n").flatMap { row in
      (0..<20).filter { row.contains(setCCommandName($0)) }
    }
  }

  static func loop(probe: SetCPaletteProbe, host: SetCPaletteSurface, name: String) throws
    -> SwiftTUIRuntime.RunLoop<Int, SetCPaletteFixture>
  {
    let identity = testIdentity(name)
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: host,
      terminalInputReader: SetCPaletteInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity])
    ) { _, _ in SetCPaletteFixture(probe: probe) }
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try drain(loop)
    loop.renderer.enableSelectiveEvaluation()
    return loop
  }

  static func press(_ key: KeyPress, _ loop: SwiftTUIRuntime.RunLoop<Int, SetCPaletteFixture>)
    throws
  {
    #expect(loop.handleKeyPress(key) == nil)
    try drain(loop)
  }

  static func drain(_ loop: SwiftTUIRuntime.RunLoop<Int, SetCPaletteFixture>) throws {
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
  }
}
