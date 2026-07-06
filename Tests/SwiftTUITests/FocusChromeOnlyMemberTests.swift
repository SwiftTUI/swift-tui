@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Chrome-only focus members: a pure focus move onto/off an identity whose
/// root-path has NO evaluation-time runtime-focus reader (a metadata-only
/// `.focusable()` container — nothing at or above it consults
/// `focusedIdentity`/`pressedIdentity`/`isFocused` while resolving) needs no
/// recompute cone at all. Its focus presentation is host-side chrome derived
/// from the committed semantic snapshot, and descendants compare focus
/// against their own identities, which did not change.
///
/// The old/new focus identities still ride the suppression scope as
/// *chrome-only* members so the frame keeps finite focus coverage (no
/// root-force), but they deny no reuse and queue no dirty work — in BOTH
/// currencies (scope matching and the tracker's move notification, filtered
/// at the source).
///
/// The soundness boundary: any flagged reader at or above the focus identity
/// (framework controls read the side-fields self-or-descendant-equality
/// style — `List` compares its row identities, `Button` itself) keeps the
/// full member cone, because the reader's re-run may hand fresh values into
/// the focused subtree.
@MainActor
@Suite(.serialized)
struct FocusChromeOnlyMemberTests {
  @Test("a focus move between metadata-only focusable containers spares their interiors")
  func metadataOnlyFocusMoveSparesInterior() throws {
    let harness = try ChromeOnlyHarness(
      rootLabel: "ChromeOnlySpareRoot"
    ) { counter in
      ChromeOnlyFocusRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption focuses container A (the first focusable); the probe
    // sits inside it, so today's member cone recomputes it on every move.
    let containerIdentity = try #require(harness.focusedIdentity)
    let evaluationsBefore = harness.contentCounter.count

    // A -> B: both members are metadata-only containers; neither cone
    // should recompute.
    try harness.moveFocusNext()
    #expect(harness.focusedIdentity != containerIdentity)
    #expect(
      harness.contentCounter.count == evaluationsBefore,
      """
      the container-interior probe re-evaluated \
      \(harness.contentCounter.count - evaluationsBefore) time(s) during a \
      focus move between metadata-only focusable containers; chrome-only \
      members should spare both interiors
      """
    )

    // B -> A: the move back is spared the same way.
    try harness.moveFocusPrevious()
    #expect(harness.focusedIdentity == containerIdentity)
    #expect(harness.contentCounter.count == evaluationsBefore)
  }

  @Test("a focused control keeps its full cone (Button label interior recomputes)")
  func focusedControlKeepsItsCone() throws {
    let harness = try ChromeOnlyHarness(
      rootLabel: "ChromeOnlyControlRoot"
    ) { counter in
      ChromeOnlyButtonRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Adoption focuses the Button — a flagged runtime-focus reader (its body
    // consults `focusedIdentity` self-equality), so it must stay a FULL
    // suppression-scope member: moving focus off it re-runs its body, and
    // the label interior (where the probe lives) recomputes with the fresh
    // presentation. This is the flagged-reader boundary of the chrome-only
    // narrowing — if the side-field read attribution ever missed `Button`,
    // this probe would stop recomputing.
    let evaluationsBefore = harness.contentCounter.count
    try harness.moveFocusNext()
    #expect(
      harness.contentCounter.count > evaluationsBefore,
      """
      the Button label probe did not re-evaluate when focus moved off the \
      Button; a runtime-focus-reading control must keep its full member cone
      """
    )
  }

  @Test("a List row focus move keeps the row highlight fresh (ancestor reader)")
  func listRowFocusMoveKeepsHighlightFresh() throws {
    let harness = try ChromeOnlyHarness(
      rootLabel: "ChromeOnlyListRoot"
    ) { counter in
      ChromeOnlyListRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // The List body is an ancestor runtime-focus reader (it compares row
    // identities against `focusedIdentity`), so row-focus moves must keep
    // recomputing the highlight even though the row identities themselves
    // carry no reader.
    let frameBefore = try #require(harness.lastFrame)
    try harness.moveFocusNext()
    let frameAfter = try #require(harness.lastFrame)
    #expect(
      frameBefore != frameAfter,
      """
      moving focus between List rows did not change the rendered highlight; \
      an ancestor runtime-focus reader must keep the focused identity a full \
      suppression-scope member
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

/// Two metadata-only `.focusable()` containers; the probe lives inside the
/// first. No bindings, handlers, or framework focus readers anywhere on the
/// containers' root paths.
private struct ChromeOnlyFocusRoot: View {
  let contentCounter: EvaluationCounter

  var body: some View {
    VStack {
      VStack {
        Text("target A")
        ContentEvaluationProbe(counter: contentCounter)
      }
      .focusable()
      Text("target B").focusable()
    }
  }
}

private struct ChromeOnlyButtonRoot: View {
  let contentCounter: EvaluationCounter

  var body: some View {
    VStack {
      Button {
      } label: {
        VStack {
          Text("press me")
          ContentEvaluationProbe(counter: contentCounter)
        }
      }
      Text("elsewhere").focusable()
    }
  }
}

private struct ChromeOnlyListRoot: View {
  let contentCounter: EvaluationCounter
  @State private var selection = 0

  var body: some View {
    VStack {
      List(selection: $selection) {
        Text("row zero").tag(0)
        Text("row one").tag(1)
        Text("row two").tag(2)
      }
      ContentEvaluationProbe(counter: contentCounter)
    }
  }
}

// MARK: - Harness

@MainActor
private final class ChromeOnlyHarness<Root: View> {
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
      terminalInputReader: ChromeOnlyInputReader(),
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
    // Drain focus-adoption follow-ups, then render once more from the root
    // so the steady-state frame includes the adopted focus presentation.
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

private final class ChromeOnlyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
