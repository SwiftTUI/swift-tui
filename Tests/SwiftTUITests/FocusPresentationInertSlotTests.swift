@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Focus-presentation-inert slots: a focusable container control (`TabView`)
/// declares that the values it hands its content slot cannot vary with its own
/// focus/press presentation, so a focus move onto/off the container no longer
/// pulls the whole content subtree into the retained-reuse suppression cone —
/// only the container's chrome (the tab strip) recomputes.
///
/// The soundness boundary these tests pin: the exemption is (member, declarer)
/// paired. Only the declaring control's own scope membership skips descendant
/// matching below its slot; a cascade from any OTHER ancestor member (whose
/// recompute may change the authored tabs the promise is conditioned on) keeps
/// full-cone suppression. See `EvaluationState.focusPresentationInertSlotIdentities`.
@MainActor
struct FocusPresentationInertSlotScopeTests {
  private let member = testIdentity("Scope", "Control")
  private let slot = testIdentity("Scope", "Control", "Body", "ContentSlot")
  private let contentChild = testIdentity(
    "Scope", "Control", "Body", "ContentSlot", "Payload", "Leaf"
  )
  private let chromeChild = testIdentity("Scope", "Control", "Body", "Bar", "Item")
  private let ancestor = testIdentity("Scope")

  private func exemptingBelowSlot(
    _ member: Identity,
    _ identity: Identity
  ) -> Bool {
    member == self.member && identity.isDescendant(of: slot)
  }

  @Test("focus member matches self, ancestors, and descendants without an exemption")
  func focusMemberConservativeMatching() {
    var scope = RetainedReuseSuppressionScope()
    scope.insertFocusPresentationMember(member)
    #expect(scope.suppresses(identity: member))
    #expect(scope.suppresses(identity: ancestor))
    #expect(scope.suppresses(identity: chromeChild))
    #expect(scope.suppresses(identity: contentChild))
    #expect(!scope.suppresses(identity: testIdentity("Elsewhere")))
  }

  @Test("a declared inert slot exempts descendant-only matches of the declaring member")
  func inertSlotExemptsDeclaringMemberDescendants() {
    var scope = RetainedReuseSuppressionScope()
    scope.insertFocusPresentationMember(member)
    // Chrome outside the slot stays in the cone; the slot subtree is exempt.
    #expect(scope.suppresses(identity: chromeChild, isFocusPresentationDescendantExempt: exemptingBelowSlot))
    #expect(!scope.suppresses(identity: contentChild, isFocusPresentationDescendantExempt: exemptingBelowSlot))
    // Self and ancestor matches never consult the exemption.
    #expect(scope.suppresses(identity: member, isFocusPresentationDescendantExempt: { _, _ in true }))
    #expect(scope.suppresses(identity: ancestor, isFocusPresentationDescendantExempt: { _, _ in true }))
  }

  @Test("one non-exempting matching member keeps the identity suppressed")
  func nonExemptingMemberWins() {
    var scope = RetainedReuseSuppressionScope()
    scope.insertFocusPresentationMember(member)
    // A second member above the slot (an ancestor container) also covers the
    // content child; the exemption is member-paired, so it must not clear it.
    scope.insertFocusPresentationMember(ancestor)
    #expect(scope.suppresses(identity: contentChild, isFocusPresentationDescendantExempt: exemptingBelowSlot))
  }

  @Test("cone members (animation legs) never consult the exemption")
  func coneMembersIgnoreExemption() {
    var scope = RetainedReuseSuppressionScope()
    scope.insert(member)
    #expect(scope.suppresses(identity: contentChild, isFocusPresentationDescendantExempt: { _, _ in true }))
  }

  @Test("focus members alone make the scope non-empty (finite focus/press coverage)")
  func focusMembersCountTowardIsEmpty() {
    var scope = RetainedReuseSuppressionScope()
    #expect(scope.isEmpty)
    scope.insertFocusPresentationMember(member)
    #expect(!scope.isEmpty)
    #expect(!scope.suppressesAll)
  }
}

/// Runtime behavior on the live frame drivers: focus moves onto/off a
/// `TabView`'s strip spare the tab content subtree, while cascades from an
/// ancestor focusable container (not the declaring control) still recompute it.
@MainActor
@Suite(.serialized)
struct FocusPresentationInertSlotRuntimeTests {
  @Test("a focus move off the tab strip spares the tab content subtree")
  func stripFocusMoveSparesContent() throws {
    let harness = try InertSlotHarness(
      rootLabel: "InertSlotSpareRoot"
    ) { counter in
      InertSlotTabRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Drive the moves through the tracker directly: a Tab KEYPRESS dispatched
    // to a focused TabView runs its key handler, whose stored-focus-index
    // state writes invalidate the TabView identity — a pre-existing
    // state-write-axis whole-cone recompute that is exactly the "arrow-key /
    // Tab within the strip" follow-up, and would mask what this test pins
    // (the pure focus-move suppression scope + tracker-invalidation seam).
    let contentIdentity = try #require(harness.focusedIdentity)
    let evaluationsBefore = harness.contentCounter.count

    // Move focus from the content target onto the TabView strip. The arriving
    // member (the TabView identity, whose descendant cone is the whole app)
    // must not recompute the content: its content slot is declared
    // focus-presentation-inert, and the tracker's move notification for it is
    // filtered at the source.
    try harness.moveFocusNext()
    #expect(harness.focusedIdentity != contentIdentity)
    #expect(
      harness.contentCounter.count == evaluationsBefore,
      """
      the tab content probe re-evaluated \
      \(harness.contentCounter.count - evaluationsBefore) time(s) during a \
      content-to-strip focus move; the TabView's inert content slot should \
      have spared it
      """
    )

    // The move back into the content spares it again (only the landing
    // control's own cone recomputes, and the probe sits outside it).
    let evaluationsBeforeReturn = harness.contentCounter.count
    try harness.moveFocusPrevious()
    #expect(harness.focusedIdentity == contentIdentity)
    #expect(harness.contentCounter.count == evaluationsBeforeReturn)
  }

  @Test("a cascade from an ancestor focusable container still recomputes the content")
  func ancestorMemberKeepsContentSuppressed() throws {
    let harness = try InertSlotHarness(
      rootLabel: "InertSlotAncestorRoot"
    ) { counter in
      InertSlotWrappedTabRoot(contentCounter: counter)
    }
    defer { harness.tearDown() }

    // Initial adoption focuses the outer `.focusable()` wrapper — an ancestor
    // of the TabView and its content.
    let wrapperIdentity = try #require(harness.focusedIdentity)
    let evaluationsBefore = harness.contentCounter.count

    // Moving focus off the wrapper puts an ancestor-of-the-declarer into the
    // scope. Its recompute cascade may change the authored tabs, so the
    // (member, declarer) pairing must keep the content in the cone: the probe
    // re-evaluates.
    try harness.press(KeyPress(.tab))
    #expect(harness.focusedIdentity != wrapperIdentity)
    #expect(
      harness.contentCounter.count > evaluationsBefore,
      """
      the tab content probe did not re-evaluate when an ancestor focusable \
      container left the focus path; the inert-slot exemption must apply only \
      to the declaring control's own membership
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

/// Deliberately binding-free and handler-free: a `@FocusState` binding's
/// runtime flip invalidates its authored owner, and a focused control with a
/// key handler that ignores Tab triggers `handleKeyPress`'s root-sweep
/// backstop — both are legitimate pre-existing work that would mask what this
/// fixture measures. Focus-flip visibility inside spared content is pinned by
/// `FocusSyncSelectiveRerenderTests`; here the focus target is a plain
/// focusable text so the only recompute pressure on the probe is the
/// suppression scope.
private struct InertSlotTabContent: View {
  let contentCounter: EvaluationCounter

  var body: some View {
    VStack {
      Text("Content target").focusable()
      ContentEvaluationProbe(counter: contentCounter)
    }
  }
}

private struct InertSlotTabRoot: View {
  let contentCounter: EvaluationCounter
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
      Tab("First", value: 0) {
        InertSlotTabContent(contentCounter: contentCounter)
      }
      Tab("Second", value: 1) {
        Text("second tab")
      }
    }
  }
}

private struct InertSlotWrappedTabRoot: View {
  let contentCounter: EvaluationCounter
  @State private var selection = 0

  var body: some View {
    VStack {
      VStack {
        Text("wrapper")
        TabView(selection: $selection) {
          Tab("First", value: 0) {
            InertSlotTabContent(contentCounter: contentCounter)
          }
        }
      }
      .focusable()
    }
  }
}

// MARK: - Harness

@MainActor
private final class InertSlotHarness<Root: View> {
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
      terminalInputReader: InertSlotInputReader(),
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
    // Drain focus-adoption follow-up frames so tests observe steady state.
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

  func moveFocusNext() throws {
    runLoop.focusTracker.focusNext()
    try settle()
  }

  func moveFocusPrevious() throws {
    runLoop.focusTracker.focusPrevious()
    try settle()
  }
}

private final class InertSlotInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

