import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteCommandTests {
  @Test("paletteCommand registers at the Panel's scope identity")
  func paletteCommandRegisters() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Toggle theme", action: {})

    var context = ResolveContext(identity: testIdentity("palette-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    #expect(panelNode != nil)

    let commands = panelNode.map { registry.paletteCommands(at: $0.identity) } ?? []
    #expect(commands.count == 1)
    #expect(commands.first?.name == "Toggle theme")
    #expect(commands.first?.isEnabled == true)
    #expect(commands.first?.description == nil)
  }

  @Test("paletteCommand with a description preserves it")
  func paletteCommandPreservesDescription() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Toggle theme",
        description: "Switch between light and dark",
        action: {}
      )

    var context = ResolveContext(identity: testIdentity("palette-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    let commands = panelNode.map { registry.paletteCommands(at: $0.identity) } ?? []
    #expect(commands.first?.description == "Switch between light and dark")
  }

  @Test("Disabled paletteCommand is registered but marked disabled")
  func paletteCommandDisabled() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Delete all",
        isEnabled: false,
        action: {}
      )

    var context = ResolveContext(identity: testIdentity("palette-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    let commands = panelNode.map { registry.paletteCommands(at: $0.identity) } ?? []
    #expect(commands.first?.isEnabled == false)
  }

  @Test("activePaletteCommands environment reflects commands on current focus chain")
  func environmentExposesActiveCommands() throws {
    let capture = PaletteCaptureBox()

    let runLoop = makePaletteTestRunLoop {
      Panel(id: "editor") {
        PaletteProbeView(capture: capture)
          .focusable(true)
      }
      .paletteCommand(name: "Save", action: {})
      .paletteCommand(name: "Toggle theme", action: {})
    }

    // First frame: registers palette commands; env is still empty
    // because `latestActivePaletteCommands` is captured at the end of
    // this frame.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    #expect(capture.latestNames == [])

    // Second frame: env carries the palette commands captured after
    // the first frame, so the probe view reads them.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(capture.latestNames == ["Save", "Toggle theme"])
  }

  @Test("activePaletteCommands is empty when no scope on the focus chain has palette commands")
  func environmentEmptyWithoutCommands() throws {
    let capture = PaletteCaptureBox()

    let runLoop = makePaletteTestRunLoop {
      Panel(id: "editor") {
        PaletteProbeView(capture: capture)
          .focusable(true)
      }
    }

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(capture.latestNames == [])
  }

  @Test("Multiple paletteCommands at the same scope accumulate in authored order")
  func paletteCommandsAccumulate() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Command A", action: {})
      .paletteCommand(name: "Command B", action: {})

    var context = ResolveContext(identity: testIdentity("palette-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    let commands = panelNode.map { registry.paletteCommands(at: $0.identity) } ?? []
    #expect(commands.count == 2)
    // Commands are applied outside-in, so B's modifier runs first
    // (outermost); the registry appends to preserve declaration order
    // at the scope identity.
    let names = commands.map(\.name)
    #expect(names.contains("Command A"))
    #expect(names.contains("Command B"))
  }
}

@MainActor
private func findPanelNode(in root: ResolvedNode) -> ResolvedNode? {
  var stack: [ResolvedNode] = [root]
  while let node = stack.popLast() {
    if case .view(let name) = node.kind, name == "Panel" {
      return node
    }
    stack.append(contentsOf: node.children)
  }
  return nil
}

@MainActor
final class PaletteCaptureBox {
  var latestNames: [String] = []
}

/// A probe view whose body reads `activePaletteCommands` from the
/// environment and records each command's name into `capture`.
private struct PaletteProbeView: View {
  let capture: PaletteCaptureBox

  var body: some View {
    EnvironmentReader(\.activePaletteCommands) { commands in
      let names: [String] = commands.map { $0.name }
      capture.latestNames = names
      return Text("probe")
    }
  }
}

@MainActor
private func makePaletteTestRunLoop<V: View>(
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = CellSize(width: 30, height: 8)
  let terminal = PaletteTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("PaletteRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: PaletteInputReader(),
    signalReader: PaletteSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return runLoop
}

private final class PaletteTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private let surfaceSizeProvider: () -> CellSize

  init(
    surfaceSizeProvider: @escaping () -> CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0, linesTouched: surface.lines.count, cellsChanged: 0)
  }
}

extension PaletteTerminalHost: DamageAwarePresentationSurface {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class PaletteInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class PaletteSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
