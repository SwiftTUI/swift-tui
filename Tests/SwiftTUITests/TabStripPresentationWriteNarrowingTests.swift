@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Strip-presentation state writes: a Tab/arrow key dispatched to a focused
/// `TabView` writes `storedFocusedTabIndex`, whose reader is the TabView body
/// itself — so reader attribution invalidates the near-root container identity
/// and conflict-denies the whole cone, recomputing the content subtree and
/// every unchanged strip item on each keypress.
///
/// The narrowing: the write certifies its value-impact cone (the flipped strip
/// items plus the overflow trigger), which replaces reader-derived invalidation
/// when every certified identity resolves onto live graph work. The body
/// re-run itself rides the state-dirty queue, so only reuse denial narrows.
/// A style that does not stamp the item route identities (`item.route`) fails
/// the liveness check and keeps today's reader-attributed broad invalidation.
@MainActor
@Suite(.serialized)
struct TabStripPresentationWriteNarrowingTests {
  @Test("an arrow keypress in the strip spares the tab content subtree")
  func stripArrowKeypressSparesContent() throws {
    let harness = try StripWriteHarness(
      rootLabel: "StripWriteSpareRoot"
    ) { counter in
      StripWriteTabRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption focuses the TabView container itself: the fixture's
    // content deliberately hosts no focusables, bindings, or key handlers, so
    // the only recompute pressure on the probe is the write's invalidation.
    let focusedBefore = try #require(harness.focusedIdentity)
    let frameBefore = try #require(harness.lastFrame)
    #expect(frameBefore.contains(">One"))
    let evaluationsBefore = harness.contentCounter.count

    // Arrow keys move the strip's focused item through the stored-focus-index
    // state slot without moving tracker focus. Only the flipped items' chrome
    // changes; the content payload is `f(authored, selection)` and neither
    // changed.
    try harness.press(KeyPress(.arrowRight))
    #expect(harness.focusedIdentity == focusedBefore)
    #expect(
      harness.contentCounter.count == evaluationsBefore,
      """
      the tab content probe re-evaluated \
      \(harness.contentCounter.count - evaluationsBefore) time(s) during an \
      arrow-key strip focus move; the certified strip-presentation write \
      should have spared it
      """
    )
    // The strip chrome itself must still update: the focused-item marker
    // moved, so the committed frame shows it on the next item.
    let frameAfterArrow = try #require(harness.lastFrame)
    #expect(frameAfterArrow.contains(">Two"))
    #expect(!frameAfterArrow.contains(">One"))

    // A second move and the move back stay spared.
    try harness.press(KeyPress(.arrowRight))
    try harness.press(KeyPress(.arrowLeft))
    #expect(harness.contentCounter.count == evaluationsBefore)

    // Enter commits the focused tab through the selection binding. That is a
    // genuine data write (the content payload changes), so the content MUST
    // recompute — the narrowing only covers the presentation slot, never the
    // selection axis.
    try harness.press(KeyPress(.return))
    let frameAfterCommit = try #require(harness.lastFrame)
    #expect(frameAfterCommit.contains("second tab content"))
  }

  @Test("a custom style without route stamps keeps strip presentation fresh")
  func customStyleWithoutRouteStampsKeepsStripFresh() throws {
    let harness = try StripWriteHarness(
      rootLabel: "StripWriteFallbackRoot"
    ) { counter in
      StripWriteUnroutedStyleTabRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // The style renders each item's focus marker but never calls
    // `item.route`, so the certified item identities resolve to no live
    // nodes. The write must fall back to reader-attributed (broad)
    // invalidation: the moved marker still renders.
    let frameBefore = try #require(harness.lastFrame)
    #expect(frameBefore.contains(">One"))
    try harness.press(KeyPress(.arrowRight))
    let frameAfter = try #require(harness.lastFrame)
    #expect(
      frameAfter.contains(">Two"),
      """
      the custom style's focused-item marker did not move after an arrow \
      keypress; a certified strip-presentation write must fall back to broad \
      invalidation when its identities have no live nodes
      """
    )
  }
}

// MARK: - Fixtures

@MainActor
private final class EvaluationCounter {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

private struct ContentEvaluationProbe: View {
  let counter: EvaluationCounter

  var body: some View {
    counter.record()
    return Text("content probe")
  }
}

/// Binding-free and handler-free, with no focusables: initial focus adoption
/// lands on the TabView container, so arrow keypresses dispatch to its key
/// handler and the probe measures only the write's invalidation cone.
private struct StripWriteTabRoot: View {
  let contentCounter: EvaluationCounter
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("One", value: 0) {
        VStack {
          Text("first tab content")
          ContentEvaluationProbe(counter: contentCounter)
        }
      }
      Tab("Two", value: 1) {
        Text("second tab content")
      }
      Tab("Three", value: 2) {
        Text("third tab content")
      }
    }
    .tabViewStyle(MarkerTabViewStyle(routesItems: true))
  }
}

/// Renders a deterministic focused-item marker. With `routesItems` the items
/// are wrapped in `item.route` (live `TabItem[i]` identities exist — the
/// narrowed path); without it no route identities exist and the certified
/// write must fall back to broad invalidation.
private struct MarkerTabViewStyle: TabViewStyle, Equatable {
  var routesItems: Bool

  var snapshotLabel: String {
    "MarkerTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.items.indices), id: \.self) { index in
          let item = configuration.items[index]
          if routesItems {
            item.route {
              markerText(for: item)
            }
          } else {
            markerText(for: item)
          }
        }
      }
      configuration.content
    }
  }

  @MainActor
  private func markerText(for item: TabViewStyleItemConfiguration) -> Text {
    Text(item.isFocused ? ">\(item.label.displayText)" : " \(item.label.displayText)")
  }
}

private struct StripWriteUnroutedStyleTabRoot: View {
  let contentCounter: EvaluationCounter
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("One", value: 0) {
        ContentEvaluationProbe(counter: contentCounter)
      }
      Tab("Two", value: 1) {
        Text("second tab content")
      }
    }
    .tabViewStyle(MarkerTabViewStyle(routesItems: false))
  }
}

// MARK: - Harness

@MainActor
private final class StripWriteHarness<Root: View> {
  let contentCounter = EvaluationCounter()
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, Root>
  private var renderedFrames = 0

  init(
    rootLabel: String,
    viewBuilder: @escaping @MainActor (EvaluationCounter) -> Root
  ) throws {
    let terminalSize = CellSize(width: 72, height: 16)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity(rootLabel)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let counter = contentCounter
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: StripWriteInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder(counter) }
    )
    runLoop.installFocusTrackerInvalidator()
    // Far-future readiness: every scheduled follow-up frame is consumable in
    // the same drain, so `settle()` reaches a true steady state.
    runLoop.frameReadinessClock = { .now().advanced(by: .seconds(3600)) }
    self.terminal = terminal
    self.runLoop = runLoop

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    // Drain focus-adoption follow-up frames, then render once more from the
    // root so the steady-state frame includes the adopted focus presentation
    // (the assertions below compare focused-item markers).
    try settle()
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try settle()
  }

  func tearDown() {}

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var lastFrame: String? {
    terminal.frames.last
  }

  /// Renders until no further frames commit (bounded, in case a fixture
  /// schedules unexpectedly).
  func settle(maxDrains: Int = 5) throws {
    for _ in 0..<maxDrains {
      let before = renderedFrames
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      if renderedFrames == before {
        return
      }
    }
  }

  func press(_ keyPress: KeyPress) throws {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    try settle()
  }
}

private final class StripWriteInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
