@_spi(Runners) import SwiftTUI

/// Stage-3 evidence for memoized-body reuse via an `Equatable` boundary.
///
/// A root `@State` counter changes on every click, invalidating the root and
/// forcing its whole reached subtree to be re-walked. A large, read-free grid
/// sits beside the counter as a descendant of that invalidated root — exactly
/// the population the memo gate can reuse.
///
/// The grid is presented one of two ways, selected by `TERMUI_PERF_MEMO_BOUNDARY`:
///
/// - `equatable` (default): the grid is an author `View & Equatable` struct
///   (`EquatableGrid`). The memo gate compares the boundary with a single `==`
///   over its `rows`/`cols` and reuses the whole subtree — including the inner
///   `ForEach` closures the structural comparator would otherwise `.block`.
/// - `plain`: the grid is a raw `VStack { ForEach … }` with no author boundary.
///   The gate must compare the framework container value structurally; the
///   `ForEach` body closure is `.blocked`, so the subtree is NOT reused and
///   recomputes every frame.
///
/// Run the A/B as: gate off (baseline recompute) vs gate on, in each mode. The
/// `equatable` mode should drop `resolve_ms` well below the gate-off baseline
/// (cheap `==` + whole-subtree reuse); the `plain` mode should stay at/above
/// baseline (blocked → recompute, plus the comparator's wasted work) — the
/// Stage-2 finding in miniature. Grid size is `TERMUI_PERF_MEMO_GRID_ROWS`
/// (default 18) × 8 columns.
public struct MemoEquatableBoundaryScenario: PerfScenario {
  public let name: PerfScenarioName = .memoEquatableBoundary
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 48)
  public let scriptedEvents = ["click inc; invalidate the root above a large Equatable grid"]
  public let visualMarkers = ["count 0"]
  public let settlingDescription = "first frame that shows count 0"

  private static let defaultRowCount = 18
  private static let columnCount = 8
  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    let useEquatableBoundary = Self.resolvedUseEquatableBoundary()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      MemoBoundaryProbeView(
        rowCount: rowCount,
        columnCount: Self.columnCount,
        useEquatableBoundary: useEquatableBoundary
      )
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "count 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      for click in 1...Self.clickCount {
        let cell = try driver.cell(containing: "inc")
        driver.sendClick(at: cell)
        let matching = try await driver.waitForFrame(
          containing: "count \(click)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
      }
      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "memo-equatable-boundary",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "count \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_MEMO_GRID_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }

  private static func resolvedUseEquatableBoundary() -> Bool {
    guard let raw = environmentValue("TERMUI_PERF_MEMO_BOUNDARY") else {
      return true
    }
    return raw != "plain"
  }
}

private struct MemoBoundaryProbeView: View {
  let rowCount: Int
  let columnCount: Int
  let useEquatableBoundary: Bool

  // State at the root: a click invalidates THIS node, forcing the whole reached
  // subtree (including the grid below) to be re-walked — so the grid is a
  // descendant of an invalidated ancestor, the memo gate's target population.
  @State private var counter = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(counter)")
      Button("inc") {
        counter += 1
      }
      // The large, read-free grid. Unchanged across clicks, so it is reuse-
      // eligible; whether it is actually reused depends on the boundary form.
      if useEquatableBoundary {
        EquatableGrid(rows: rowCount, columns: columnCount)
      } else {
        PlainGrid(rows: rowCount, columns: columnCount)
      }
    }
    .padding(1)
  }
}

/// Author `View & Equatable` boundary: the memo gate compares it by `==` over
/// `rows`/`columns` and reuses the whole subtree (the inner `ForEach` closures
/// included) without descending. Read-free body, so it passes the gate's
/// no-recorded-dependencies guard.
private struct EquatableGrid: View, Equatable {
  let rows: Int
  let columns: Int

  var body: some View {
    GridBody(rows: rows, columns: columns)
  }
}

/// The same grid with no author boundary: the gate sees the framework container
/// value and the `ForEach` closure blocks structural comparison, so it is not
/// reused.
private struct PlainGrid: View {
  let rows: Int
  let columns: Int

  var body: some View {
    GridBody(rows: rows, columns: columns)
  }
}

private struct GridBody: View {
  let rows: Int
  let columns: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(0..<rows), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<columns), id: \.self) { column in
            Text("r\(row)c\(column)").border(.separator)
          }
        }
      }
    }
  }
}
