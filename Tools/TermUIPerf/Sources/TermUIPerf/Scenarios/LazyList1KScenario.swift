@_spi(Runners) import SwiftTUI

/// F173 vehicle: a direct-data `List` over 1,000 elements by default. The
/// initializer exposes a total indexed source, so finite frames realize only
/// the visible band plus bounded overscan while the selection walk repeatedly
/// shifts that band over an unchanged data source.
///
/// A `sel:<tag>|` mirror line gives the driver a deterministic settle marker
/// for selection moves that is independent of row focus chrome. Row count is
/// `SWIFTTUI_PERF_LAZY_LIST_ROWS`-overridable for scaling probes. The default
/// is 1k because that is the largest scale HEAD can drive today: the Stage-0
/// doubling probe measured total-CPU ratios of 2.39x (500->1k) and 2.89x
/// (1k->2k) — a dominating quadratic term — and a 10k initial frame does not
/// present within 120 seconds. Flipping the default (and name) to 10k is a
/// proposal 2026-07-13-002 Stage-2 acceptance criterion.
public struct LazyList1KScenario: PerfScenario {
  public let name: PerfScenarioName = .lazyList1K
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "click-select and one arrow step over a 1k-row List, then wheel scrolls"
      + " that drive the window to the end of the source"
  ]
  public let visualMarkers = ["lrow 0"]
  public let settlingDescription = "first frame showing the list's first row"
  // Keep headroom for scaling probes that set the row-count override to 10k.
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let defaultRowCount = 1_000

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    let usesEagerBuilder = Self.usesEagerBuilder()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfLazyListView(rowCount: rowCount, usesEagerBuilder: usesEagerBuilder)
    } drive: { driver in
      // Initial render: direct-data source setup plus the first viewport.
      _ = try await driver.waitForFrame(containing: "lrow 0", timeout: .seconds(120))
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var events: [PerfEventRecord] = []

      // Click a visible row: activation writes the selection binding (and
      // focuses the row for the arrow-key leg below).
      let clickDispatch = monotonicSeconds()
      let rowCell = try driver.cell(containing: "lrow 3")
      driver.sendClick(at: rowCell)
      let clicked = try await driver.waitForFrame(
        containing: "sel:3|",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = clicked.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-click-select",
          eventType: "pointer_select",
          dispatchTimeSeconds: clickDispatch,
          expectedVisualMarker: "sel:3|",
          firstMatchingFrame: clicked.frameNumber,
          firstMatchingTimeSeconds: clicked.timestampSeconds,
          finalSettledFrame: clicked.frameNumber,
          finalSettledTimeSeconds: clicked.timestampSeconds
        )
      )

      // One arrow step: the selection moves and, because the click above put
      // focus on a row, the window follows it. A single key event per settle —
      // a burst would coalesce into one frame, and every arrow in that burst
      // would dispatch to the same (pre-move) row handler.
      let stepDispatch = monotonicSeconds()
      driver.sendKey(KeyPress(.arrowDown))
      let stepped = try await driver.waitForFrame(
        containing: "sel:4|",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = stepped.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-key-select",
          eventType: "key_select",
          dispatchTimeSeconds: stepDispatch,
          expectedVisualMarker: "sel:4|",
          firstMatchingFrame: stepped.frameNumber,
          firstMatchingTimeSeconds: stepped.timestampSeconds,
          finalSettledFrame: stepped.frameNumber,
          finalSettledTimeSeconds: stepped.timestampSeconds
        )
      )

      // Wheel scroll: since scroll-currency S1 the wheel moves the window and
      // leaves the selection alone, so this leg measures exactly the
      // rows-entering-and-leaving work over the unchanged 1k-row source. The
      // settle marker is a row that was nowhere near the previous window, so
      // it can only appear once the window has actually moved.
      let scrollDispatch = monotonicSeconds()
      driver.sendScroll(deltaY: 40, at: rowCell)
      let scrolled = try await driver.waitForFrame(
        containing: "lrow 40",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = scrolled.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-scroll-window",
          eventType: "scroll",
          dispatchTimeSeconds: scrollDispatch,
          expectedVisualMarker: "lrow 40",
          firstMatchingFrame: scrolled.frameNumber,
          firstMatchingTimeSeconds: scrolled.timestampSeconds,
          finalSettledFrame: scrolled.frameNumber,
          finalSettledTimeSeconds: scrolled.timestampSeconds
        )
      )

      // Deep walk: drive the window all the way to the end of the source, so
      // the entering/leaving-row work is exercised at depth rather than on
      // page one. Settled on the CLAMPED end row rather than an intermediate
      // one: scroll momentum can animate through a mid-range window without
      // painting a frame at any particular offset, but the clamped end is
      // where the anchor comes to rest.
      let walkDispatch = monotonicSeconds()
      // A few rows short of the very last: the final window certainly
      // contains it, without depending on exactly how many rows the border
      // and overflow indicators leave room for.
      let lastRowMarker = "lrow \(rowCount - 5)"
      driver.sendScroll(deltaY: rowCount, at: rowCell)
      let settledFrame = try await driver.waitForFrame(
        containing: lastRowMarker,
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-scroll-walk",
          eventType: "scroll",
          dispatchTimeSeconds: walkDispatch,
          expectedVisualMarker: lastRowMarker,
          firstMatchingFrame: settledFrame.frameNumber,
          firstMatchingTimeSeconds: settledFrame.timestampSeconds,
          finalSettledFrame: settledFrame.frameNumber,
          finalSettledTimeSeconds: settledFrame.timestampSeconds
        )
      )
      return events
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_LAZY_LIST_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }

  private static func usesEagerBuilder() -> Bool {
    environmentValue("SWIFTTUI_PERF_COLLECTION_SOURCE_MODE") == "eager"
  }
}

private struct PerfLazyListView: View {
  let rowCount: Int
  let usesEagerBuilder: Bool

  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy list workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the selection — independent of row focus
      // chrome — so the driver can settle each selection move.
      Text("sel:\(selection ?? -1)|")
      if usesEagerBuilder {
        List(selection: $selection) {
          ForEach(0..<rowCount, id: \.self) { index in
            row(index).tag(index)
          }
        }
        .frame(height: 24)
        .border(.separator)
      } else {
        List(0..<rowCount, id: \.self, selection: $selection) { index in
          row(index)
        }
        .frame(height: 24)
        .border(.separator)
      }
    }
    .padding(1)
  }

  private func row(_ index: Int) -> some View {
    HStack(spacing: 1) {
      Text("lrow \(index)")
      Spacer(minLength: 1)
      Text("meta \(index % 97)")
        .foregroundStyle(.separator)
    }
  }
}
