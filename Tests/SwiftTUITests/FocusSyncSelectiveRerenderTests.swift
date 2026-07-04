@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F08 lever B: the eager focus-sync rerender (the at-most-one second pass a
/// mid-frame focus relocation triggers) rides the selective dirty-frontier
/// path instead of forcing root evaluation, except for scroll-reveal rerenders,
/// which have no attributable identity cone and keep the root-forced fallback.
///
/// The correctness trap these tests pin: on the rerender path,
/// `processFocusSyncIteration` returns before the pure-focused-value reader
/// invalidation block, and pass 2 compares against the already-updated
/// `currentFocusedValues` — so `@FocusedValue` readers outside the relocation
/// cone must ride the rerender's suppression scope or they are never scheduled
/// again and go permanently stale.
///
/// Serialized: each test toggles the global
/// `RuntimeRegistrationPublicationDiagnosticsConfiguration` to observe
/// per-frame plan attribution.
@MainActor
@Suite(.serialized)
struct FocusSyncSelectiveRerenderTests {
  @Test("sheet-open focus adoption commits a selective focus-sync rerender")
  func sheetOpenFocusAdoptionCommitsSelectively() throws {
    let harness = try SelectiveRerenderHarness(
      rootLabel: "SheetSelectiveRerenderRoot"
    ) { counter in
      SheetRerenderRoot(stableCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption focuses the opener button (the first focusable).
    #expect(harness.focusedIdentity == SheetRerenderIDs.opener)
    let framesBeforeOpen = harness.renderedFrameCount

    try harness.press(KeyPress(.return))

    // The open frame is the one that ran the eager focus-sync rerender: the
    // selective pass composed the sheet via portal escalation, then focus
    // adopted into the modal scope mid-frame.
    let openSample = try #require(
      harness.rerenderSample(after: framesBeforeOpen),
      "opening the sheet must run the eager focus-sync rerender"
    )
    let publication = openSample.diagnostics.runtime.registrations.publication
    #expect(
      publication.selectiveEvaluationDisabledReasons.isEmpty,
      """
      the focus-sync rerender must not force root evaluation; got disabled \
      reasons: \(publication.selectiveEvaluationDisabledReasons)
      """
    )
    #expect(publication.dirtyPlanResult == "formed")

    // Same-frame correctness: the committed open frame must show the sheet
    // AND the relocated focused value on the reader outside the focus cone.
    // Same-frame correctness: the committed open frame shows the composed
    // sheet, and focus adopted into the modal scope (the sheet chrome's close
    // control is the first modal region, so it wins adoption here).
    let openFrame = try #require(harness.frame(for: openSample))
    #expect(openFrame.contains("Sheet action"))
    #expect(harness.focusedIdentity != SheetRerenderIDs.opener)
  }

  @Test("a mid-frame focus departure commits selectively and spares static siblings")
  func focusDepartureCommitsSelectively() throws {
    let harness = try SelectiveRerenderHarness(
      rootLabel: "DepartureSelectiveRerenderRoot"
    ) { counter in
      DepartureRerenderRoot(stableCounter: counter)
    }
    defer { harness.tearDown() }

    #expect(harness.focusedIdentity == DepartureRerenderIDs.departing)
    let framesBeforeDeparture = harness.renderedFrameCount
    let stableEvaluationsBeforeDeparture = harness.stableCounter.count

    try harness.press(KeyPress(.return))

    let departureSample = try #require(
      harness.rerenderSample(after: framesBeforeDeparture),
      "removing the focused control must run the eager focus-sync rerender"
    )
    let publication = departureSample.diagnostics.runtime.registrations.publication
    #expect(
      publication.selectiveEvaluationDisabledReasons.isEmpty,
      """
      the focus-sync rerender must not force root evaluation; got disabled \
      reasons: \(publication.selectiveEvaluationDisabledReasons)
      """
    )
    #expect(publication.dirtyPlanResult == "formed")
    #expect(publication.publicationMode == "subtrees")

    // Same-frame correctness: the relocated focused value is visible on the
    // committed frame's reader (outside the relocation cone), and the landing
    // control's @FocusState owner — also outside the state-write cone — shows
    // its runtime flip.
    let departureFrame = try #require(harness.frame(for: departureSample))
    #expect(departureFrame.contains("Focused label: Landing"))
    #expect(departureFrame.contains("Landing focused: yes"))
    #expect(harness.focusedIdentity == DepartureRerenderIDs.landing)

    // Narrowness: the static sibling outside the focus cone must not
    // re-evaluate on the rerender pass. FOLLOW-UP tolerance: the focus
    // tracker's mid-frame move schedules a follow-up frame whose invalidation
    // set still names the DEPARTED identity; that identity no longer maps to
    // a graph node, so the follow-up trips `nil_unmapped_invalidated_identity`
    // into one full evaluation (+1 below). Narrowing that follow-up is its own
    // tranche — this bound fails if the rerender pass itself widens.
    #expect(
      harness.stableCounter.count <= stableEvaluationsBeforeDeparture + 1,
      """
      the static sibling re-evaluated \
      \(harness.stableCounter.count - stableEvaluationsBeforeDeparture) time(s) \
      during a scoped focus-sync rerender interaction
      """
    )
  }

  @Test("a scroll-reveal focus-sync rerender keeps the root-forced fallback")
  func scrollRevealRerenderKeepsRootForcedFallback() throws {
    let harness = try SelectiveRerenderHarness(
      rootLabel: "ScrollSelectiveRerenderRoot"
    ) { counter in
      ScrollRerenderRoot(stableCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption picks the scroll container; Tab moves onto the
    // above-fold control inside the scroll interior (frame-head path). The
    // interior buttons keep structural identities — an authored absolute
    // `.id` would rebase them outside the scroll route's identity subtree and
    // defeat the reveal's ancestry check.
    try harness.press(KeyPress(.tab))
    let framesBeforeReveal = harness.renderedFrameCount

    // The next Tab advances focus to the below-fold field; the frame that
    // renders the move detects the needed scroll reveal mid-frame
    // (`scrollPositionChanged`) and runs the eager rerender.
    try harness.press(KeyPress(.tab))

    let revealSample = try #require(
      harness.rerenderSample(after: framesBeforeReveal),
      "focusing the below-fold field must run the eager focus-sync rerender"
    )
    let publication = revealSample.diagnostics.runtime.registrations.publication
    #expect(
      publication.selectiveEvaluationDisabledReasons.contains(
        "frame_state_force_root(focus_sync_rerender)"
      ),
      """
      a scroll-reveal rerender has no attributable scope and must keep the \
      root-forced fallback; got: \(publication.selectiveEvaluationDisabledReasons)
      """
    )

    // The reveal scrolled the below-fold field into the committed viewport.
    let revealFrame = try #require(harness.frame(for: revealSample))
    #expect(revealFrame.contains("below-fold field"))
  }
}

// MARK: - Harness

@MainActor
private final class RecordingFrameDiagnosticSink: FrameDiagnosticSink {
  private(set) var committedSamples: [CommittedFrameSample] = []

  nonisolated init() {}

  func record(_ sample: RuntimeFrameSample) {
    if case .committed(let committed) = sample {
      committedSamples.append(committed)
    }
  }
}

@MainActor
private final class EvaluationCounter {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

@MainActor
private final class SelectiveRerenderHarness<Root: View> {
  let sink = RecordingFrameDiagnosticSink()
  let stableCounter = EvaluationCounter()
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, Root>
  private var renderedFrames = 0
  private let previousDiagnosticsEnabled: Bool

  init(
    rootLabel: String,
    viewBuilder: @escaping @MainActor (EvaluationCounter) -> Root
  ) throws {
    previousDiagnosticsEnabled =
      RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled
    RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled = true

    let terminalSize = CellSize(width: 72, height: 12)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity(rootLabel)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let counter = stableCounter
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: SelectiveRerenderInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder(counter) }
    )
    focusTracker.invalidator = runLoop.scheduler
    runLoop.frameSink = sink
    // Far-future readiness: every scheduled follow-up frame is consumable in
    // the same drain, so `settle()` reaches a true steady state.
    runLoop.frameReadinessClock = { .now().advanced(by: .seconds(3600)) }
    self.terminal = terminal
    self.runLoop = runLoop

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    // Drain focus-adoption follow-up frames so tests observe steady state.
    try settle()
  }

  func tearDown() {
    RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled =
      previousDiagnosticsEnabled
  }

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var renderedFrameCount: Int {
    renderedFrames
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


  /// The first committed sample after `frameCount` that ran the eager
  /// focus-sync rerender.
  func rerenderSample(after frameCount: Int) -> CommittedFrameSample? {
    sink.committedSamples.first {
      $0.frameNumber > frameCount && $0.focusSyncRerenders == 1
    }
  }

  /// The committed terminal frame for `sample` (frame numbers are 1-based and
  /// align with the recording surface's presented frames on the sync driver).
  func frame(for sample: CommittedFrameSample) -> String? {
    let index = sample.frameNumber - 1
    guard terminal.frames.indices.contains(index) else {
      return nil
    }
    return terminal.frames[index]
  }
}

private final class SelectiveRerenderInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

// MARK: - Shared fixture pieces

private struct StableEvaluationProbe: View {
  let counter: EvaluationCounter

  var body: some View {
    counter.record()
    return Text("stable sibling")
  }
}

private enum SelectiveRerenderLabelKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var selectiveRerenderLabel: String? {
    get { self[SelectiveRerenderLabelKey.self] }
    set { self[SelectiveRerenderLabelKey.self] = newValue }
  }
}

private struct SelectiveRerenderReader: View {
  @FocusedValue(\.selectiveRerenderLabel) private var label

  var body: some View {
    Text("Focused label: \(label ?? "none")")
  }
}

// MARK: - Sheet fixture

private enum SheetRerenderIDs {
  static let reader = testIdentity("SheetSelectiveRerender", "Reader")
  static let opener = testIdentity("SheetSelectiveRerender", "Opener")
  static let stable = testIdentity("SheetSelectiveRerender", "Stable")
}

private struct SheetRerenderContent: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Sheet action") {}
        .focusedValue(\.selectiveRerenderLabel, "SheetField")
    }
  }
}

private struct SheetRerenderTrigger: View {
  @State private var isPresented = false

  var body: some View {
    Button("Open sheet") {
      isPresented = true
    }
    .id(SheetRerenderIDs.opener)
    .sheet(isPresented: $isPresented) {
      SheetRerenderContent()
    }
  }
}

private struct SheetRerenderRoot: View {
  let stableCounter: EvaluationCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SelectiveRerenderReader()
        .id(SheetRerenderIDs.reader)
      SheetRerenderTrigger()
      StableEvaluationProbe(counter: stableCounter)
        .id(SheetRerenderIDs.stable)
    }
  }
}

// MARK: - Focus-departure fixture

private enum DepartureRerenderIDs {
  static let reader = testIdentity("DepartureSelectiveRerender", "Reader")
  static let departing = testIdentity("DepartureSelectiveRerender", "Departing")
  static let landing = testIdentity("DepartureSelectiveRerender", "Landing")
  static let stable = testIdentity("DepartureSelectiveRerender", "Stable")
}

private struct DepartureRerenderLandingField: View {
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Landing focused: \(isFocused ? "yes" : "no")")
      Button("landing field") {}
        .id(DepartureRerenderIDs.landing)
        .focused($isFocused)
        .focusedValue(\.selectiveRerenderLabel, "Landing")
    }
  }
}

private struct DepartureRerenderPane: View {
  @State private var showsDeparting = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsDeparting {
        Button("hide me") {
          showsDeparting = false
        }
        .id(DepartureRerenderIDs.departing)
        .focusedValue(\.selectiveRerenderLabel, "Departing")
      }
    }
  }
}

private struct DepartureRerenderRoot: View {
  let stableCounter: EvaluationCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SelectiveRerenderReader()
        .id(DepartureRerenderIDs.reader)
      DepartureRerenderPane()
      DepartureRerenderLandingField()
      StableEvaluationProbe(counter: stableCounter)
        .id(DepartureRerenderIDs.stable)
    }
  }
}

// MARK: - Scroll-reveal fixture

private struct ScrollRerenderRoot: View {
  let stableCounter: EvaluationCounter

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      StableEvaluationProbe(counter: stableCounter)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Button("above-fold field") {}
          ForEach(0..<30, id: \.self) { index in
            Text("filler row \(index)")
          }
          Button("below-fold field") {}
        }
      }
    }
  }
}
