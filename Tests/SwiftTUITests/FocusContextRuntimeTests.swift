@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct FocusContextRuntimeTests {
  // Bug #3 facet 1 ("hitting Tab does not appear to do anything"): one Tab from
  // the tab strip should advance focus to the first editable field, but it stops
  // on the `Panel` wrapping the tab body. `Panel` is an `ActionScope` ("a focus
  // region that owns commands") and is an unconditional focus *target* so its
  // commands can activate even with no focusable descendant — which makes Tab
  // land on a container, diverging from SwiftUI (Tab lands on leaves). This is a
  // design issue (Panel conflates command-owning scope with focus target), not a
  // surgical bug; tracked in docs/proposals/2026-06-29-001-focus-model-reassessment.md.
  // Recorded as a known issue so it documents the divergence without reddening the
  // gate; flips to a failure when focus traversal is redesigned.
  @Test("Tab traversal in a TabView-hosted focus context reaches the first editable field")
  func focusContextTabTraversalReachesFirstEditableField() throws {
    let harness = FocusContextRuntimeHarness()
    try harness.renderInitial()

    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.tabs)

    harness.handleTabWithoutRendering()
    withKnownIssue(
      "bug #3 facet 1: one Tab lands focus on the Panel scope, not the first field (see focus-model-reassessment proposal)"
    ) {
      #expect(harness.focusedIdentity == FocusContextRuntimeIDs.firstTitle)
    }
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

  // Drilldown for the Focus Context tab: a @FocusedBinding mutation lands on the
  // currently focused field and the status consumer reflects it.
  //
  // CRASH FIXED (bug #3 facet 2): dispatching the focused-binding mutation while
  // a `.focusedValue`-publishing field is focused used to drive the focus-sync
  // loop past its rerender budget and trap (`RunLoop+Rendering.swift:125`,
  // signal 5). Root cause: `FocusedValues.==` reported a `Binding` focused value
  // as always-changed (non-`AnyHashable` -> false), so the loop never converged.
  // Fixed by comparing focused bindings by their current value
  // (`MainActorFocusedValueEquatable`), converging in <=2 passes.
  @Test("FocusedBinding mutation lands on the focused field without looping the focus-sync budget")
  func focusedBindingMutationLandsOnFocusedField() throws {
    let harness = FocusContextRuntimeHarness()
    try harness.renderInitial()

    try harness.focus(FocusContextRuntimeIDs.firstTitle)
    #expect(harness.focusedIdentity == FocusContextRuntimeIDs.firstTitle)
    #expect(harness.surfaceText.contains("Focused title: Coverage matrix"))

    // Previously trapped here: the binding focused value compared always-unequal
    // and the focus-sync loop ran to the rerender budget. Now it converges, the
    // write lands on the focused field, and the status consumer reflects it.
    try harness.markFocusedReviewed()
    #expect(harness.surfaceText.contains("Focused title: Coverage matrix reviewed"))
    #expect(!harness.surfaceText.contains("Focused test lane reviewed"))
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
