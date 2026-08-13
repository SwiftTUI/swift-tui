import SwiftTUIGraph
import Testing

@_spi(Testing) import SwiftTUITestSupport

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Stage-0 pin for the palette CLOSE cone
// (docs/plans/2026-08-12-001-focus-invalidation-narrowing-plan.md in the org
// root): a deterministic open/close cycle over a static background grid,
// recording the dismissal frames' resolve work and the reuse trace's
// `invalidation-conflict` count. The perf twin is
// `termui-perf run --scenario sheet-open-latency` (close class: 195 computed /
// conflict=177 at 176 rows). These tests pin the same shape at test scale so
// Stages 1-2 have a measurable, suite-visible flip.
@Suite("PaletteCloseFramePin", .serialized)
@MainActor
struct PaletteCloseFramePinTests {
  private static let rowCount = 24

  @Test("Palette close-frame resolve work and conflict count match the recorded baseline")
  func closeFrameShapeMatchesRecordedBaseline() async throws {
    // This test pins the legacy (narrowing-off) close shape regardless of the
    // process environment; the flag-on shape is pinned separately below.
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled = false
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }
    let harness = try PaletteClosePinHarness(rowCount: Self.rowCount)
    defer { harness.tearDownTrace() }

    let open = try await harness.openPalette()
    let close = try await harness.closePalette()

    // The OPEN is O(overlay): the background is untouched, so its resolve
    // work must not scale with the grid. (~21 nodes today; the bound leaves
    // room for chrome drift without letting a background re-resolve hide.)
    #expect(open.maxResolvedNodesComputed < 60)

    // Recorded CLOSE baseline (the Stage-0 pin). The dismissal cycle's most
    // expensive pass recomputes the grid's row containers: the eager
    // focus-restore rerender carries the departed overlay leaf plus the
    // restored trigger in its invalidation set, and the reuse door denies one
    // node per background row (+1) as `invalidation-conflict`. Update these
    // recorded values ONLY with evidence (a perf run + trace attribution);
    // Stages 1-2 of the plan flip them to the open's shape.
    #expect(close.maxInvalidationConflicts == Self.rowCount + 1)
    #expect(close.maxResolvedNodesComputed > open.maxResolvedNodesComputed)

    // After the palette closes, focus must land back on the control that
    // opened it (the SwiftUI-expected dismissal behavior; Stage-1 acceptance).
    let focusedPath = harness.focusedIdentity?.path ?? "nil"
    #expect(focusedPath.hasSuffix("VStack[0]"), "focus restored to \(focusedPath)")
  }

  @Test("Focus-move narrowing collapses the palette close to the open's shape")
  func closeFrameCollapsesUnderFocusMoveNarrowing() async throws {
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled = true
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }
    let harness = try PaletteClosePinHarness(rowCount: Self.rowCount)
    defer { harness.tearDownTrace() }

    let open = try await harness.openPalette()
    let close = try await harness.closePalette()

    // With the tracker's move endpoints re-validated at frame time, the
    // departed overlay identities contribute nothing and the dismissal cycle
    // stops scaling with the background: no row-grid conflict denials, and
    // resolve work in the open's O(overlay) band.
    #expect(close.maxInvalidationConflicts <= 2)
    #expect(close.maxResolvedNodesComputed <= open.maxResolvedNodesComputed + 8)

    // The narrowing must not change dismissal behavior: the palette closed
    // (asserted by `closePalette`) and focus is back on the trigger control.
    let focusedPath = harness.focusedIdentity?.path ?? "nil"
    #expect(focusedPath.hasSuffix("VStack[0]"), "focus restored to \(focusedPath)")
  }

  @Test("Default configuration: palette close resolve work matches the open's shape")
  func closeFrameResolveWorkMatchesOpenTarget() async throws {
    // Pins the DEFAULT configuration's close shape. Default-on since the flip
    // (plan 2026-08-12-004 Stage 3); the legacy baseline test above stays as
    // the explicit latch-off regression pin for the kill-switch path.
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled =
      FeatureGate.focusMoveInvalidationNarrowing.defaultIsEnabled
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }
    let harness = try PaletteClosePinHarness(rowCount: Self.rowCount)
    defer { harness.tearDownTrace() }

    let open = try await harness.openPalette()
    let close = try await harness.closePalette()

    // The -001 plan's acceptance, standing since the default flip: the
    // close-frame class matches the open's shape (no conflict cone, resolve
    // work independent of the background size).
    #expect(close.maxInvalidationConflicts == 0)
    #expect(close.maxResolvedNodesComputed <= open.maxResolvedNodesComputed + 8)
  }
}

/// One drained interaction's frame observations: the maximum per-frame resolve
/// work and the maximum per-frame `invalidation-conflict` reuse-trace count
/// across every frame the interaction produced (the dismissal cycle spans a
/// teardown pass, the eager focus-restore rerender, and async re-runs -- the
/// pin cares about the most expensive pass).
private struct PaletteCycleObservation {
  var maxResolvedNodesComputed = 0
  var maxInvalidationConflicts = 0
}

@MainActor
private final class PaletteClosePinHarness {
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, PaletteClosePinRoot>
  private let scheduler: FrameScheduler
  private let diagnosticsRecorder: ResolveWorkRecorder
  private var renderedFrames = 0
  private var conflictCountsByFrame: [UInt64: Int] = [:]
  private let previousTraceEnabled: Bool

  init(rowCount: Int) throws {
    let terminalSize = CellSize(width: 72, height: 40)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("PaletteClosePinRoot")
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: PaletteClosePinInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in PaletteClosePinRoot(rowCount: rowCount) }
    )
    // Production wiring: the tracker's move notifications go through the
    // chrome-only/inert-slot invalidation filter, exactly as `run()` installs
    // it -- the pin measures the production close path, not a test shortcut.
    runLoop.installFocusTrackerInvalidator()
    let diagnosticsRecorder = ResolveWorkRecorder()
    runLoop.frameSink = diagnosticsRecorder
    self.terminal = terminal
    self.runLoop = runLoop
    self.scheduler = scheduler
    self.diagnosticsRecorder = diagnosticsRecorder

    previousTraceEnabled = ReuseDenialTrace.isEnabled
    ReuseDenialTrace.reset()
    ReuseDenialTrace.isEnabled = true
    ReuseDenialTrace.onFrameSummary = { [weak self] frameID, reasonCounts in
      self?.conflictCountsByFrame[frameID] = reasonCounts["invalidation-conflict"] ?? 0
    }

    scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  func tearDownTrace() {
    ReuseDenialTrace.onFrameSummary = nil
    ReuseDenialTrace.isEnabled = previousTraceEnabled
    ReuseDenialTrace.reset()
  }

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var surfaceText: String {
    terminal.frames.last ?? ""
  }

  func openPalette() async throws -> PaletteCycleObservation {
    // The trigger button is the only interaction region in the base tree.
    let observation = try await observing {
      try await click { !$0.identity.path.contains("PortalHost") }
    }
    #expect(surfaceText.contains("Sheet body"))
    return observation
  }

  func closePalette() async throws -> PaletteCycleObservation {
    // The palette contributes several portal-hosted regions (chrome,
    // backdrop); the authored close button is the deepest one.
    let observation = try await observing {
      let portalRegions = runLoop.latestSemanticSnapshot.interactionRegions
        .filter { $0.identity.path.contains("PortalHost") }
      let deepest = portalRegions.max(by: {
        $0.identity.components.count < $1.identity.components.count
      })
      try await click { $0.identity == deepest?.identity }
    }
    #expect(!surfaceText.contains("Sheet body"))
    return observation
  }

  /// Runs one interaction and reduces the frames it produced (including the
  /// final settle frame, whose trace histogram only dumps at the NEXT
  /// `beginFrame`) into a ``PaletteCycleObservation``.
  private func observing(
    _ interaction: () async throws -> Void
  ) async throws -> PaletteCycleObservation {
    diagnosticsRecorder.reset()
    conflictCountsByFrame.removeAll()
    try await interaction()
    // The last frame's trace counters have not been dumped yet -- fold the
    // still-accumulating histogram in as that frame's summary.
    let residualConflicts = ReuseDenialTrace.reasonCounts["invalidation-conflict"] ?? 0
    var observation = PaletteCycleObservation()
    observation.maxResolvedNodesComputed =
      diagnosticsRecorder.resolvedNodesComputedPerFrame.max() ?? 0
    observation.maxInvalidationConflicts = max(
      conflictCountsByFrame.values.max() ?? 0,
      residualConflicts
    )
    return observation
  }

  /// Clicks the center of the interaction region matching `predicate`. The
  /// fixture keeps the perf scenario's exact structural identity scheme (no
  /// test-only `.id`s), so regions are selected by identity namespace rather
  /// than by an authored identity.
  private func click(
    region predicate: (InteractionRegion) -> Bool
  ) async throws {
    let matched = runLoop.latestSemanticSnapshot.interactionRegions.first(
      where: predicate
    )
    let region = try #require(
      matched,
      """
      no matching interaction region; regions: \
      \(runLoop.latestSemanticSnapshot.interactionRegions.map {
        "\($0.identity.path)@\($0.rect)"
      }.joined(separator: ", "))
      """
    )
    let center = PointerLocation.cellFallback(
      CellPoint(
        x: region.rect.origin.x + region.rect.size.width / 2,
        y: region.rect.origin.y + region.rect.size.height / 2
      )
    )
    runLoop.handleMouseDown(MouseButton.primary, location: center)
    runLoop.handleMouseUp(MouseButton.primary, location: center)
    try await drain()
  }

  private func drain() async throws {
    var localRenderedFrames = renderedFrames
    defer { renderedFrames = localRenderedFrames }
    var iterations = 0
    while scheduler.hasPendingFrame(at: .now()) && iterations < 12 {
      // Synchronous drain on purpose: the reuse trace's counters are
      // process-global (F119), and the async tail's chunked resolve suspends
      // mid-pass -- a concurrently running test's `beginFrame` would dump and
      // reset a partially accumulated conflict count. The sync path resolves
      // without suspension, so each frame's histogram stays whole.
      try runLoop.renderPendingFrames(renderedFrames: &localRenderedFrames)
      iterations += 1
    }
  }
}

/// Captures each committed frame's `resolvedNodesComputed`. Main-actor
/// isolation makes the class implicitly `Sendable` for the sink protocol.
@MainActor
private final class ResolveWorkRecorder: FrameDiagnosticSink {
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

/// The perf fixture's shape at test scale: a trigger button above a static
/// grid, wrapped in a panel, presenting a command palette
/// (`SheetOpenLatencyScenario` is the release-lane twin).
private struct PaletteClosePinRoot: View {
  let rowCount: Int
  @State private var paletteShown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("open palette") {
        paletteShown = true
      }
      ForEach(Array(0..<rowCount), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<4), id: \.self) { column in
            Text("bg r\(row) c\(column)")
          }
        }
      }
    }
    .padding(1)
    .panel(id: "palette-close-pin-host")
    .paletteSheet("Palette", isPresented: $paletteShown) { _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close sheet") {
          paletteShown = false
        }
      }
    }
  }
}

private final class PaletteClosePinInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
