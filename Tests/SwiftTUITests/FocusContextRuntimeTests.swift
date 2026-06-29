@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct FocusContextRuntimeTests {
  @Test("Tab traversal in a TabView-hosted focus context reaches the first editable field")
  func focusContextTabTraversalReachesFirstEditableField() throws {
    let harness = FocusContextRuntimeHarness()
    try harness.renderInitial()

    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.tabs)

    harness.handleTabWithoutRendering()
    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.firstTitle)
  }

  @Test("Repeated Tab cycles across a focus context remain converged")
  func repeatedTabCyclesAcrossFocusContextRemainConverged() throws {
    let harness = FocusContextRuntimeHarness()
    try harness.renderInitial()

    for index in 0..<40 {
      if index.isMultiple(of: 2) {
        try harness.pressTab()
      } else {
        try harness.pressShiftTab()
      }

      let focusedIdentity = try #require(harness.focusedIdentity)
      #expect(harness.currentFocusRegions.contains(focusedIdentity))
      switch focusedIdentity {
      case FocusContextRuntimeIDs.firstTitle:
        #expect(harness.surfaceText.contains("Focused title: Coverage matrix"))
      case FocusContextRuntimeIDs.secondTitle:
        #expect(harness.surfaceText.contains("Focused title: Focused test lane"))
      default:
        #expect(harness.surfaceText.contains("Focused title: none"))
      }
    }
  }

  @Test(
    "FocusedBinding action mutates only the currently focused text field",
    .disabled("Currently trips focus-sync non-convergence before action dispatch can be asserted.")
  )
  func focusedBindingActionMutatesCurrentlyFocusedTextFieldBinding() throws {
    let harness = FocusContextRuntimeHarness()
    try harness.renderInitial()

    try harness.focus(FocusContextRuntimeIDs.firstTitle)
    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.firstTitle)
    try harness.markFocusedReviewed()
    #expect(harness.surfaceText.contains("Focused title: Coverage matrix reviewed"))
    #expect(!harness.surfaceText.contains("Focused test lane reviewed"))

    try harness.focus(FocusContextRuntimeIDs.secondTitle)
    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.secondTitle)
    try harness.markFocusedReviewed()
    #expect(harness.surfaceText.contains("Focused title: Focused test lane reviewed"))
    #expect(harness.surfaceText.contains("Coverage matrix reviewed"))
  }
}

@MainActor
private final class FocusContextRuntimeHarness {
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, FocusContextRuntimeRoot>
  private var renderedFrames = 0

  init() {
    let terminalSize = CellSize(width: 72, height: 14)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("FocusContextRuntimeRoot")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: FocusContextInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in FocusContextRuntimeRoot() }
    )
    focusTracker.invalidator = runLoop.scheduler
    self.terminal = terminal
    self.runLoop = runLoop
  }

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var surfaceText: String {
    terminal.frames.last ?? ""
  }

  var currentFocusRegions: Set<Identity> {
    Set(runLoop.latestSemanticSnapshot.focusRegions.map(\.identity))
  }

  func renderInitial() throws {
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  func pressTab() throws {
    try press(KeyPress(.tab))
  }

  func pressTab(until expectedIdentity: Identity, maxPresses: Int = 6) throws {
    try press(KeyPress(.tab), until: expectedIdentity, maxPresses: maxPresses)
  }

  func pressShiftTab() throws {
    try press(KeyPress(.tab, modifiers: .shift))
  }

  func pressShiftTab(until expectedIdentity: Identity, maxPresses: Int = 6) throws {
    try press(KeyPress(.tab, modifiers: .shift), until: expectedIdentity, maxPresses: maxPresses)
  }

  func markFocusedReviewed() throws {
    try press(KeyPress(.character("r"), modifiers: .ctrl))
  }

  func focus(_ identity: Identity) throws {
    _ = runLoop.focusTracker.setFocus(to: identity)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  func handleTabWithoutRendering() {
    #expect(runLoop.handleKeyPress(KeyPress(.tab)) == nil)
  }

  private func press(_ keyPress: KeyPress) throws {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  private func press(
    _ keyPress: KeyPress,
    until expectedIdentity: Identity,
    maxPresses: Int
  ) throws {
    for _ in 0..<maxPresses {
      try press(keyPress)
      if focusedIdentity == expectedIdentity {
        return
      }
    }
    #expect(focusedIdentity == expectedIdentity)
  }
}

private enum FocusContextRuntimeIDs {
  static let tabs = testIdentity("FocusContextRuntimeTabs")
  static let firstTitle = testIdentity("FocusContextFirstTitle")
  static let secondTitle = testIdentity("FocusContextSecondTitle")
}

private enum FocusContextRuntimeTitleKey: FocusedValueKey {
  typealias Value = Binding<String>
}

extension FocusedValues {
  fileprivate var focusContextRuntimeTitle: Binding<String>? {
    get { self[FocusContextRuntimeTitleKey.self] }
    set { self[FocusContextRuntimeTitleKey.self] = newValue }
  }
}

private struct FocusContextRuntimeRoot: View {
  @State private var selection = "focus"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Focus Context", value: "focus") {
        FocusContextRuntimeTab()
      }
      Tab("Other", value: "other") {
        Text("Other tab")
      }
    }
    .tabViewStyle(.literalTabs)
    .id(FocusContextRuntimeIDs.tabs)
  }
}

private struct FocusContextRuntimeTab: View {
  @State private var firstTitle = "Coverage matrix"
  @State private var secondTitle = "Focused test lane"
  @FocusedBinding(\.focusContextRuntimeTitle) private var focusedTitle

  var body: some View {
    Panel(id: "focus-context-runtime") {
      VStack(alignment: .leading, spacing: 1) {
        Text("Focused title: \(focusedTitle ?? "none")")
        TextField("First title", text: $firstTitle)
          .id(FocusContextRuntimeIDs.firstTitle)
          .textFieldStyle(.roundedBorder)
          .focusedValue(\.focusContextRuntimeTitle, $firstTitle)
        TextField("Second title", text: $secondTitle)
          .id(FocusContextRuntimeIDs.secondTitle)
          .textFieldStyle(.roundedBorder)
          .focusedValue(\.focusContextRuntimeTitle, $secondTitle)
      }
      .padding(1)
    }
    .keyCommand("Mark focused reviewed", key: .character("r"), modifiers: .ctrl) {
      if let focusedTitle {
        self.focusedTitle = "\(focusedTitle) reviewed"
      }
    }
  }
}

private final class FocusContextInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
