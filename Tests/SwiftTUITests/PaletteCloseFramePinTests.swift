import SwiftTUIGraph
import Testing

@_spi(Testing) import SwiftTUITestSupport

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Pin for the palette CLOSE cone
// (docs/plans/2026-08-12-001-focus-invalidation-narrowing-plan.md in the org
// root): a deterministic open/close cycle over a static background grid,
// recording the dismissal frames' resolve work and the reuse trace's
// `invalidation-conflict` count. The perf twin is
// `termui-perf run --scenario sheet-open-latency` (close class: 195 computed /
// conflict=177 at 176 rows).
//
// These tests assert the plan's INVARIANT — close-frame work is independent of
// the background size — by running the same cycle over two grids and comparing.
// They previously pinned recorded CONSTANTS (`== rowCount + 1`, `<= 2`, `== 0`),
// which were calibrated against a palette whose body was a caller-supplied
// single `Text`. Control-style A5 made the palette contentless and the
// framework renders its own body (filter field, divider, match list), so every
// constant moved while the invariant held: at 24 and 48 background rows the
// close observations are identical (conflicts 15 latched-off / 10 narrowed,
// resolve 10, both row counts). A/B evidence that this is body size and not a
// focus-seam regression: the same harness driving a plain `.sheet` with a
// trivial `Text` body over the same Escape close still satisfies the old
// constants. Asserting the invariant instead of the constant is both the
// stronger claim and the one that survives a body change.
@Suite("PaletteCloseFramePin", .serialized)
@MainActor
struct PaletteCloseFramePinTests {
  private static let rowCount = 24
  /// The comparison grid. Twice the rows: anything the close cone does that
  /// scales with the background shows up as a difference between the two.
  private static let scaledRowCount = 48

  @Test("Latched-off palette close work is independent of the background size")
  func closeFrameShapeIsBackgroundIndependentWithNarrowingOff() async throws {
    // Pins the kill-switch path regardless of the process environment; the
    // flag-on shape is pinned separately below.
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled = false
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }

    let small = try await measureCycle(rowCount: Self.rowCount)
    let large = try await measureCycle(rowCount: Self.scaledRowCount)

    // The OPEN is O(overlay): the background is untouched, so its resolve work
    // must not scale with the grid.
    #expect(small.open.maxResolvedNodesComputed < 60)
    #expect(large.open.maxResolvedNodesComputed == small.open.maxResolvedNodesComputed)

    // The CLOSE must not scale with the background either, even latched off.
    #expect(large.close.maxInvalidationConflicts == small.close.maxInvalidationConflicts)
    #expect(large.close.maxResolvedNodesComputed == small.close.maxResolvedNodesComputed)

    // After the palette closes, focus must land back on the control that
    // opened it (the SwiftUI-expected dismissal behavior).
    #expect(
      small.focusedPath.hasSuffix("VStack[0]"),
      "focus restored to \(small.focusedPath)"
    )
  }

  @Test("Focus-move narrowing lowers the palette close cone and keeps it background-independent")
  func closeFrameCollapsesUnderFocusMoveNarrowing() async throws {
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }

    FocusMoveInvalidationNarrowing.isEnabled = false
    let latchedOff = try await measureCycle(rowCount: Self.rowCount)

    FocusMoveInvalidationNarrowing.isEnabled = true
    let small = try await measureCycle(rowCount: Self.rowCount)
    let large = try await measureCycle(rowCount: Self.scaledRowCount)

    // With the tracker's move endpoints re-validated at frame time, the
    // departed overlay identities contribute nothing, so the narrowed close
    // denies strictly fewer nodes than the latched-off one. Measured against
    // the control arm in the same run rather than a recorded constant, so a
    // body change moves both arms together instead of failing the pin.
    #expect(
      small.close.maxInvalidationConflicts < latchedOff.close.maxInvalidationConflicts,
      """
      narrowing must lower the close cone: \
      \(small.close.maxInvalidationConflicts) \
      vs latched-off \(latchedOff.close.maxInvalidationConflicts)
      """
    )
    #expect(large.close.maxInvalidationConflicts == small.close.maxInvalidationConflicts)
    #expect(large.close.maxResolvedNodesComputed == small.close.maxResolvedNodesComputed)

    // The narrowing must not change dismissal behavior: the palette closed
    // (asserted by `closePalette`) and focus is back on the trigger control.
    #expect(
      small.focusedPath.hasSuffix("VStack[0]"),
      "focus restored to \(small.focusedPath)"
    )
  }

  @Test("Default configuration: palette close resolve work matches the open's shape")
  func closeFrameResolveWorkMatchesOpenTarget() async throws {
    // Pins the DEFAULT configuration's close shape. Default-on since the flip
    // (plan 2026-08-12-004 Stage 3); the latch-off path is pinned above.
    let wasEnabled = FocusMoveInvalidationNarrowing.isEnabled
    FocusMoveInvalidationNarrowing.isEnabled =
      FeatureGate.focusMoveInvalidationNarrowing.defaultIsEnabled
    defer { FocusMoveInvalidationNarrowing.isEnabled = wasEnabled }

    let small = try await measureCycle(rowCount: Self.rowCount)
    let large = try await measureCycle(rowCount: Self.scaledRowCount)

    // The -001 plan's acceptance, standing since the default flip: the
    // close-frame class matches the open's shape — resolve work in the open's
    // O(overlay) band, and nothing about the close scaling with the background.
    #expect(small.close.maxResolvedNodesComputed <= small.open.maxResolvedNodesComputed + 8)
    #expect(large.close.maxInvalidationConflicts == small.close.maxInvalidationConflicts)
    #expect(large.close.maxResolvedNodesComputed == small.close.maxResolvedNodesComputed)
  }

  /// One open/close cycle over a grid of `rowCount` rows.
  private func measureCycle(rowCount: Int) async throws -> PaletteCycleMeasurement {
    let harness = try PaletteClosePinHarness(rowCount: rowCount)
    defer { harness.tearDownTrace() }
    let open = try await harness.openPalette()
    let close = try await harness.closePalette()
    return PaletteCycleMeasurement(
      open: open,
      close: close,
      focusedPath: harness.focusedIdentity?.path ?? "nil"
    )
  }
}

/// One measured open/close cycle plus where focus landed afterwards.
private struct PaletteCycleMeasurement {
  var open: PaletteCycleObservation
  var close: PaletteCycleObservation
  var focusedPath: String
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
    // A contentless palette renders the framework's own body, so the presence
    // check is that body's empty-scope line (this fixture contributes no
    // commands) rather than a caller-supplied string. The filter field is
    // focused on open and paints a cursor, not its placeholder.
    #expect(
      surfaceText.contains("No commands in the current scope."),
      "palette did not open:\n\(surfaceText)"
    )
    return observation
  }

  func closePalette() async throws -> PaletteCycleObservation {
    // Escape is the framework's dismissal. Before A5 this clicked the deepest
    // portal-hosted region, which was the caller's authored close button; a
    // contentless palette has no such button, and the deepest region is now a
    // command row (or the filter field), which would not dismiss at all.
    let observation = try await observing {
      _ = runLoop.handleKeyPress(KeyPress(.escape))
      try await drain()
    }
    #expect(
      !surfaceText.contains("No commands in the current scope."),
      "palette did not close:\n\(surfaceText)"
    )
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
    .paletteSheet("Palette", isPresented: $paletteShown)
  }
}

private final class PaletteClosePinInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
