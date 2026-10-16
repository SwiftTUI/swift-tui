import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct DefaultPaletteViewportTests {
  @Test("native palette keeps every keyboard selection visible", arguments: [8, 12, 30])
  func selectionStaysVisible(height: Int) throws {
    let probe = PaletteViewportProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteViewport", String(height)),
      size: CellSize(width: 72, height: height)
    ) { PaletteViewportFixture(probe: probe) }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("> Command 00"))
    for index in 1..<20 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      #expect(harness.frame.contains("> \(commandName(index))"), "\(harness.frame)")
    }
    for index in (0..<19).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      #expect(harness.frame.contains("> \(commandName(index))"), "\(harness.frame)")
    }
    _ = try harness.pressKey(KeyPress(.tab))
    _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
    #expect(harness.frame.contains("> Command 00"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(probe.activated == [0])
    #expect(!harness.frame.contains("Command "))
  }

  @Test("native palette shows and invokes a command beyond a short viewport")
  func activatesVisibleSelection() throws {
    let probe = PaletteViewportProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteViewportActivation"),
      size: CellSize(width: 72, height: 12)
    ) { PaletteViewportFixture(probe: probe) }
    defer { harness.shutdown() }
    for _ in 0..<8 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    #expect(harness.frame.contains("> Command 08"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(probe.activated == [8])
    #expect(!harness.frame.contains("Command "))
  }

  @Test("an open native palette preserves selection and filtering across host resize")
  func liveResize() throws {
    let probe = PaletteViewportProbe()
    let host = PaletteViewportSurface()
    let identity = testIdentity("PaletteViewportResize")
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: host,
      terminalInputReader: PaletteViewportInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity])
    ) { _, _ in PaletteViewportFixture(probe: probe) }
    defer { loop.lifecycleCoordinator.shutdown() }
    var rendered = 0
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try loop.renderPendingFrames(renderedFrames: &rendered)
    loop.renderer.enableSelectiveEvaluation()
    for _ in 0..<8 {
      #expect(loop.handleKeyPress(KeyPress(.arrowDown)) == nil)
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    #expect(host.frame.contains("> Command 08"))
    for height in [12, 30, 12] {
      host.size = CellSize(width: 72, height: height)
      loop.scheduler.requestSignal(named: "SIGWINCH")
      try loop.renderPendingFrames(renderedFrames: &rendered)
      #expect(host.frame.contains("> Command 08"), "height \(height):\n\(host.frame)")
    }
    loop.handlePaste(PasteEvent(content: "Command 1"))
    try loop.renderPendingFrames(renderedFrames: &rendered)
    #expect(host.frame.contains("> Command 10"), "\(host.frame)")
    for _ in 0..<9 {
      #expect(loop.handleKeyPress(KeyPress(.arrowDown)) == nil)
      try loop.renderPendingFrames(renderedFrames: &rendered)
    }
    #expect(host.frame.contains("> Command 19"), "\(host.frame)")
    host.size = CellSize(width: 72, height: 30)
    loop.scheduler.requestSignal(named: "SIGWINCH")
    try loop.renderPendingFrames(renderedFrames: &rendered)
    #expect(host.frame.contains("Command 1"))
    #expect(!host.frame.contains("Command 00"))
    #expect(host.frame.contains("> Command 19"))
    #expect(loop.handleKeyPress(KeyPress(.return)) == nil)
    try loop.renderPendingFrames(renderedFrames: &rendered)
    #expect(probe.activated == [19])
    #expect(!host.frame.contains("Command "))
  }
}

private func commandName(_ index: Int) -> String {
  "Command " + String(("00" + String(index)).suffix(2))
}

@MainActor
private final class PaletteViewportProbe {
  var activated: [Int] = []
}

@MainActor
private struct PaletteViewportFixture: View {
  let probe: PaletteViewportProbe
  @State private var isPresented = true

  var body: some View {
    Panel(id: "commands") {
      ForEach(0..<20, id: \.self) { index in
        Panel(id: index) { EmptyView() }
          .paletteCommand(name: commandName(index), action: { probe.activated.append(index) })
      }
    }
    .paletteSheet("Commands", isPresented: $isPresented)
  }
}

private final class PaletteViewportSurface: PresentationSurface {
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

private final class PaletteViewportInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}
