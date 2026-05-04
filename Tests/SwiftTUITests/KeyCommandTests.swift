import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

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

  @Test("keyCommand root invalidation redraws imperative route changes")
  func keyCommandRootInvalidationRedrawsImperativeRouteChanges() throws {
    let model = KeyCommandRouterModel()
    let runLoop = makeRunLoop {
      KeyCommandRouterFixture(model: model)
    }
    try renderInitial(runLoop)

    #expect(latestSurfaceText(for: runLoop).contains("detail"))

    _ = runLoop.handle(.input(.key(.character("b"), modifiers: .ctrl)))
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(renderedFrames > 0)
    #expect(surfaceText.contains("picker"))
    #expect(!surfaceText.contains("detail"))
  }

  @Test("keyCommand fires after list activation routes into a new Panel")
  func keyCommandDispatchesAfterListActivationRouteChange() throws {
    let runLoop = makeRunLoop {
      KeyCommandListRouteFixture()
    }
    try renderInitial(runLoop)

    let rowIdentity = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.map(\.identity).first {
        $0.description.contains("ListRow[0]")
      })
    #expect(runLoop.focusTracker.setFocus(to: rowIdentity))

    _ = runLoop.handle(.input(.key(.return)))
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(latestSurfaceText(for: runLoop).contains("detail"))

    _ = runLoop.handle(.input(.key(.character("b"), modifiers: .ctrl)))
    renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Open"))
    #expect(!surfaceText.contains("detail"))
  }

  @Test("keyCommand fires after route change to a Panel with no focusable child")
  func keyCommandDispatchesAfterRouteChangeToBarePanel() throws {
    let runLoop = makeRunLoop {
      KeyCommandListRouteFixture(detailHasFocusableChild: false)
    }
    try renderInitial(runLoop)

    let rowIdentity = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.map(\.identity).first {
        $0.description.contains("ListRow[0]")
      })
    #expect(runLoop.focusTracker.setFocus(to: rowIdentity))

    _ = runLoop.handle(.input(.key(.return)))
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(latestSurfaceText(for: runLoop).contains("detail"))
    #expect(!runLoop.currentFocusScopePath().isEmpty)

    _ = runLoop.handle(.input(.key(.character("b"), modifiers: .ctrl)))
    renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Open"))
    #expect(!surfaceText.contains("detail"))
  }

  @Test("keyCommand fires after mouse list activation routes into a new Panel")
  func keyCommandDispatchesAfterMouseListActivationRouteChange() throws {
    let runLoop = makeRunLoop {
      KeyCommandListRouteFixture()
    }
    try renderInitial(runLoop)

    let rowIdentity = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.map(\.identity).first {
        $0.description.contains("ListRow[0]")
      })
    let rowRegion = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first { $0.identity == rowIdentity })
    let rowCenter = CellPoint(
      x: rowRegion.rect.origin.x + rowRegion.rect.size.width / 2,
      y: rowRegion.rect.origin.y + rowRegion.rect.size.height / 2
    )

    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: Point(rowCenter)))))
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: Point(rowCenter)))))
    renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(latestSurfaceText(for: runLoop).contains("detail"))

    _ = runLoop.handle(.input(.key(.character("b"), modifiers: .ctrl)))
    renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Open"))
    #expect(!surfaceText.contains("detail"))
  }

  @Test("keyCommand fires after batched mouse click routes into a new Panel")
  func keyCommandDispatchesAfterBatchedMouseListActivationRouteChange() throws {
    let runLoop = makeRunLoop {
      KeyCommandListRouteFixture()
    }
    try renderInitial(runLoop)

    let rowIdentity = try #require(
      runLoop.latestSemanticSnapshot.focusRegions.map(\.identity).first {
        $0.description.contains("ListRow[0]")
      })
    let rowRegion = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first { $0.identity == rowIdentity })
    let rowCenter = CellPoint(
      x: rowRegion.rect.origin.x + rowRegion.rect.size.width / 2,
      y: rowRegion.rect.origin.y + rowRegion.rect.size.height / 2
    )

    _ = runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: Point(rowCenter)))))
    _ = runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: Point(rowCenter)))))
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(latestSurfaceText(for: runLoop).contains("detail"))
    #expect(!runLoop.currentFocusScopePath().isEmpty)
    let backBinding = KeyBinding(key: .character("b"), modifiers: .ctrl)
    #expect(
      runLoop.currentFocusScopePath().contains {
        runLoop.commandRegistry.keyCommand(at: $0, matching: backBinding) != nil
      }
    )

    _ = runLoop.handle(.input(.key(.character("b"), modifiers: .ctrl)))
    renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Open"))
    #expect(!surfaceText.contains("detail"))
  }
}

@MainActor
private func makeRunLoop<V: View>(
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminalSize = CellSize(width: 30, height: 8)
  let terminal = KeyCommandTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("KeyCommandRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
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
private func latestSurfaceText<State, V: View>(
  for runLoop: RunLoop<State, V>
) -> String {
  guard let terminal = runLoop.presentationSurface as? KeyCommandTerminalHost,
    let surface = terminal.latestSurface
  else {
    return ""
  }
  return surface.lines.joined(separator: "\n")
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

@MainActor
private final class KeyCommandRouterModel {
  var showingDetail = true
}

private struct KeyCommandRouterFixture: View {
  let model: KeyCommandRouterModel

  var body: some View {
    if model.showingDetail {
      Panel(id: "detail") {
        VStack(alignment: .leading, spacing: 0) {
          Text("detail").focusable(true)
          Text("detail stale row")
          Text("detail stale footer")
        }
      }
      .keyCommand("Back", key: .character("b"), modifiers: .ctrl) {
        model.showingDetail = false
      }
    } else {
      Panel(id: "picker") {
        Text("picker").focusable(true)
      }
    }
  }
}

private struct KeyCommandListRouteFixture: View {
  @State private var showingDetail = false
  @State private var selection: Int?

  var detailHasFocusableChild = true

  var body: some View {
    if showingDetail {
      Panel(id: "detail") {
        if detailHasFocusableChild {
          Text("detail").focusable(true)
        } else {
          Text("detail")
        }
      }
      .keyCommand("Back", key: .character("b"), modifiers: .ctrl) {
        showingDetail = false
      }
    } else {
      Panel(id: "picker") {
        List(selection: $selection, onActivate: { _ in showingDetail = true }) {
          Text("Open").tag(0)
        }
      }
    }
  }
}

private final class KeyCommandTerminalHost: PresentationSurface {
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

extension KeyCommandTerminalHost: DamageAwarePresentationSurface {
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
