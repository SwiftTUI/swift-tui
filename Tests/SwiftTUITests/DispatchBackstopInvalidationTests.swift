@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Event-dispatch backstop invalidations: the coarse root sweep after a
/// consumed key command (and the source-identity sweep inside a
/// presentation's dismiss action) exist only as backstops for actions with
/// untracked side effects. When the dispatched action's own writes already
/// scheduled a (reader-attributed) invalidation, the sweep is redundant —
/// and on the palette/sheet hot path it re-resolved the entire background
/// on every open and close frame (`root_invalidated` rode the transition's
/// replayed sets, disabling selective evaluation wholesale).
///
/// The narrow paths these tests pin: a key command whose action writes
/// `@State` invalidates only the recorded readers; an Escape dismissal
/// invalidates only the presentation's zero-size `__presentationTrigger`
/// leaf (whose re-resolve reports the deactivation that escalates to the
/// portal reconcile). The backstops stay: untracked side effects still
/// repaint via the root sweep, and an untracked dismiss binding still
/// dismisses via the trigger-leaf invalidation.
@MainActor
@Suite(.serialized)
struct DispatchBackstopInvalidationTests {
  @Test("a key command whose action writes @State spares disjoint subtrees")
  func keyCommandStateWriteSparesDisjointSubtree() throws {
    let harness = try DispatchBackstopHarness(
      rootLabel: "KeyCommandNarrowingRoot"
    ) { counter in
      KeyCommandNarrowingRoot(backgroundCounter: counter)
    }
    defer { harness.tearDown() }

    #expect(harness.lastFrame?.contains("flag: off") == true)
    let evaluationsBefore = harness.backgroundCounter.count

    try harness.pressKey(KeyPress(.character("k"), modifiers: .ctrl))

    #expect(
      harness.lastFrame?.contains("flag: on") == true,
      "the key command's @State write must render; frame:\n\(harness.lastFrame ?? "")"
    )
    #expect(
      harness.backgroundCounter.count == evaluationsBefore,
      """
      the disjoint background probe re-evaluated \
      \(harness.backgroundCounter.count - evaluationsBefore) time(s) during a \
      key command whose action's @State write already invalidated its \
      readers; the dispatch root sweep must stay a backstop for untracked \
      side effects only
      """
    )
  }

  @Test("a key command with untracked side effects keeps the root backstop")
  func keyCommandUntrackedSideEffectKeepsRootBackstop() throws {
    let box = UntrackedCounterBox()
    let harness = try DispatchBackstopHarness(
      rootLabel: "UntrackedKeyCommandRoot"
    ) { _ in
      UntrackedKeyCommandRoot(box: box)
    }
    defer { harness.tearDown() }

    #expect(harness.lastFrame?.contains("count: 0") == true)

    try harness.pressKey(KeyPress(.character("b"), modifiers: .ctrl))

    #expect(
      harness.lastFrame?.contains("count: 1") == true,
      """
      a key command whose action mutates untracked state schedules no \
      invalidation of its own; the dispatch backstop root sweep must \
      re-render it; frame:\n\(harness.lastFrame ?? "")
      """
    )
  }

  @Test("escape sheet dismissal spares the background")
  func escapeSheetDismissalSparesBackground() throws {
    let harness = try DispatchBackstopHarness(
      rootLabel: "SheetBackgroundRoot"
    ) { counter in
      SheetBackgroundRoot(backgroundCounter: counter)
    }
    defer { harness.tearDown() }

    try harness.pressKey(KeyPress(.character("o"), modifiers: .ctrl))
    #expect(
      harness.lastFrame?.contains("sheet content") == true,
      "the sheet must open; frame:\n\(harness.lastFrame ?? "")"
    )
    let evaluationsBefore = harness.backgroundCounter.count

    try harness.pressKey(KeyPress(.escape))

    #expect(
      harness.lastFrame?.contains("sheet content") == false,
      "escape must dismiss the sheet; frame:\n\(harness.lastFrame ?? "")"
    )
    #expect(
      harness.backgroundCounter.count == evaluationsBefore,
      """
      the sheet background probe re-evaluated \
      \(harness.backgroundCounter.count - evaluationsBefore) time(s) during \
      an escape dismissal; the dismiss action's tracked `isPresented` write \
      plus the trigger-leaf backstop must reconcile the portal without \
      re-resolving the background
      """
    )
  }

  @Test("escape dismissal through an untracked binding still dismisses")
  func escapeDismissalThroughUntrackedBindingStillDismisses() throws {
    let box = UntrackedPresentationBox()
    let harness = try DispatchBackstopHarness(
      rootLabel: "UntrackedBindingSheetRoot"
    ) { _ in
      UntrackedBindingSheetRoot(box: box)
    }
    defer { harness.tearDown() }

    #expect(
      harness.lastFrame?.contains("sheet content") == true,
      "the untracked-binding sheet must present initially; frame:\n\(harness.lastFrame ?? "")"
    )

    try harness.pressKey(KeyPress(.escape))

    #expect(
      harness.lastFrame?.contains("sheet content") == false,
      """
      an escape dismissal whose binding write is untracked schedules no \
      invalidation of its own; the trigger-leaf backstop must still \
      reconcile the portal entry away; frame:\n\(harness.lastFrame ?? "")
      """
    )
    #expect(box.isPresented == false)
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

private struct BackgroundEvaluationProbe: View {
  let counter: EvaluationCounter

  var body: some View {
    counter.record()
    return Text("background probe")
  }
}

/// Reads the flag inside its own body so the `@State` read is attributed to
/// this leaf's node (reader attribution), keeping the write's invalidation
/// disjoint from the background probe.
private struct FlagLeaf: View {
  @Binding var flag: Bool

  var body: some View {
    Text(flag ? "flag: on" : "flag: off")
  }
}

private struct KeyCommandNarrowingRoot: View {
  let backgroundCounter: EvaluationCounter
  @State private var flag = false

  var body: some View {
    VStack {
      VStack {
        BackgroundEvaluationProbe(counter: backgroundCounter)
        Text("background body")
      }
      FlagLeaf(flag: $flag)
    }
    .panel(id: "key-command-narrowing")
    .keyCommand(
      "Toggle flag",
      key: .character("k"),
      modifiers: .ctrl,
      action: { flag = true }
    )
  }
}

@MainActor
private final class UntrackedCounterBox {
  var value = 0
}

private struct UntrackedKeyCommandRoot: View {
  let box: UntrackedCounterBox

  var body: some View {
    Text("count: \(box.value)")
      .panel(id: "untracked-key-command")
      .keyCommand(
        "Bump",
        key: .character("b"),
        modifiers: .ctrl,
        action: { box.value += 1 }
      )
  }
}

private struct SheetBackgroundRoot: View {
  let backgroundCounter: EvaluationCounter
  @State private var showSheet = false

  var body: some View {
    VStack {
      BackgroundEvaluationProbe(counter: backgroundCounter)
      Text("background body")
    }
    .panel(id: "sheet-background")
    .keyCommand(
      "Open sheet",
      key: .character("o"),
      modifiers: .ctrl,
      action: { showSheet = true }
    )
    .sheet("Backstop Sheet", isPresented: $showSheet) {
      Text("sheet content")
    }
  }
}

@MainActor
private final class UntrackedPresentationBox {
  var isPresented = true
}

private struct UntrackedBindingSheetRoot: View {
  let box: UntrackedPresentationBox

  var body: some View {
    Text("background body")
      .sheet(
        "Untracked Sheet",
        isPresented: Binding(
          mainActorGet: { box.isPresented },
          set: { box.isPresented = $0 }
        )
      ) {
        Text("sheet content")
      }
  }
}

// MARK: - Harness

@MainActor
private final class DispatchBackstopHarness<Root: View> {
  let backgroundCounter = EvaluationCounter()
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, Root>
  private var renderedFrames = 0

  init(
    rootLabel: String,
    viewBuilder: @escaping @MainActor (EvaluationCounter) -> Root
  ) throws {
    let terminalSize = CellSize(width: 72, height: 20)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity(rootLabel)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let counter = backgroundCounter
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: DispatchBackstopInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder(counter) }
    )
    runLoop.installFocusTrackerInvalidator()
    runLoop.frameReadinessClock = { .now().advanced(by: .seconds(3600)) }
    self.terminal = terminal
    self.runLoop = runLoop

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    try settle()
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try settle()
  }

  func tearDown() {}

  var lastFrame: String? {
    terminal.frames.last
  }

  func settle(maxDrains: Int = 8) throws {
    for _ in 0..<maxDrains {
      let before = renderedFrames
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      if renderedFrames == before {
        return
      }
    }
  }

  func pressKey(_ keyPress: KeyPress) throws {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    try settle()
  }
}

private final class DispatchBackstopInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
