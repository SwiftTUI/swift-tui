import SwiftTUIGraph
import Testing

@_spi(Testing) import SwiftTUITestSupport

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Stage-0 pin for the coalesced focus-flip + scroll-write selective seam
// (docs/plans/2026-08-12-004-focus-move-narrowing-default-flip-plan.md in the
// org root): one frame carries BOTH a Tab focus flip onto a ScrollView and
// that scroll's internally managed offset write. The production twin is
// `InteractiveRuntimeTests/scrollViewWithoutExplicitPositionHandlesKeyboardScrolling`
// under `SWIFTTUI_FOCUS_MOVE_NARROWING=1`.
//
// Diagnosed mechanism (Stage 0): the fixture's `.frame`-wrapped, `.id`-carrying
// ScrollView is a single-child flattening: the wrapper's apply absorbs the
// authored scroll node's identity entry, and `flattenedStateOwnerNodeIDByIdentity`
// keeps authoring-host resolution landing the scroll's `@State` on the AUTHORED
// node. The flag-off dispatch backstop root-sweeps the frame (a set-equality
// accident — the offset-write's reader is already pending from the raw focus
// enqueue), and the full root re-run reaches the scroll through the wrapper,
// correctly re-hosting on the authored owner. Flag-on, the frame runs
// selectively with `{Button, Scroll}` and the frontier evaluator for the
// absorbed `/Scroll` identity re-runs the scroll body hosted on the WRAPPER
// (fresh state slot: the offset write is lost) and BELOW the `.frame(10x3)`
// modifier (unconstrained viewport: clip and indicators lost, content fits).
@Suite("KeyboardScrollCoalescedFramePin", .serialized)
@MainActor
struct KeyboardScrollCoalescedFramePinTests {
  @Test("Flag-off: the dispatch backstop's root sweep masks the coalesced frame")
  func legacyBackstopMasksCoalescedFrame() async throws {
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled = false
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }
    let harness = try KeyboardScrollPinHarness()
    defer { harness.tearDownTrace() }

    let observation = try await harness.tabThenArrowDown()

    // Behavior: the coalesced frame renders the scrolled, clipped viewport,
    // and the registry holds the scrolled offset on the authored owner.
    #expect(harness.focusedIdentity == harness.scrollIdentity)
    #expect(harness.scrollOffsetY == 1)
    #expect(!harness.surfaceText.contains("Key 0"))
    #expect(harness.surfaceText.contains("Key 1"))
    #expect(harness.surfaceText.contains("Key 3"))
    #expect(!harness.surfaceText.contains("Key 4"))

    // Stage 2 (landed): the dispatch backstop compares the scheduler's
    // monotonic invalidation-request GENERATION, so the scroll dispatch's own
    // offset-write request keeps the backstop quiet even though the written
    // identity was already pending from the raw focus-move enqueue (the
    // pending-SET equality misfired a root sweep here, and that sweep was
    // what masked the Stage-1 seam). The coalesced frame now runs selectively
    // in BOTH flag states — plan formed, frontier = the covering `/content`
    // target, recorded at 20 computed vs the sweep's 22–29 — and must stay
    // correct without the sweep. Update the recorded value only with
    // evidence (a trace attribution).
    #expect(observation.maxResolvedNodesComputed <= 20)
  }

  @Test("Flag-on: the coalesced selective frame must render the scrolled viewport")
  func coalescedSelectiveFrameRendersScrolledViewport() async throws {
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled = true
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }
    let harness = try KeyboardScrollPinHarness()
    defer { harness.tearDownTrace() }

    _ = try await harness.tabThenArrowDown()

    // The focus flip itself lands either way.
    #expect(harness.focusedIdentity == harness.scrollIdentity)

    // Stage 1 (landed): the planner's stitchable-target walk lifts past
    // collapse-absorbing links (`resolvedIdentity != identity`), so the
    // frontier evaluator re-runs the enclosing wrapper — the `.frame`
    // viewport survives and the offset stays on the authored state owner.
    // Before the lift, this frame re-ran the wrapper's CONTENT closure below
    // the modifier: fresh state slot (the just-written offset read back 0),
    // no clip, no indicators, every fixture row drawn.
    #expect(harness.scrollOffsetY == 1)
    #expect(!harness.surfaceText.contains("Key 0"))
    #expect(harness.surfaceText.contains("Key 1"))
    #expect(harness.surfaceText.contains("Key 3"))
    #expect(!harness.surfaceText.contains("Key 4"))
  }
}

/// One drained interaction's frame observations.
private struct KeyboardScrollObservation {
  var maxResolvedNodesComputed = 0
}

@MainActor
private final class KeyboardScrollPinHarness {
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, KeyboardScrollPinRoot>
  private let scheduler: FrameScheduler
  private let diagnosticsRecorder: KeyboardScrollResolveWorkRecorder
  private var renderedFrames = 0
  private let previousTraceEnabled: Bool

  let scrollIdentity = testIdentity("ImplicitKeyboardScrollFixture", "Scroll")

  init() throws {
    let terminalSize = CellSize(width: 20, height: 8)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("ImplicitKeyboardScrollFixture")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: KeyboardScrollPinInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in KeyboardScrollPinRoot() }
    )
    // Production wiring: the tracker's move notifications go through the
    // chrome-only/inert-slot invalidation filter, exactly as `run()` installs
    // it — the pin measures the production dispatch path.
    runLoop.installFocusTrackerInvalidator()
    let diagnosticsRecorder = KeyboardScrollResolveWorkRecorder()
    runLoop.frameSink = diagnosticsRecorder
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler
    self.diagnosticsRecorder = diagnosticsRecorder

    previousTraceEnabled = ReuseDenialTrace.isEnabled
    ReuseDenialTrace.reset()
    ReuseDenialTrace.isEnabled = true

    scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  func tearDownTrace() {
    ReuseDenialTrace.isEnabled = previousTraceEnabled
    ReuseDenialTrace.reset()
  }

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var surfaceText: String {
    terminal.frames.last ?? ""
  }

  /// The registry-held vertical offset for the fixture's scroll view.
  var scrollOffsetY: Int? {
    runLoop.runtimeRegistrations.scrollPositionRegistry?.snapshot()
      .first(where: { $0.identity == scrollIdentity })
      .map { $0.currentOffset().y }
  }

  /// Dispatches Tab then ArrowDown WITHOUT draining between them, so the
  /// focus flip and the scroll-offset write coalesce into one frame — the
  /// exact shape the terminal input harness produces for batched input bytes.
  func tabThenArrowDown() async throws -> KeyboardScrollObservation {
    diagnosticsRecorder.reset()
    _ = runLoop.handleKeyPress(KeyPress(.tab, modifiers: []))
    _ = runLoop.handleKeyPress(KeyPress(.arrowDown, modifiers: []))
    try await drain()
    var observation = KeyboardScrollObservation()
    observation.maxResolvedNodesComputed =
      diagnosticsRecorder.resolvedNodesComputedPerFrame.max() ?? 0
    return observation
  }

  private func drain() async throws {
    var localRenderedFrames = renderedFrames
    defer { renderedFrames = localRenderedFrames }
    var iterations = 0
    while scheduler.hasPendingFrame(at: .now()) && iterations < 12 {
      // Synchronous drain on purpose: the reuse trace's counters are
      // process-global (F119), and the async tail's chunked resolve suspends
      // mid-pass — a concurrently running test's `beginFrame` would dump and
      // reset a partially accumulated histogram.
      try runLoop.renderPendingFrames(renderedFrames: &localRenderedFrames)
      iterations += 1
    }
  }
}

/// Captures each committed frame's `resolvedNodesComputed`.
@MainActor
private final class KeyboardScrollResolveWorkRecorder: FrameDiagnosticSink {
  private(set) var resolvedNodesComputedPerFrame: [Int] = []

  func record(_ sample: RuntimeFrameSample) {
    guard case .committed(let committed) = sample else {
      return
    }
    resolvedNodesComputedPerFrame.append(
      committed.diagnostics.work.resolvedNodesComputed
    )
  }

  func reset() {
    resolvedNodesComputedPerFrame.removeAll()
  }
}

/// The failing production test's fixture, verbatim: a focusable Button above a
/// keyboard-scrollable ScrollView whose viewport shows 3 of 6 rows.
private struct KeyboardScrollPinRoot: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Focus") {}
        .id(testIdentity("ImplicitKeyboardScrollFixture", "Button"))

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<6) { index in
            Text("Key \(index)")
          }
        }
      }
      .id(testIdentity("ImplicitKeyboardScrollFixture", "Scroll"))
      .frame(width: 10, height: 3, alignment: .topLeading)
    }
    .frame(width: 20, height: 8, alignment: .topLeading)
  }
}

private final class KeyboardScrollPinInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
