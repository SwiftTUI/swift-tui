import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct KeyCommandTests {
  @Test("keyCommand registers at the Panel's scope identity in the CommandRegistry")
  func keyCommandRegistersAtScopeIdentity() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .keyCommand(
        "Save",
        key: .character("s"),
        modifiers: .ctrl,
        action: {}
      )

    var context = ResolveContext(identity: testIdentity("key-command-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    #expect(panelNode != nil)

    let match = panelNode.flatMap { node in
      registry.keyCommand(
        at: node.identity,
        matching: KeyBinding(key: .character("s"), modifiers: .ctrl)
      )
    }
    #expect(match != nil)
    #expect(match?.description == "Save")
    #expect(match?.isEnabled == true)
  }

  @Test("keyCommand with empty modifiers does not register")
  func keyCommandRejectsModifierless() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .keyCommand(
        "Bad",
        key: .character("s"),
        modifiers: [],
        action: {}
      )

    var context = ResolveContext(identity: testIdentity("key-command-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    #expect(panelNode != nil)

    let match = panelNode.flatMap { node in
      registry.keyCommand(
        at: node.identity,
        matching: KeyBinding(key: .character("s"), modifiers: [])
      )
    }
    #expect(match == nil)
  }

  @Test("keyCommand with isEnabled=false still registers but is marked disabled")
  func keyCommandDisabledRegistration() {
    let registry = CommandRegistry()

    let panel = Panel(id: "editor") { EmptyView() }
      .keyCommand(
        "Save (disabled)",
        key: .character("s"),
        modifiers: .ctrl,
        isEnabled: false,
        action: {}
      )

    var context = ResolveContext(identity: testIdentity("key-command-root"))
    context.commandRegistry = registry
    let resolved = Resolver().resolve(AnyView(panel), in: context)

    let panelNode = findPanelNode(in: resolved)
    let match = panelNode.flatMap { node in
      registry.keyCommand(
        at: node.identity,
        matching: KeyBinding(key: .character("s"), modifiers: .ctrl)
      )
    }
    #expect(match != nil)
    #expect(match?.isEnabled == false)
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
@Suite
struct KeyCommandDispatchTests {
  @Test("Ctrl+S on focus inside a Panel fires the Panel's keyCommand")
  func endToEndDispatch() throws {
    let fired = Counter()

    let runLoop = makeRunLoop {
      Panel(id: "editor") {
        Text("inside").focusable(true)
      }
      .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {
        fired.increment()
      }
    }
    try renderInitial(runLoop)

    #expect(runLoop.focusTracker.currentFocusIdentity != nil)

    _ = runLoop.handleKeyPress(KeyPress(.character("s"), modifiers: .ctrl))
    #expect(fired.count == 1)
  }

  @Test("keyCommand does not fire when modifiers don't match")
  func modifierMismatchDoesNotFire() throws {
    let fired = Counter()

    let runLoop = makeRunLoop {
      Panel(id: "editor") {
        Text("inside").focusable(true)
      }
      .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {
        fired.increment()
      }
    }
    try renderInitial(runLoop)

    _ = runLoop.handleKeyPress(KeyPress(.character("s"), modifiers: .alt))
    #expect(fired.count == 0)
  }

  @Test("keyCommand-registered Ctrl+C takes precedence over the default exit")
  func consumerCtrlCOverridesDefaultExit() throws {
    let fired = Counter()

    let runLoop = makeRunLoop {
      Panel(id: "app") {
        Text("inside").focusable(true)
      }
      .keyCommand("Intercept", key: .character("c"), modifiers: .ctrl) {
        fired.increment()
      }
    }
    try renderInitial(runLoop)

    let reason = runLoop.handleKeyPress(KeyPress(.character("c"), modifiers: .ctrl))
    #expect(reason == nil)
    #expect(fired.count == 1)
  }

  @Test("Ancestor Panel's Ctrl+S wins over descendant Panel's Ctrl+S")
  func shallowestWins() throws {
    let ancestorFired = Counter()
    let descendantFired = Counter()

    let runLoop = makeRunLoop {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("leaf").focusable(true)
        }
        .keyCommand("Inner save", key: .character("s"), modifiers: .ctrl) {
          descendantFired.increment()
        }
      }
      .keyCommand("Outer save", key: .character("s"), modifiers: .ctrl) {
        ancestorFired.increment()
      }
    }
    try renderInitial(runLoop)

    _ = runLoop.handleKeyPress(KeyPress(.character("s"), modifiers: .ctrl))
    #expect(ancestorFired.count == 1)
    #expect(descendantFired.count == 0)
  }

  @Test("Disabled ancestor consumes the binding and blocks the descendant")
  func disabledAncestorBlocksDescendant() throws {
    let descendantFired = Counter()

    let runLoop = makeRunLoop {
      Panel(id: "outer") {
        Panel(id: "inner") {
          Text("leaf").focusable(true)
        }
        .keyCommand("Inner save", key: .character("s"), modifiers: .ctrl) {
          descendantFired.increment()
        }
      }
      .keyCommand(
        "Outer save",
        key: .character("s"),
        modifiers: .ctrl,
        isEnabled: false
      ) {}
    }
    try renderInitial(runLoop)

    _ = runLoop.handleKeyPress(KeyPress(.character("s"), modifiers: .ctrl))
    #expect(descendantFired.count == 0)
  }
}

@MainActor
private func makeRunLoop<V: View>(
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = Size(width: 30, height: 8)
  let terminal = KeyCommandTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("KeyCommandRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: terminal,
    terminalInputReader: KeyCommandInputReader(),
    signalReader: KeyCommandSignalReader(),
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

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

@MainActor
final class Counter {
  private(set) var count = 0
  func increment() { count += 1 }
}

private final class KeyCommandTerminalHost: TerminalHosting {
  var surfaceSize: Size { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private let surfaceSizeProvider: () -> Size

  init(
    surfaceSizeProvider: @escaping () -> Size,
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
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0, linesTouched: surface.lines.count, cellsChanged: 0)
  }
}

extension KeyCommandTerminalHost: DamageAwareTerminalHosting {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class KeyCommandInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class KeyCommandSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
