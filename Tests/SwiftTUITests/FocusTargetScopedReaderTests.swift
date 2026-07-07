@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Target-scoped runtime-focus side-field reads: a framework reader that
/// compares `focusedIdentity` exclusively against a declared set of exact
/// identities (`focusedIdentity(comparedAgainst:)` — `ScrollView` against
/// itself and its two synthetic indicator identities) is AFFECTED by a focus
/// move only when the moved identity is among those targets. Its presence on
/// a content descendant's root path therefore no longer blocks the
/// chrome-only demotion of that descendant: a metadata-only `.focusable()`
/// container inside a `ScrollView` needs no recompute cone, exactly as it
/// needs none outside one.
///
/// The boundary: a move onto one of the declared targets (the scroll view
/// itself) keeps the reader affected, so its own re-run — and the indicator
/// highlight it renders — stays fresh.
@MainActor
@Suite(.serialized)
struct FocusTargetScopedReaderTests {
  @Test("a focus move between containers beside a ScrollView spares the scroll-hosted interior")
  func scrollHostedContainerMoveSparesInterior() throws {
    let harness = try TargetScopedHarness(
      rootLabel: "TargetScopedSpareRoot"
    ) { counter in
      ScrollHostedFocusRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Adoption focuses the ScrollView itself (the first region in document
    // order — it IS a declared comparison target, so that move keeps its
    // cone). Prime one move to land on container A inside it; from there,
    // A -> B and B -> A are moves between metadata-only containers whose
    // root-path reader (the ScrollView) declared targets that include
    // neither, so both directions must spare A's interior probe.
    try harness.moveFocusNext()
    let evaluationsBefore = harness.contentCounter.count

    try harness.moveFocusNext()
    #expect(
      harness.contentCounter.count == evaluationsBefore,
      """
      the scroll-hosted container-interior probe re-evaluated \
      \(harness.contentCounter.count - evaluationsBefore) time(s) during a \
      focus move off a metadata-only container; a target-scoped ScrollView \
      reader on its path must not block the chrome-only demotion
      """
    )

    try harness.moveFocusPrevious()
    #expect(harness.contentCounter.count == evaluationsBefore)
  }

  @Test("a focus move onto the ScrollView itself keeps its cone")
  func scrollViewFocusKeepsItsCone() throws {
    let harness = try TargetScopedHarness(
      rootLabel: "TargetScopedBoundaryRoot"
    ) { counter in
      ScrollFocusBoundaryRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Adoption focuses the outside text; the next region is the ScrollView
    // itself. Moving onto it IS a move onto a declared comparison target:
    // the reader is affected, so it must stay a FULL suppression member and
    // its subtree (where the probe lives) recomputes with the fresh
    // indicator presentation. This is the boundary pin — if the
    // target-scoped predicate ever demoted moves onto the targets
    // themselves, the ScrollView's focus chrome would go stale and this
    // probe would stop recomputing.
    let evaluationsBefore = harness.contentCounter.count
    try harness.moveFocusNext()
    #expect(
      harness.contentCounter.count > evaluationsBefore,
      """
      the scroll-content probe did not re-evaluate when focus moved onto the \
      ScrollView; a move onto a declared comparison target must keep the \
      reader's full member cone
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

/// A metadata-only `.focusable()` container INSIDE a ScrollView (the sheet
/// shape: scroll chrome on the container's root path), plus an outside
/// focusable to move to. The probe lives inside the container.
private struct ScrollHostedFocusRoot: View {
  let contentCounter: EvaluationCounter

  var body: some View {
    VStack {
      ScrollView {
        VStack {
          Text("target A")
          ContentEvaluationProbe(counter: contentCounter)
        }
        .focusable()
        Text("scrolled filler")
      }
      Text("target B").focusable()
    }
  }
}

/// A ScrollView with no focusable content, so the scroll view itself is a
/// focus target; content is taller than the viewport so the vertical
/// indicator renders and its focused highlight is frame-visible.
private struct ScrollFocusBoundaryRoot: View {
  let contentCounter: EvaluationCounter

  var body: some View {
    VStack {
      Text("outside").focusable()
      ScrollView {
        VStack {
          ForEach(0..<32, id: \.self) { index in
            Text("row \(index)")
          }
          ContentEvaluationProbe(counter: contentCounter)
        }
      }
    }
  }
}

// MARK: - Harness

@MainActor
private final class TargetScopedHarness<Root: View> {
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
      terminalInputReader: TargetScopedInputReader(),
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

private final class TargetScopedInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
