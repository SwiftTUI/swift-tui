@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Reproduction for the gallery Focus Context bug: with the second field
// focused, clicking "Mark focused reviewed" appended " reviewed" to the FIRST
// field. A mouse press moves focus onto the button itself before the release
// dispatches the action, so the action's `@FocusedBinding` read depends on the
// focused values the dispatch context serves — which must track the field that
// was focused when the click began, not a stale registration-time snapshot.
@Suite("FocusContextClickDispatch", .serialized)
@MainActor
struct FocusContextClickDispatchTests {
  @Test("Clicking the review button mutates the field that was focused, not the first field")
  func clickReviewButtonMutatesTheFocusedField() async throws {
    let harness = try ClickDispatchHarness()

    try await harness.click(ClickDispatchIDs.secondTitle)
    #expect(harness.focusedIdentity == ClickDispatchIDs.secondTitle)
    #expect(harness.surfaceText.contains("Focused title: Focused test lane"))

    try await harness.click(ClickDispatchIDs.review)

    #expect(harness.surfaceText.contains("Focused test lane reviewed"))
    #expect(!harness.surfaceText.contains("Coverage matrix reviewed"))
    // The button disabled itself the moment the press stole focus from the
    // field, so its region vanished and focus must return to the field the
    // user was in — not re-seat onto the first field in the scope.
    #expect(harness.focusedIdentity == ClickDispatchIDs.secondTitle)
    #expect(harness.surfaceText.contains("Focused title: Focused test lane reviewed"))
  }

  @Test("A click whose press/release straddle a frame still mutates the focused field")
  func straddledClickReviewButtonMutatesTheFocusedField() async throws {
    let harness = try ClickDispatchHarness()

    try await harness.click(ClickDispatchIDs.secondTitle)
    #expect(harness.focusedIdentity == ClickDispatchIDs.secondTitle)

    try await harness.click(ClickDispatchIDs.review, drainBetweenPressAndRelease: true)

    #expect(harness.surfaceText.contains("Focused test lane reviewed"))
    #expect(!harness.surfaceText.contains("Coverage matrix reviewed"))
    #expect(harness.focusedIdentity == ClickDispatchIDs.secondTitle)
    #expect(harness.surfaceText.contains("Focused title: Focused test lane reviewed"))
  }

  @Test("Clicking the review button after refocusing the first field mutates the first field")
  func clickReviewButtonTracksRefocusedFirstField() async throws {
    let harness = try ClickDispatchHarness()

    try await harness.click(ClickDispatchIDs.secondTitle)
    try await harness.click(ClickDispatchIDs.firstTitle)
    #expect(harness.focusedIdentity == ClickDispatchIDs.firstTitle)
    #expect(harness.surfaceText.contains("Focused title: Coverage matrix"))

    try await harness.click(ClickDispatchIDs.review)

    #expect(harness.surfaceText.contains("Coverage matrix reviewed"))
    #expect(!harness.surfaceText.contains("Focused test lane reviewed"))
  }
}

@MainActor
private final class ClickDispatchHarness {
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, GalleryLikeClickRoot>
  private let scheduler: FrameScheduler
  private var renderedFrames = 0

  init() throws {
    let terminalSize = CellSize(width: 72, height: 22)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("FocusContextClickRoot")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ClickDispatchInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in GalleryLikeClickRoot() }
    )
    focusTracker.invalidator = runLoop.scheduler
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler

    scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var surfaceText: String {
    terminal.frames.last ?? ""
  }

  func click(
    _ identity: Identity,
    drainBetweenPressAndRelease: Bool = false
  ) async throws {
    let region = try #require(
      runLoop.latestSemanticSnapshot.interactionRegions.first { region in
        region.identity == identity || region.identity.isDescendant(of: identity)
      },
      "no interaction region for \(identity)"
    )
    let center = PointerLocation.cellFallback(
      CellPoint(
        x: region.rect.origin.x + region.rect.size.width / 2,
        y: region.rect.origin.y + region.rect.size.height / 2
      )
    )
    runLoop.handleMouseDown(MouseButton.primary, location: center)
    if drainBetweenPressAndRelease {
      try await drain()
    }
    runLoop.handleMouseUp(MouseButton.primary, location: center)
    try await drain()
  }

  private func drain() async throws {
    var localRenderedFrames = renderedFrames
    defer { renderedFrames = localRenderedFrames }
    var iterations = 0
    while scheduler.hasPendingFrame(at: .now()) && iterations < 12 {
      _ = try await runLoop.renderPendingFramesAsync(renderedFrames: &localRenderedFrames)
      iterations += 1
    }
  }
}

private enum ClickDispatchIDs {
  static let firstTitle = testIdentity("ClickDispatchFirstTitle")
  static let secondTitle = testIdentity("ClickDispatchSecondTitle")
  static let review = testIdentity("ClickDispatchReview")
}

private enum ClickDispatchTitleKey: FocusedValueKey {
  typealias Value = Binding<String>
}

extension FocusedValues {
  fileprivate var clickDispatchTitle: Binding<String>? {
    get { self[ClickDispatchTitleKey.self] }
    set { self[ClickDispatchTitleKey.self] = newValue }
  }
}

// The gallery Focus Context page shape, including its (since removed) nested
// panel + bottom toolbar inside the gallery's own toolbar scope: the nesting
// must not perturb focused-value dispatch either.
private struct GalleryLikeClickTab: View {
  @State private var firstTitle = "Coverage matrix"
  @State private var secondTitle = "Focused test lane"
  @FocusedBinding(\.clickDispatchTitle) private var focusedTitle

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Focused title: \(focusedTitle ?? "none")")
      TextField("First title", text: $firstTitle)
        .id(ClickDispatchIDs.firstTitle)
        .focusedValue(\.clickDispatchTitle, $firstTitle)
      TextField("Second title", text: $secondTitle)
        .id(ClickDispatchIDs.secondTitle)
        .focusedValue(\.clickDispatchTitle, $secondTitle)
      Button("Mark focused reviewed") {
        guard let binding = $focusedTitle else { return }
        binding.wrappedValue = "\(binding.wrappedValue) reviewed"
      }
      .id(ClickDispatchIDs.review)
      .disabled($focusedTitle == nil)
      Spacer(minLength: 0)
    }
    .padding(1)
    .toolbarItem(.init(title: "Mark Focused", action: {}))
    .panel(id: "click-dispatch-focus-context")
    .toolbar(style: .defaultBottom)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct GalleryLikeClickRoot: View {
  @State private var selection = "focus"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Focus Context", value: "focus") {
        GalleryLikeClickTab()
      }
      Tab("Other", value: "other") {
        Text("Other content")
      }
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(.init(title: "⌃K Palette", action: {}))
    .panel(id: "click-dispatch-gallery")
    .toolbar(style: .defaultBottom)
  }
}

private final class ClickDispatchInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
