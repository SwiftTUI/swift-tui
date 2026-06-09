@_spi(Runners) import SwiftTUI

/// Measures the cost of OPENING and CLOSING a sheet over a large, static
/// background tree.
///
/// Opening a presentation inserts an `OverlayStack` wrapper, which changes the
/// surface-topology signature and (at the current pin) forces the frame tail to
/// re-raster the entire surface from scratch — including the unchanged
/// background — on both the open and the close transition frame. The sheet here
/// uses the default `backdropOpacity: 0`, so the background is visually
/// identical while the sheet is open; any full-surface re-raster is therefore
/// pure waste.
///
/// The background grid row count is fixed by default (smoke-test friendly) but
/// can be swept with `TERMUI_PERF_SHEET_TREE_ROWS` to show whether the
/// transition-frame `raster_ms`, `present_cells`, and `damage_rows` scale with
/// the background/surface size.
///
/// Diagnostic columns to read in `frames.tsv` for the open/close frames:
///   - `damage_rows`   — prints `full` on a full-surface repaint, a small
///     integer once damage is bounded.
///   - `raster_ms`     — raster-phase CPU time (fresh full raster vs incremental).
///   - `present_cells` / `present_lines` — terminal write cost.
///
/// A/B the `additiveOverlayBoundedDamage` prototype by running this scenario
/// with and without `SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE=1`.
public struct SheetOpenLatencyScenario: PerfScenario {
  public let name: PerfScenarioName = .sheetOpenLatency
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 60)
  public let scriptedEvents = ["toggle a command palette open/closed over a large static background"]
  public let visualMarkers = ["open sheet"]
  public let settlingDescription = "first frame that shows the open-sheet trigger"

  private static let defaultRowCount = 44
  private static let columnCount = 4
  private static let cycleCount = 4

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    let overlayKind = Self.resolvedOverlayKind()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfSheetLatencyProbeView(
        rowCount: rowCount,
        columnCount: Self.columnCount,
        overlayKind: overlayKind
      )
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "open sheet")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var firstOpenFrame = lastFrame

      for cycle in 1...Self.cycleCount {
        // OPEN: click the background trigger; wait for the sheet body to appear.
        let openCell = try driver.cell(containing: "open sheet")
        driver.sendClick(at: openCell)
        let opened = try await driver.waitForFrame(
          containing: "Sheet body",
          afterFrame: lastFrame
        )
        if cycle == 1 {
          firstOpenFrame = opened.frameNumber
        }
        lastFrame = opened.frameNumber

        // CLOSE: click the sheet's own close button; wait for the first frame
        // after it that no longer shows the sheet body.
        let closeCell = try driver.cell(containing: "Close sheet")
        driver.sendClick(at: closeCell)
        let closed = try await Self.waitForFrameNotContaining(
          "Sheet body",
          afterFrame: lastFrame,
          in: driver
        )
        lastFrame = closed.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "sheet-open-latency",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "Sheet body",
          firstMatchingFrame: firstOpenFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  @MainActor
  private static func waitForFrameNotContaining(
    _ marker: String,
    afterFrame frameNumber: Int,
    in driver: PerfScenarioDriver,
    timeout: Duration = .seconds(2)
  ) async throws -> PerfPresentedFrame {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if let frame = driver.terminalHost.presentedFrames.last(where: {
        $0.frameNumber > frameNumber && !$0.text.contains(marker)
      }) {
        return frame
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw PerfScenarioError.markerTimedOut("!\(marker)")
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_SHEET_TREE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }

  private static func resolvedOverlayKind() -> OverlayKind {
    // `palette` (dropdown, fill-available — the user's reported case) is the
    // default; `popover` is a compact intrinsic-sized overlay that exercises the
    // regime where incremental raster reuse wins large.
    environmentValue("TERMUI_PERF_SHEET_OVERLAY") == "popover" ? .popover : .palette
  }
}

enum OverlayKind: Sendable {
  case palette
  case popover
}

private struct PerfSheetLatencyProbeView: View {
  let rowCount: Int
  let columnCount: Int
  let overlayKind: OverlayKind
  @State private var sheetPresented = false

  var body: some View {
    if overlayKind == .popover {
      background
        // A compact popover: menu chrome, intrinsic-sized. Its footprint is a
        // few rows, so most of the background is reuse-eligible on open.
        .popover(isPresented: $sheetPresented) {
          overlayContent
        }
    } else {
      background
        // A command palette: dropdown chrome (a top strip), `backdropOpacity: 0`.
        .panel(id: "palette-host")
        .paletteSheet("Palette", isPresented: $sheetPresented) { _ in
          overlayContent
        }
    }
  }

  private var background: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("open sheet") {
        sheetPresented = true
      }
      // Large, static background. It is disjoint from the overlay's `@State`, so
      // it is reuse-eligible through resolve/measure/place and should NOT need a
      // re-raster when the overlay opens over it.
      ForEach(Array(0..<rowCount), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<columnCount), id: \.self) { column in
            Text("bg r\(row) c\(column)")
          }
        }
      }
    }
    .padding(1)
  }

  private var overlayContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Sheet body")
      Button("Close sheet") {
        sheetPresented = false
      }
    }
  }
}
