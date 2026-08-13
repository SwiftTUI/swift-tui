import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

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
      .toolbar().toolbarStyle(DefaultBottomToolbarStyle())
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
      .toolbar().toolbarStyle(DefaultBottomToolbarStyle())
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

    // After two renders, PaletteCommandsPreferenceKey should have entries.
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // A contentless palette hands no command list to the caller, so the probe
    // drives the real activation path instead of calling a captured closure:
    // the palette renders the absorbed command, and Return on the focused
    // filter field activates the selected row. That is a stronger claim — it
    // shows the absorbed command reached the rendering AND that activating it
    // runs the action under the declaring view's authoring scope.
    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(surfaceText.contains("Switch"), "absorbed command did not render:\n\(surfaceText)")

    _ = runLoop.handleKeyPress(KeyPress(.return))
    var activationFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &activationFrames)

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

    // Observed on the rendered surface rather than through a content closure
    // the contentless palette no longer has: each absorbed command must appear
    // exactly once. A duplicate would paint a second row.
    let surfaceText = latestSurfaceText(for: runLoop)
    for name in ["Alpha probe", "Bravo probe", "Charlie probe"] {
      let occurrences = surfaceText.ranges(of: name).count
      #expect(
        occurrences == 1,
        "expected '\(name)' exactly once after re-resolves, got \(occurrences):\n\(surfaceText)"
      )
    }
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
    // Dropdown chrome: no title bar. The palette is contentless now, so its
    // presence is asserted through the framework body's rendered command rows.
    #expect(!surfaceText.contains("Command palette"))
    #expect(surfaceText.contains("Alpha probe"), "palette body did not render:\n\(surfaceText)")
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

    let surfaceText = latestSurfaceText(for: runLoop)
    #expect(!surfaceText.contains("Command palette"))
    #expect(surfaceText.contains("Alpha probe"), "palette body did not render:\n\(surfaceText)")
  }

}

@MainActor
private final class LockedBoxLocal<T> {
  private var _value: T
  init(initial: T) { _value = initial }
  var value: T { _value }
  func update(_ mutate: (inout T) -> Void) { mutate(&_value) }
}

@MainActor
private struct GallerySimulator: View {
  static func reset() {}

  @State private var isPaletteOpen: Bool = false

  var body: some View {
    galleryBody()
  }

  @ViewBuilder
  private func galleryBody() -> some View {
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
        isPaletteOpen = true
      }
    )
    .paletteCommand(name: "Alpha probe", action: {})
    .paletteCommand(name: "Bravo probe", action: {})
    .paletteCommand(name: "Charlie probe", action: {})
    .toolbar().toolbarStyle(DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen)
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
    .paletteCommand(name: "Alpha probe", action: {})
    .paletteCommand(name: "Bravo probe", action: {})
    .paletteCommand(name: "Charlie probe", action: {})
    .paletteSheet("__capture", isPresented: .constant(true))
    .onAppear {
      tick = Self.tickSource.value
    }
  }
}

@MainActor
private struct GalleryStyleOuter: View {
  @State private var selection: Int = 0

  static let selectionSink = LockedBoxLocal<Int>(initial: 0)

  var body: some View {
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
    .paletteSheet("__capture", isPresented: .constant(true))
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
    presentationSurface: terminal,
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
  guard let terminal = runLoop.presentationSurface as? GalleryStyleTerminalHost,
    let surface = terminal.latestSurface
  else {
    return ""
  }
  return surface.lines.joined(separator: "\n")
}

private final class GalleryStyleTerminalHost: PresentationSurface {
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

extension GalleryStyleTerminalHost: DamageAwarePresentationSurface {
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
