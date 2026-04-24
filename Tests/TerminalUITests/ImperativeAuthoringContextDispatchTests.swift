import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ImperativeAuthoringContextDispatchTests {
  @Test(
    "keyCommand mutates the graph that dispatched it when the same view instance is hosted twice")
  func keyCommandTargetsDispatchingGraph() throws {
    let sharedView = KeyCommandScopeFixture()
    let primary = makeRunLoop(rootName: "SharedKeyCommandPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedKeyCommandSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.character("m"), modifiers: .ctrl))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "paletteCommand action mutates the graph that exposed it when the same view instance is hosted twice"
  )
  func paletteCommandTargetsDispatchingGraph() throws {
    let sharedView = PaletteCommandScopeFixture()
    let primary = makeRunLoop(rootName: "SharedPalettePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedPaletteSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    let command = try #require(
      primary.runLoop.commandRegistry.paletteCommands(
        along: primary.runLoop.currentFocusScopePath()
      ).first
    )
    command.action()
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "toolbarItem button mutates the graph that activated it when the same view instance is hosted twice"
  )
  func toolbarItemTargetsDispatchingGraph() throws {
    let sharedView = ToolbarScopeFixture()
    let primary = makeRunLoop(rootName: "SharedToolbarPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedToolbarSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    _ = primary.runLoop.handleKeyPress(KeyPress(.space, modifiers: []))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "dropDestination mutates the graph that handled the paste when the same view instance is hosted twice"
  )
  func dropDestinationTargetsDispatchingGraph() throws {
    let sharedView = DropDestinationScopeFixture()
    let primary = makeRunLoop(rootName: "SharedDropPrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedDropSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)
    focusLeafmostFocusable(in: primary.runLoop)

    primary.runLoop.handlePaste(PasteEvent(content: "/tmp/file.txt"))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("mutated"))
    #expect(surfaceText(secondary.host).contains("idle"))
  }

  @Test(
    "gesture callbacks mutate only the graph that received the drag when the same view instance is hosted twice"
  )
  func gestureCallbacksTargetDispatchingGraph() throws {
    let sharedView = GestureCallbackScopeFixture()
    let primary = makeRunLoop(rootName: "SharedGesturePrimary") { sharedView }
    let secondary = makeRunLoop(rootName: "SharedGestureSecondary") { sharedView }

    try renderInitial(primary.runLoop)
    try renderInitial(secondary.runLoop)

    let region = try #require(primary.runLoop.latestSemanticSnapshot.interactionRegions.first)
    let start = centerPoint(of: region.rect)
    let dragged = Point(x: start.x + 4, y: start.y + 1)

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: start))))
    try renderPending(primary.runLoop)

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .dragged(.primary), location: dragged))))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("changed"))
    #expect(surfaceText(primary.host).contains("offset:4,1"))
    #expect(surfaceText(secondary.host).contains("idle"))
    #expect(surfaceText(secondary.host).contains("offset:0,0"))

    _ = primary.runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: dragged))))
    try renderPending(primary.runLoop)
    try renderPending(secondary.runLoop)

    #expect(surfaceText(primary.host).contains("ended"))
    #expect(surfaceText(primary.host).contains("offset:0,0"))
    #expect(surfaceText(primary.host).contains("commits:1"))
    #expect(surfaceText(secondary.host).contains("idle"))
    #expect(surfaceText(secondary.host).contains("commits:0"))
  }
}

@MainActor
private struct KeyCommandScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .keyCommand("Mutate", key: .character("m"), modifiers: .ctrl) {
      value = "mutated"
    }
  }
}

@MainActor
private struct PaletteCommandScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .paletteCommand(name: "Mutate") {
      value = "mutated"
    }
  }
}

@MainActor
private struct ToolbarScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value)
        .toolbarItem(
          .init(
            title: "Mutate",
            action: { value = "mutated" }
          )
        )
    }
    .toolbar(style: DefaultBottomToolbarStyle())
  }
}

@MainActor
private struct DropDestinationScopeFixture: View {
  @State private var value = "idle"

  var body: some View {
    Panel(id: "scope") {
      Text(value).focusable(true)
    }
    .dropDestination { _ in
      value = "mutated"
      return true
    }
  }
}

@MainActor
private struct GestureCallbackScopeFixture: View {
  @State private var status = "idle"
  @State private var commits = 0
  @GestureState private var dragOffset = Size.zero

  var body: some View {
    Text("status:\(status)|offset:\(dragOffset.width),\(dragOffset.height)|commits:\(commits)")
      .frame(minWidth: 48, maxWidth: 48, minHeight: 1, maxHeight: 1)
      .gesture(
        DragGesture()
          .updating($dragOffset) { value, state, _ in
            state = value.translation
          }
          .onChanged { _ in
            status = "changed"
          }
          .onEnded { _ in
            status = "ended"
            commits += 1
          }
      )
  }
}

@MainActor
private func makeRunLoop<V: View>(
  rootName: String,
  @ViewBuilder content: @escaping () -> V
) -> (runLoop: RunLoop<Int, V>, host: ImperativeScopeTerminalHost) {
  let terminalSize = Size(width: 60, height: 8)
  let host = ImperativeScopeTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity(rootName)
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = host.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: host,
    terminalInputReader: ImperativeScopeInputReader(),
    signalReader: ImperativeScopeSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return (runLoop, host)
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

@MainActor
private func renderPending<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func focusLeafmostFocusable<State, V: View>(
  in runLoop: RunLoop<State, V>
) {
  if let actionable = runLoop.latestSemanticSnapshot.focusRegions
    .filter({ runLoop.localActionRegistry.hasHandler(identity: $0.identity) })
    .max(by: { $0.scopePath.count < $1.scopePath.count })
  {
    _ = runLoop.focusTracker.setFocus(to: actionable.identity)
    return
  }
  guard
    let leafmost = runLoop.latestSemanticSnapshot.focusRegions
      .max(by: { $0.scopePath.count < $1.scopePath.count })
  else { return }
  _ = runLoop.focusTracker.setFocus(to: leafmost.identity)
}

private func centerPoint(of rect: Rect) -> Point {
  Point(
    x: rect.origin.x + rect.size.width / 2,
    y: rect.origin.y + rect.size.height / 2
  )
}

@MainActor
private func surfaceText(_ host: ImperativeScopeTerminalHost) -> String {
  host.latestSurface?.lines.joined(separator: "\n") ?? ""
}

private final class ImperativeScopeTerminalHost: TerminalHosting {
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
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

extension ImperativeScopeTerminalHost: DamageAwareTerminalHosting {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class ImperativeScopeInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class ImperativeScopeSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
