import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

/// Tests that focus transitions between controls (Tab/Shift-Tab) produce
/// visually distinct rendered frames — both in static rendering and through
/// the RunLoop's live focus-transition pipeline.
@MainActor
@Suite
struct FocusTransitionTests {

  // MARK: - Fixtures

  private static func tabViewWithPicker() -> some View {
    TabView(selection: .constant("demo")) {
      Tab("Demo", value: "demo") {
        Picker("Options", selection: .constant("one")) {
          Text("One").tag("one")
          Text("Two").tag("two")
          Text("Three").tag("three")
        }
        .pickerStyle(.segmented)
      }

      Tab("Other", value: "other") {
        Text("Other tab")
      }
    }
    .id(testIdentity("Tabs"))
  }

  private static func statefulTabSelectionView() -> some View {
    StatefulTabSelectionView()
  }

  private func renderArtifacts(
    focusedIdentity: Identity? = nil
  ) -> FrameArtifacts {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = focusedIdentity
    return DefaultRenderer().render(
      Self.tabViewWithPicker(),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      ),
      proposal: .init(width: 50, height: 10)
    )
  }

  // MARK: - Static rendering tests

  @Test("focus regions include both the TabView and the Picker inside it")
  func focusRegionsIncludeTabViewAndPicker() {
    let regions = renderArtifacts().semanticSnapshot.focusRegions
    #expect(regions.count >= 2)
    #expect(regions.contains { $0.identity == testIdentity("Tabs") })
    #expect(regions.contains { $0.identity != testIdentity("Tabs") })
  }

  @Test("segmented picker renders visually different styling when focused")
  func segmentedPickerShowsFocusHighlight() {
    let unfocusedArtifacts = renderArtifacts()
    let focusRegions = unfocusedArtifacts.semanticSnapshot.focusRegions

    guard let pickerRegion = focusRegions.first(where: { $0.identity != testIdentity("Tabs") })
    else {
      Issue.record("Picker focus region not found")
      return
    }

    let unfocusedStyles = unfocusedArtifacts.rasterSurface.styleRuns
    let pickerFocusedStyles = renderArtifacts(focusedIdentity: pickerRegion.identity)
      .rasterSurface.styleRuns
    let tabFocusedStyles = renderArtifacts(focusedIdentity: testIdentity("Tabs"))
      .rasterSurface.styleRuns

    #expect(
      pickerFocusedStyles != unfocusedStyles,
      "Picker focus should produce different styling than unfocused")
    #expect(
      tabFocusedStyles != unfocusedStyles,
      "TabView focus should produce different styling than unfocused")
    #expect(
      pickerFocusedStyles != tabFocusedStyles,
      "Picker focus should differ from TabView focus")
  }

  @Test("standalone Picker renders focus highlight when focusedIdentity matches")
  func standalonePickerFocusHighlight() {
    var env = EnvironmentValues()
    env.focusedIdentity = testIdentity("Picker")

    let focused = DefaultRenderer().render(
      Picker("Options", selection: .constant("one")) {
        Text("One").tag("one")
        Text("Two").tag("two")
      }
      .pickerStyle(.segmented)
      .id(testIdentity("Picker")),
      context: .init(identity: testIdentity("Root"), environmentValues: env),
      proposal: .init(width: 20, height: 4)
    ).rasterSurface.styleRuns

    let unfocused = DefaultRenderer().render(
      Picker("Options", selection: .constant("one")) {
        Text("One").tag("one")
        Text("Two").tag("two")
      }
      .pickerStyle(.segmented)
      .id(testIdentity("Picker")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 20, height: 4)
    ).rasterSurface.styleRuns

    #expect(
      focused != unfocused,
      "Standalone Picker styling should differ when focused")
  }

  @Test("segmented picker uses heavy border when focused")
  func segmentedPickerUsesHeavyBorderWhenFocused() {
    let unfocusedArtifacts = renderArtifacts()
    let focusRegions = unfocusedArtifacts.semanticSnapshot.focusRegions
    guard let pickerRegion = focusRegions.first(where: { $0.identity != testIdentity("Tabs") })
    else {
      Issue.record("Picker focus region not found")
      return
    }

    let pickerFocusedArtifacts = renderArtifacts(focusedIdentity: pickerRegion.identity)
    let focusedLines = pickerFocusedArtifacts.rasterSurface.lines

    let hasHeavyBorder = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
    #expect(hasHeavyBorder, "Focused segmented picker should use heavy border characters (┏┗)")

    let unfocusedLines = unfocusedArtifacts.rasterSurface.lines
    let unfocusedHasHeavy = unfocusedLines.contains { $0.contains("┏") || $0.contains("┗") }
    #expect(!unfocusedHasHeavy, "Unfocused picker should not use heavy border characters")
  }

  @Test("focused TextField uses heavy border")
  func focusedTextFieldUsesHeavyBorder() {
    var env = EnvironmentValues()
    env.focusedIdentity = testIdentity("Field")

    let focused = DefaultRenderer().render(
      TextField("Name", text: .constant("hello"))
        .textFieldStyle(.roundedBorder)
        .id(testIdentity("Field")),
      context: .init(identity: testIdentity("Root"), environmentValues: env),
      proposal: .init(width: 20, height: 4)
    )

    let focusedLines = focused.rasterSurface.lines
    let hasHeavy = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
    #expect(hasHeavy, "Focused TextField should use heavy border")

    let unfocused = DefaultRenderer().render(
      TextField("Name", text: .constant("hello"))
        .textFieldStyle(.roundedBorder)
        .id(testIdentity("Field")),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 20, height: 4)
    )

    let unfocusedLines = unfocused.rasterSurface.lines
    let unfocusedHasHeavy = unfocusedLines.contains { $0.contains("┏") || $0.contains("┗") }
    #expect(!unfocusedHasHeavy, "Unfocused TextField should not use heavy border")
  }

  @Test("focused plain button shows focus rail")
  func focusedPlainButtonShowsRail() {
    var env = EnvironmentValues()
    env.focusedIdentity = testIdentity("Btn")

    let focused = DefaultRenderer().render(
      Button("Submit") {}
        .buttonStyle(.plain)
        .id(testIdentity("Btn")),
      context: .init(identity: testIdentity("Root"), environmentValues: env),
      proposal: .init(width: 14, height: 1)
    )

    let focusedLines = focused.rasterSurface.lines
    let hasRail = focusedLines.contains { $0.contains("▌") }
    #expect(hasRail, "Focused plain button should show focus rail (▌)")
  }

  @Test("focused bordered button uses heavy border")
  func focusedBorderedButtonUsesHeavyBorder() {
    var env = EnvironmentValues()
    env.focusedIdentity = testIdentity("Btn")

    let focused = DefaultRenderer().render(
      Button("Submit") {}
        .buttonStyle(.bordered)
        .id(testIdentity("Btn")),
      context: .init(identity: testIdentity("Root"), environmentValues: env),
      proposal: .init(width: 14, height: 3)
    )

    let focusedLines = focused.rasterSurface.lines
    let hasHeavy = focusedLines.contains { $0.contains("┏") || $0.contains("┗") }
    #expect(hasHeavy, "Focused bordered button should use heavy border")
  }

  @Test("focused TabView emphasizes only the focused tab underline")
  func focusedTabViewEmphasizesOnlyTheFocusedTabUnderline() {
    var env = EnvironmentValues()
    env.focusedIdentity = testIdentity("Tabs")

    let focused = DefaultRenderer().render(
      Self.tabViewWithPicker(),
      context: .init(identity: testIdentity("Root"), environmentValues: env),
      proposal: .init(width: 50, height: 12)
    )

    let unfocused = DefaultRenderer().render(
      Self.tabViewWithPicker(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 50, height: 12)
    )

    let focusedLines = focused.rasterSurface.lines
    let unfocusedLines = unfocused.rasterSurface.lines

    // Unfocused: unselected tabs use ▁, selected uses ▂
    #expect(
      unfocusedLines.contains { $0.contains("▁") },
      "Unfocused unselected tabs should use lower one-eighth block (▁)")
    #expect(
      unfocusedLines.contains { $0.contains("▂") },
      "Unfocused selected tab should use lower quarter block (▂)")

    // Focused: only the focused tab is promoted; unfocused tabs keep
    // their resting underline weight.
    #expect(
      focusedLines.contains { $0.contains("▄") },
      "Focused selected tab should use lower half block (▄)")
    #expect(
      focusedLines.contains { $0.contains("▁") },
      "Focused unselected tabs should keep lower one-eighth block (▁)")
  }

  // MARK: - RunLoop integration tests

  @Test("Tab/Shift-Tab transitions update both controls' focus highlights correctly")
  func tabTransitionsUpdateBothHighlights() throws {
    let terminalSize = CellSize(width: 50, height: 10)
    let terminal = FocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("HighlightSync")

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FocusTestInputReader(events: []),
      signalReader: FocusTestSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in Self.tabViewWithPicker() }
    )

    focusTracker.invalidator = runLoop.scheduler

    // Initial render — TabView gets focus by default
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    let tabViewIdentity = testIdentity("Tabs")
    #expect(
      focusTracker.currentFocusIdentity == tabViewIdentity,
      "Initial focus should be on TabView")

    // State 1: TabView focused → tab strip has focus indicators, Picker has no heavy border
    var lines = terminal.latestSurface!.lines
    let state1TabHasFocusBlock = lines.contains { $0.contains("▄") || $0.contains("▂") }
    #expect(
      state1TabHasFocusBlock,
      "State 1: Focused TabView should show focus block characters in underline")
    #expect(
      !lines.contains { $0.contains("┏") || $0.contains("┗") },
      "State 1: Picker should NOT show heavy border when TabView is focused")

    // Tab → focus moves to Picker
    _ = runLoop.handleKeyPress(KeyPress(.tab))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let pickerIdentity = focusTracker.currentFocusIdentity
    #expect(
      pickerIdentity != tabViewIdentity,
      "After Tab, focus should have moved away from TabView")

    // State 2: Picker focused → Picker SHOULD have heavy border
    lines = terminal.latestSurface!.lines
    #expect(
      lines.contains { $0.contains("┏") || $0.contains("┗") },
      "State 2: Picker SHOULD show heavy border when focused")

    // Shift-Tab → focus moves back to TabView
    _ = runLoop.handleKeyPress(KeyPress(.tab, modifiers: .shift))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(
      focusTracker.currentFocusIdentity == tabViewIdentity,
      "After Shift-Tab, focus should return to TabView")

    // State 3: TabView focused again → Picker should NOT have heavy border
    lines = terminal.latestSurface!.lines
    #expect(
      !lines.contains { $0.contains("┏") || $0.contains("┗") },
      "State 3: Picker should NOT show heavy border after losing focus")
  }

  @Test("Multiple rapid Tab/Shift-Tab cycles maintain correct highlights")
  func multipleRapidCyclesMaintainHighlights() throws {
    let terminalSize = CellSize(width: 50, height: 10)
    let terminal = FocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("RapidCycles")

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FocusTestInputReader(events: []),
      signalReader: FocusTestSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in Self.tabViewWithPicker() }
    )

    focusTracker.invalidator = runLoop.scheduler

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    let tabViewIdentity = testIdentity("Tabs")

    for cycle in 1...5 {
      // Tab → Picker
      _ = runLoop.handleKeyPress(KeyPress(.tab))
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

      #expect(
        focusTracker.currentFocusIdentity != tabViewIdentity,
        "Cycle \(cycle): After Tab, focus should be on Picker")

      var lines = terminal.latestSurface!.lines
      #expect(
        !lines.contains { $0.contains("▄") },
        "Cycle \(cycle) after Tab: TabView should NOT show ▄")
      #expect(
        lines.contains { $0.contains("┏") || $0.contains("┗") },
        "Cycle \(cycle) after Tab: Picker SHOULD show heavy border")

      // Shift-Tab → TabView
      _ = runLoop.handleKeyPress(KeyPress(.tab, modifiers: .shift))
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

      #expect(
        focusTracker.currentFocusIdentity == tabViewIdentity,
        "Cycle \(cycle): After Shift-Tab, focus should be on TabView")

      lines = terminal.latestSurface!.lines
      #expect(
        lines.contains { $0.contains("▄") },
        "Cycle \(cycle) after Shift-Tab: TabView SHOULD show ▄")
      #expect(
        !lines.contains { $0.contains("┏") || $0.contains("┗") },
        "Cycle \(cycle) after Shift-Tab: Picker should NOT show heavy border")
    }
  }

  @Test("Tab key in RunLoop moves focus and changes rendered frame styling")
  func tabKeyRunLoopProducesDifferentFrame() throws {
    let terminalSize = CellSize(width: 50, height: 10)
    let terminal = FocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("FocusTransition")

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FocusTestInputReader(events: []),
      signalReader: FocusTestSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in Self.tabViewWithPicker() }
    )

    focusTracker.invalidator = runLoop.scheduler

    // Initial render
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    let initialFocus = focusTracker.currentFocusIdentity
    let initialStyles = terminal.latestSurface?.styleRuns ?? []
    #expect(initialFocus != nil)

    // Tab → focus should move to next control
    _ = runLoop.handleKeyPress(KeyPress(.tab))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let afterTabFocus = focusTracker.currentFocusIdentity
    let afterTabStyles = terminal.latestSurface?.styleRuns ?? []

    #expect(initialFocus != afterTabFocus, "Tab should move focus")
    #expect(afterTabFocus != nil)
    #expect(
      afterTabStyles != initialStyles,
      "Rendered frame should change after Tab (focus highlight moved)")

    // Shift-Tab → focus should move back
    _ = runLoop.handleKeyPress(KeyPress(.tab, modifiers: .shift))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let afterShiftTabFocus = focusTracker.currentFocusIdentity
    let afterShiftTabStyles = terminal.latestSurface?.styleRuns ?? []

    #expect(afterShiftTabFocus == initialFocus, "Shift-Tab should return to original")
    #expect(
      afterShiftTabStyles != afterTabStyles,
      "Shift-Tab frame should differ from Tab frame (focus moved back)")
  }

  @Test("TabView arrow navigation moves focus without auto-selecting and Enter commits selection")
  func tabViewArrowNavigationSeparatesFocusFromSelection() throws {
    let terminalSize = CellSize(width: 50, height: 8)
    let terminal = FocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("TabbedSelection")

    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize

    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FocusTestInputReader(events: []),
      signalReader: FocusTestSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in Self.statefulTabSelectionView() }
    )

    focusTracker.invalidator = runLoop.scheduler

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()

    let initialLines = terminal.latestSurface!.lines
    #expect(focusTracker.currentFocusIdentity == testIdentity("Tabs"))
    #expect(initialLines.contains { $0.contains("Demo body") })
    #expect(!initialLines.contains { $0.contains("Other body") })

    _ = runLoop.handleKeyPress(KeyPress(.arrowRight))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let afterArrowLines = terminal.latestSurface!.lines
    #expect(
      focusTracker.currentFocusIdentity == testIdentity("Tabs"),
      "Arrow navigation should keep focus on the tab strip")
    #expect(
      afterArrowLines.contains { $0.contains("Demo body") },
      "Moving tab focus should not auto-select the newly focused tab")
    #expect(!afterArrowLines.contains { $0.contains("Other body") })

    _ = runLoop.handleKeyPress(KeyPress(.return))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let afterReturnLines = terminal.latestSurface!.lines
    #expect(
      afterReturnLines.contains { $0.contains("Other body") },
      "Enter should select the focused tab")
    #expect(!afterReturnLines.contains { $0.contains("Demo body") })
  }
}

// MARK: - Test support types

private final class FocusTestTerminalHost: PresentationSurface {
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

extension FocusTestTerminalHost: DamageAwarePresentationSurface {
  func present(_ surface: RasterSurface, damage: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class FocusTestInputReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]
  init(events: [InputEvent]) { scriptedEvents = events }
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { cont in
      for e in scriptedEvents { cont.yield(e) }
      cont.finish()
    }
  }
}

private final class FocusTestSignalReader: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}

private struct StatefulTabSelectionView: View {
  @State private var selection = "demo"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Demo", value: "demo") {
        Text("Demo body")
      }

      Tab("Other", value: "other") {
        Text("Other body")
      }
    }
    .id(testIdentity("Tabs"))
  }
}
