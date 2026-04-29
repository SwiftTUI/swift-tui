import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Reproduces the exact modifier shape used by the gallery demo's
/// `GalleryView` (EnvironmentReader → TabView → .toolbarItem → .panel →
/// stacked .keyCommand → .paletteCommand → .toolbar → .sheet) to verify
/// that ⌃1 and similar bindings actually reach `commandRegistry` and
/// fire when the tab content holds focus.
@MainActor
@Suite
struct GalleryStyleDispatchTests {
  @Test("Panel-anchored keyCommand dispatches while focus is inside a TabView descendant")
  func galleryKeyCommandDispatchesIntoTabbedContent() throws {
    let fired = Counter()

    let runLoop = makeRunLoopLocal {
      EnvironmentReader(\.activePaletteCommands) { _ in
        TabView(selection: .constant(0)) {
          Text("inside").focusable(true).tag(0)
          Text("other").focusable(true).tag(1)
        }
        .tabViewStyle(.literalTabs)
        .toolbarItem(
          .init(
            title: "Palette",
            action: {}
          )
        )
        .panel(id: "gallery")
        .keyCommand(
          "Switch to Counter",
          key: .character("1"),
          modifiers: .ctrl,
          action: { fired.increment() }
        )
        .toolbar(style: DefaultBottomToolbarStyle())
      }
    }
    try renderInitial(runLoop)

    #expect(runLoop.focusTracker.currentFocusIdentity != nil)

    _ = runLoop.handleKeyPress(KeyPress(.character("1"), modifiers: .ctrl))
    #expect(fired.count == 1)
  }

  @Test("Gallery-shaped chain with 7 keyCommands and paletteCommands all dispatch correctly")
  func galleryStyleMultipleCommandsDispatch() throws {
    let fired1 = Counter()
    let fired2 = Counter()
    let fired3 = Counter()

    let runLoop = makeRunLoopLocal {
      EnvironmentReader(\.activePaletteCommands) { _ in
        TabView(selection: .constant(0)) {
          Text("a").focusable(true).tag(0)
          Text("b").focusable(true).tag(1)
          Text("c").focusable(true).tag(2)
        }
        .tabViewStyle(.literalTabs)
        .toolbarItem(.init(title: "P", action: {}))
        .panel(id: "gallery")
        .keyCommand("one", key: .character("1"), modifiers: .ctrl) { fired1.increment() }
        .keyCommand("two", key: .character("2"), modifiers: .ctrl) { fired2.increment() }
        .keyCommand("three", key: .character("3"), modifiers: .ctrl) { fired3.increment() }
        .paletteCommand(name: "one", action: {})
        .paletteCommand(name: "two", action: {})
        .paletteCommand(name: "three", action: {})
        .toolbar(style: DefaultBottomToolbarStyle())
      }
    }
    try renderInitial(runLoop)

    _ = runLoop.handleKeyPress(KeyPress(.character("1"), modifiers: .ctrl))
    _ = runLoop.handleKeyPress(KeyPress(.character("2"), modifiers: .ctrl))
    _ = runLoop.handleKeyPress(KeyPress(.character("3"), modifiers: .ctrl))

    #expect(fired1.count == 1)
    #expect(fired2.count == 1)
    #expect(fired3.count == 1)
  }

  @Test("Palette command action mutates @State owned by an outer View")
  func paletteCommandActionMutatesState() throws {
    let runLoop = makeRunLoopLocal {
      GalleryStyleOuter()
    }
    try renderInitial(runLoop)

    // After two renders, activePaletteCommands env should have entries.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // Read the captured palette command and fire its action.
    let captured = GalleryStyleOuter.capturedCommands.value
    #expect(captured.count >= 1, "expected at least one palette command, got \(captured.count)")
    guard let first = captured.first(where: { $0.name == "Switch" }) else {
      Issue.record("palette command 'Switch' not present in snapshot: \(captured.map(\.name))")
      return
    }
    first.action()
    #expect(GalleryStyleOuter.selectionSink.value == 1)
  }

  @Test("Palette commands do not duplicate across partial-invalidation re-resolves")
  func paletteCommandsDoNotAccumulate() throws {
    let runLoop = makeRunLoopLocal {
      PaletteDupProbeRoot()
    }
    try renderInitial(runLoop)

    // Force many state-driven re-resolves. Partial invalidations
    // previously skipped CommandRegistry cleanup — the removeSubtrees
    // call on RuntimeRegistrationSet did not recurse into commandRegistry
    // — so palette command lists could grow unboundedly across frames.
    for _ in 0..<10 {
      PaletteDupProbeRoot.tickSource.update { $0 += 1 }
      runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }

    let counts = runLoop.commandRegistry.paletteCommandCountsByScope()
    #expect(counts.count == 1)
    #expect(counts.values.first == 3, "expected 3 palette commands per scope, got \(counts)")
  }

  @Test("Alt+digit keyCommand fires via the input path")
  func altDigitDispatches() throws {
    let fired = Counter()

    let runLoop = makeRunLoopLocal {
      TabView(selection: .constant(0)) {
        Text("x").focusable(true).tag(0)
      }
      .tabViewStyle(.literalTabs)
      .panel(id: "gallery")
      .keyCommand(
        "Switch to tab 1",
        key: .character("1"),
        modifiers: .alt,
        action: { fired.increment() }
      )
    }
    try renderInitial(runLoop)

    _ = runLoop.handleKeyPress(KeyPress(.character("1"), modifiers: .alt))
    #expect(fired.count == 1)
  }

  @Test(
    "Gallery-exact flow: ⌃K keyCommand snapshots non-empty activePaletteCommands via the env closure capture"
  )
  func galleryExactFlowKeyCommandSnapshotsNonEmptyCommands() throws {
    GallerySimulator.reset()

    let runLoop = makeRunLoopLocal {
      GallerySimulator()
    }
    try renderInitial(runLoop)

    // Drive additional frames so env propagation has time to deliver
    // palette commands to the reader's closure capture.
    for _ in 0..<3 {
      runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    // Simulate the user pressing ⌃K.
    _ = runLoop.handleKeyPress(KeyPress(.character("k"), modifiers: .ctrl))

    // After firing, one more render to settle state.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var rendered = 0
    try runLoop.renderPendingFrames(renderedFrames: &rendered)

    let snapshot = GallerySimulator.snapshotAtKeyPress.value
    #expect(
      snapshot.count == 3,
      "Expected keyCommand action to have captured 3 palette commands at the moment ⌃K fired; got \(snapshot.count)"
    )
  }

  @Test("Gallery-exact flow: ⌃K presents the palette on the next runtime input frame")
  func galleryExactFlowPresentsPaletteImmediatelyAfterRuntimeInput() throws {
    GallerySimulator.reset()

    let runLoop = makeRunLoopLocal(
      terminalSize: .init(width: 60, height: 16)
    ) {
      GallerySimulator()
    }
    try renderInitial(runLoop)
    try settleGalleryPaletteEnvironment(runLoop)

    let reason = runLoop.handle(
      .input(.key(.character("k"), modifiers: .ctrl))
    )
    #expect(reason == nil)

    var rendered = 0
    try runLoop.renderPendingFrames(renderedFrames: &rendered)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Command palette"))
    #expect(surfaceText.contains("palette sheet"))
  }

  @Test("Wrapper-hosted gallery palette still presents immediately after ⌃K")
  func wrapperHostedGalleryPresentsPaletteImmediatelyAfterRuntimeInput() throws {
    GallerySimulator.reset()

    let runLoop = makeRunLoopLocal(
      terminalSize: .init(width: 60, height: 16)
    ) {
      WrappedGallerySimulator()
    }
    try renderInitial(runLoop)
    try settleGalleryPaletteEnvironment(runLoop)

    let reason = runLoop.handle(
      .input(.key(.character("k"), modifiers: .ctrl))
    )
    #expect(reason == nil)

    var rendered = 0
    try runLoop.renderPendingFrames(renderedFrames: &rendered)

    let snapshot = GallerySimulator.snapshotAtKeyPress.value
    #expect(snapshot.count == 3)

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Command palette"))
    #expect(surfaceText.contains("palette sheet"))
  }

  @Test(
    "activePaletteCommands captured via env reader reflects Panel commands when a .toolbar wraps the Panel"
  )
  func toolbarWrappedPanelSurfacesActivePaletteCommandsViaEnv() throws {
    let capturedCounts = LockedBoxLocal<[Int]>(initial: [])

    let runLoop = makeRunLoopLocal {
      EnvironmentReader(\.activePaletteCommands) { commands in
        capturedCounts.append(commands.count)
        return
          TabView(selection: .constant(0)) {
            Text("body").focusable(true).tag(0)
          }
          .tabViewStyle(.literalTabs)
          .toolbarItem(.init(title: "Palette", action: {}))
          .panel(id: "gallery")
          .paletteCommand(name: "A", action: {})
          .paletteCommand(name: "B", action: {})
          .paletteCommand(name: "C", action: {})
          .toolbar(style: DefaultBottomToolbarStyle())
      }
    }
    try renderInitial(runLoop)

    // Drive a few more frames so any pending focus/env updates settle.
    for _ in 0..<3 {
      runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
      var rendered = 0
      try runLoop.renderPendingFrames(renderedFrames: &rendered)
    }

    let seen = capturedCounts.value
    // This is the EXACT failure mode the user reports: with a toolbar
    // wrapping the Panel, the env reader never sees the palette
    // commands, so the gallery's snapshot-capture path hands [] into
    // the sheet.
    #expect(
      seen.contains(3),
      "Expected to observe 3 palette commands at some render, got: \(seen)"
    )
  }

  @Test("activePaletteCommands arrives via environment after a render cycle")
  func activePaletteCommandsFlowsIntoEnvironment() throws {
    let capturedCounts = LockedBoxLocal<[Int]>(initial: [])

    let runLoop = makeRunLoopLocal {
      EnvironmentReader(\.activePaletteCommands) { commands in
        // Capture every time the reader re-resolves.
        capturedCounts.append(commands.count)
        return
          TabView(selection: .constant(0)) {
            Text("inside").focusable(true).tag(0)
          }
          .tabViewStyle(.literalTabs)
          .panel(id: "gallery")
          .paletteCommand(name: "A", action: {})
          .paletteCommand(name: "B", action: {})
          .paletteCommand(name: "C", action: {})
      }
    }
    try renderInitial(runLoop)

    // After one render, the palette commands registered this frame get
    // captured at end-of-frame and injected into next frame's env. A
    // second render cycle is needed for the reader to see them.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let seen = capturedCounts.value
    // We should see the env value at least once; after a second frame
    // it should include 3 palette commands.
    #expect(seen.contains(3), "Expected to observe 3 palette commands at some render, got: \(seen)")
  }
}

@MainActor
private final class LockedBoxLocal<T> {
  private var _value: T
  init(initial: T) { _value = initial }
  var value: T { _value }
  func update(_ mutate: (inout T) -> Void) { mutate(&_value) }
}

extension LockedBoxLocal where T == [Int] {
  func append(_ element: Int) {
    update { $0.append(element) }
  }
}

@MainActor
private struct GallerySimulator: View {
  static let snapshotAtKeyPress = LockedBoxLocal<[ActivePaletteCommand]>(initial: [])
  static let lastSeenEnvCount = LockedBoxLocal<Int>(initial: -1)

  static func reset() {
    snapshotAtKeyPress.update { $0 = [] }
    lastSeenEnvCount.update { $0 = -1 }
  }

  @State private var isPaletteOpen: Bool = false

  var body: some View {
    EnvironmentReader(\.activePaletteCommands) { commands in
      Self.lastSeenEnvCount.update { $0 = commands.count }
      return galleryBody(commands: commands)
    }
  }

  private func galleryBody(
    commands: [ActivePaletteCommand]
  ) -> some View {
    TabView(selection: .constant(0)) {
      Text("body").focusable(true).tag(0)
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(.init(title: "⌃K Palette", action: {}))
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: {
        Self.snapshotAtKeyPress.update { $0 = commands }
        isPaletteOpen = true
      }
    )
    .paletteCommand(name: "A", action: {})
    .paletteCommand(name: "B", action: {})
    .paletteCommand(name: "C", action: {})
    .toolbar(style: DefaultBottomToolbarStyle())
    .sheet("Command palette", isPresented: .constant(isPaletteOpen)) {
      Text("palette sheet")
    }
  }
}

@MainActor
private struct WrappedGallerySimulator: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GallerySimulator()
    }
  }
}

@MainActor
private struct PaletteDupProbeRoot: View {
  static let tickSource = LockedBoxLocal<Int>(initial: 0)

  @State private var tick: Int = 0

  var body: some View {
    TabView(selection: .constant(0)) {
      Text("tick=\(tick)").focusable(true).tag(0)
    }
    .tabViewStyle(.literalTabs)
    .panel(id: "gallery")
    .paletteCommand(name: "A", action: {})
    .paletteCommand(name: "B", action: {})
    .paletteCommand(name: "C", action: {})
    .onAppear {
      tick = Self.tickSource.value
    }
  }
}

@MainActor
private struct GalleryStyleOuter: View {
  @State private var selection: Int = 0

  static let selectionSink = LockedBoxLocal<Int>(initial: 0)
  static let capturedCommands = LockedBoxLocal<[ActivePaletteCommand]>(initial: [])

  var body: some View {
    EnvironmentReader(\.activePaletteCommands) { commands in
      Self.capturedCommands.update { $0 = commands }
      return
        TabView(selection: $selection) {
          Text("zero").focusable(true).tag(0)
          Text("one").focusable(true).tag(1)
        }
        .tabViewStyle(.literalTabs)
        .panel(id: "gallery")
        .paletteCommand(
          name: "Switch",
          action: {
            selection = 1
            Self.selectionSink.update { $0 = selection }
          }
        )
    }
  }
}

@MainActor
private func makeRunLoopLocal<V: View>(
  terminalSize: CellSize = .init(width: 40, height: 10),
  @ViewBuilder content: @escaping () -> V
) -> RunLoop<Int, V> {
  let terminal = GalleryStyleTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("GalleryStyleRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    terminalHost: terminal,
    terminalInputReader: GalleryStyleInputReader(),
    signalReader: GalleryStyleSignalReader(),
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
private func settleGalleryPaletteEnvironment<State, V: View>(
  _ runLoop: RunLoop<State, V>
) throws {
  for _ in 0..<3 {
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var rendered = 0
    try runLoop.renderPendingFrames(renderedFrames: &rendered)
  }
}

@MainActor
private func latestSurfaceText<State, V: View>(
  for runLoop: RunLoop<State, V>
) -> String {
  guard let terminal = runLoop.terminalHost as? GalleryStyleTerminalHost,
    let surface = terminal.latestSurface
  else {
    return ""
  }
  return surface.lines.joined(separator: "\n")
}

private final class GalleryStyleTerminalHost: TerminalHosting {
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

extension GalleryStyleTerminalHost: DamageAwareTerminalHosting {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class GalleryStyleInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class GalleryStyleSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
