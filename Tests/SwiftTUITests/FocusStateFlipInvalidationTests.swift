@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime `@FocusState` flips are reader-attributed: when focus-sync applies
/// a focus change to a bound `@FocusState` (the `applyRuntimeFocus` leg of
/// `LocalFocusBindingRegistry.sync`), the invalidation targets the slot's
/// recorded readers — the `.focused()` registration site (which must
/// re-register with fresh `isSelected`) and any body that genuinely read the
/// value — not the owner's whole identity. A body that merely *projects* the
/// binding (`$focus`) hosts the storage but presents nothing derived from it,
/// so its sibling content must keep retained reuse across the flip.
///
/// Authored requests (`focus = true` from an action) keep the owner-identity
/// invalidation: a pending request must reach a re-resolve of the
/// registration site to be consumed, and the owner cone guarantees that
/// regardless of reader attribution.
@MainActor
@Suite(.serialized)
struct FocusStateFlipInvalidationTests {
  @Test("a runtime focus flip spares siblings of the bound control")
  func runtimeFlipSparesProjectionOnlySiblings() throws {
    let harness = try FocusFlipHarness(
      rootLabel: "FocusFlipSpareRoot"
    ) { counter in
      FocusFlipProjectionOnlyRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption focused the TextField and applied `true` to the
    // binding; settled. Moving focus off the field applies `false` — a
    // genuine runtime flip. The probe is a sibling of the field inside the
    // owner's body and reads nothing focus-derived, so it must not
    // re-evaluate.
    let evaluationsBefore = harness.contentCounter.count
    try harness.moveFocusNext()
    #expect(
      harness.contentCounter.count == evaluationsBefore,
      """
      the owner-body sibling probe re-evaluated \
      \(harness.contentCounter.count - evaluationsBefore) time(s) during a \
      runtime @FocusState flip; the flip's invalidation should target the \
      slot's readers, not the owner's whole cone
      """
    )

    // Moving back applies `true` again — same sparing in the other
    // direction.
    try harness.moveFocusPrevious()
    #expect(harness.contentCounter.count == evaluationsBefore)
  }

  @Test("a body that reads the focus state keeps its cone and stays fresh")
  func valueReadingBodyRecomputesOnFlip() throws {
    let harness = try FocusFlipHarness(
      rootLabel: "FocusFlipReaderRoot"
    ) { counter in
      FocusFlipReadingRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // The owner body renders a value derived from the focus state, so it is
    // a recorded reader: the flip must re-run it (the probe recomputes as
    // part of the owner's re-presented cone) and the rendered frame must
    // show the fresh value.
    let evaluationsBefore = harness.contentCounter.count
    let frameBefore = try #require(harness.lastFrame)
    #expect(frameBefore.contains("field focused"))

    try harness.moveFocusNext()
    let frameAfter = try #require(harness.lastFrame)
    #expect(
      harness.contentCounter.count > evaluationsBefore,
      """
      the probe inside a value-reading owner body did not re-evaluate on the \
      runtime flip; reader attribution must keep genuine readers in the cone
      """
    )
    #expect(
      frameAfter.contains("field blurred"),
      "the rendered focus-derived text went stale across the runtime flip"
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

/// The owner body only *projects* the focus binding to the field; nothing in
/// the body reads its value. The probe is a sibling of the bound field.
private struct FocusFlipProjectionOnlyRoot: View {
  let contentCounter: EvaluationCounter
  @FocusState private var isFieldFocused: Bool
  @State private var text = ""

  var body: some View {
    VStack {
      TextField("field", text: $text)
        .focused($isFieldFocused)
      Text("elsewhere").focusable()
      ContentEvaluationProbe(counter: contentCounter)
    }
  }
}

/// The owner body genuinely reads the focus-state value, so it is a recorded
/// reader of the slot and must recompute on every runtime flip.
private struct FocusFlipReadingRoot: View {
  let contentCounter: EvaluationCounter
  @FocusState private var isFieldFocused: Bool
  @State private var text = ""

  var body: some View {
    VStack {
      TextField("field", text: $text)
        .focused($isFieldFocused)
      Text("elsewhere").focusable()
      Text(isFieldFocused ? "field focused" : "field blurred")
      ContentEvaluationProbe(counter: contentCounter)
    }
  }
}

// MARK: - Harness

@MainActor
private final class FocusFlipHarness<Root: View> {
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
      terminalInputReader: FocusFlipInputReader(),
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
    // Drain focus-adoption follow-ups (including the adoption's own runtime
    // flip), then render once more from the root so the steady-state frame
    // includes the adopted focus presentation.
    try settle()
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try settle()
  }

  func tearDown() {}

  var lastFrame: String? {
    terminal.frames.last
  }

  func settle(maxDrains: Int = 5) throws {
    for _ in 0..<maxDrains {
      let before = renderedFrames
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      if renderedFrames == before {
        return
      }
    }
  }

  func moveFocusNext() throws {
    runLoop.focusTracker.focusNext()
    try settle()
  }

  func moveFocusPrevious() throws {
    runLoop.focusTracker.focusPrevious()
    try settle()
  }
}

private final class FocusFlipInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
