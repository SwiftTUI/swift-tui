import Foundation
import Testing

@testable import SwiftTUICharts
@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI chart and live-data stress behavior", .serialized)
struct FrameworkStressChartDataTests {}

@MainActor
private func chartDataExercise<Root: View>(
  attempt: String,
  generations: ClosedRange<Int> = 0...16,
  proposal: ProposedSize = .init(width: 64, height: 16),
  compareSemanticSnapshot: Bool = true,
  makeRoot: (Int) -> Root,
  verify: (Int, RenderSnapshot) -> Void
) {
  let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
  let identity = testIdentity("ChartData", attempt)

  for generation in generations {
    let root = makeRoot(generation)
    let retained = renderer.render(
      root,
      context: .init(
        identity: identity,
        invalidatedIdentities: generation == generations.lowerBound ? [] : [identity]
      ),
      proposal: proposal
    )
    let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
      root,
      context: .init(identity: identity),
      proposal: proposal
    )

    #expect(
      retained.rasterSurface == fresh.rasterSurface,
      "retained raster diverged in chart attempt \(attempt), generation \(generation)"
    )
    if compareSemanticSnapshot {
      #expect(
        retained.semanticSnapshot == fresh.semanticSnapshot,
        "retained semantics diverged in chart attempt \(attempt), generation \(generation)"
      )
    } else {
      let retainedNodes = retained.semanticSnapshot.accessibilityNodes
      let freshNodes = fresh.semanticSnapshot.accessibilityNodes
      #expect(retainedNodes.map(\.identity) == freshNodes.map(\.identity))
      #expect(retainedNodes.map(\.parentIdentity) == freshNodes.map(\.parentIdentity))
      #expect(retainedNodes.map(\.rect) == freshNodes.map(\.rect))
      #expect(retainedNodes.map(\.role) == freshNodes.map(\.role))
      #expect(retainedNodes.map(\.label) == freshNodes.map(\.label))
      #expect(retainedNodes.map(\.hint) == freshNodes.map(\.hint))
      #expect(retainedNodes.map(\.hidden) == freshNodes.map(\.hidden))
      #expect(retainedNodes.map(\.liveRegion) == freshNodes.map(\.liveRegion))
      #expect(retainedNodes.map(\.cursorAnchor) == freshNodes.map(\.cursorAnchor))
    }
    verify(generation, retained)
  }
}

private func chartDataText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private func chartDataAccessibilityLabels(_ snapshot: RenderSnapshot) -> [String] {
  snapshot.semanticSnapshot.accessibilityNodes.compactMap(\.label)
}

private let chartDataUTCGregorian: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}()

private func chartDataDate(day: Int, hour: Int = 12) -> Date {
  Date(timeIntervalSinceReferenceDate: Double(day * 86_400 + hour * 3_600))
}

// MARK: - Attempt 001: bar data reorder and live extrema

extension FrameworkStressChartDataTests {
  @Test("stress chart data 001 bar rows retarget after reorder and extrema replacement")
  func chartData001BarRowsRetargetAfterReorderAndExtremaReplacement() {
    // Hypothesis: BarChart's index-keyed rows can retain an earlier entry's
    // label or normalized width when order and the maximum owner change together.
    struct Root: View {
      let generation: Int

      var body: some View {
        let entries = [
          BarChartEntry("A\(generation)", value: Double(generation + 1), tone: .success),
          BarChartEntry("B\(generation)", value: Double(30 - generation), tone: .warning),
          BarChartEntry("C\(generation)", value: Double((generation * 7) % 19), tone: .info),
        ]
        BarChart(
          "Bars \(generation)",
          entries: generation.isMultiple(of: 2) ? entries : Array(entries.reversed()),
          barWidth: 15,
          labelWidth: 6
        )
      }
    }

    chartDataExercise(attempt: "001", proposal: .init(width: 48, height: 8)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Bars \(generation)"))
      #expect(text.contains("A\(generation)"))
      #expect(text.contains("B\(generation)"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains { $0.contains("Bars \(generation):") })
    }
  }
}

// MARK: - Attempt 025: AnyView cross-chart topology replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 025 AnyView replaces unrelated chart families at one slot")
  func chartData025AnyViewReplacesUnrelatedChartFamiliesAtOneSlot() {
    // Hypothesis: AnyView can reuse a primitive chart's value-collapsed subtree
    // after an unrelated chart family replaces it at the same erased identity.
    struct Root: View {
      let generation: Int

      var expectedMarker: String { "marker-\(generation)" }

      var body: some View {
        switch generation % 6 {
        case 0:
          AnyView(
            BarChart(
              expectedMarker,
              entries: [.init("bar", value: Double(generation + 1))],
              barWidth: 10,
              labelWidth: 5
            )
          )
        case 1:
          AnyView(
            LineChart(
              expectedMarker,
              series: [
                .init(
                  "line-\(generation)",
                  points: [.init(x: 0, y: 0), .init(x: 1, y: Double(generation + 1))]
                )
              ],
              height: 5,
              width: 28
            )
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
          )
        case 2:
          AnyView(
            CalendarHeatmap(
              expectedMarker,
              days: [.init(chartDataDate(day: generation % 10), value: Double(generation + 1))],
              range: chartDataDate(day: 0)...chartDataDate(day: 13),
              calendar: chartDataUTCGregorian,
              showsMonthHeader: false,
              showsDayLabels: false,
              showsScaleLegend: false
            )
          )
        case 3:
          AnyView(
            Meter(
              expectedMarker,
              value: Double(generation),
              total: Double(generation + 10),
              barWidth: 12
            )
          )
        case 4:
          AnyView(
            Timeline([
              .init(expectedMarker, detail: "timeline-\(generation)", tone: .success)
            ])
          )
        default:
          AnyView(
            ThresholdGauge(
              expectedMarker,
              value: Double(generation),
              total: Double(generation + 20),
              bands: [
                .init(upTo: Double(generation + 5), tone: .success),
                .init(upTo: Double(generation + 20), tone: .critical),
              ],
              barWidth: 11
            )
          )
        }
      }
    }

    chartDataExercise(
      attempt: "025",
      proposal: .init(width: 58, height: 13),
      compareSemanticSnapshot: false
    ) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("marker-\(generation)"))
      if generation > 0 {
        #expect(!text.contains("marker-\(generation - 1)"))
      }
    }
  }
}

// MARK: - Attempt 024: calendar timezone and identifier replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 024 calendar timezone replacement rebuckets boundary instants")
  func chartData024CalendarTimezoneReplacementRebucketsBoundaryInstants() {
    // Hypothesis: CalendarHeatmap can retain day positions derived from an old
    // Calendar value when identical absolute instants cross local-day boundaries.
    struct Root: View {
      let generation: Int

      var calendar: Calendar {
        var result = Calendar(identifier: generation % 3 == 2 ? .iso8601 : .gregorian)
        let identifier: String
        switch generation % 3 {
        case 0: identifier = "UTC"
        case 1: identifier = "America/Los_Angeles"
        default: identifier = "Asia/Tokyo"
        }
        result.timeZone = TimeZone(identifier: identifier)!
        return result
      }

      var body: some View {
        CalendarHeatmap(
          "Timezone \(generation)",
          days: [
            .init(chartDataDate(day: 3, hour: 0), value: 3),
            .init(chartDataDate(day: 3, hour: 23), value: 5),
            .init(chartDataDate(day: 9, hour: 1), value: Double(7 + generation)),
            .init(chartDataDate(day: 9, hour: 22), value: Double(11 + generation)),
          ],
          range: chartDataDate(day: 0)...chartDataDate(day: 20, hour: 23),
          weekStart: generation.isMultiple(of: 2) ? .sunday : .monday,
          calendar: calendar,
          cellWidth: 2,
          showsMonthHeader: false,
          showsDayLabels: true,
          showsScaleLegend: true,
          tone: .info
        )
      }
    }

    chartDataExercise(attempt: "024", proposal: .init(width: 58, height: 13)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Timezone \(generation)"))
      #expect(text.contains("4 days"))
      #expect(text.contains("Mon"))
      #expect(text.contains("Less"))
      #expect(chartDataAccessibilityLabels(snapshot).contains("Timezone \(generation): 4 days"))
    }
  }
}

// MARK: - Attempt 023: calendar range and chrome topology replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 023 calendar range week start and chrome topology replace")
  func chartData023CalendarRangeWeekStartAndChromeTopologyReplace() {
    // Hypothesis: changing week origin and week-column count alongside optional
    // chrome can retain an old bucket shape or mismatched weekday labels.
    struct Root: View {
      let generation: Int

      var showsMonthHeader: Bool { !generation.isMultiple(of: 3) }
      var showsDayLabels: Bool { generation.isMultiple(of: 2) }
      var showsLegend: Bool { generation % 4 < 2 }

      var range: ClosedRange<Date> {
        generation.isMultiple(of: 2)
          ? chartDataDate(day: 0)...chartDataDate(day: 6)
          : chartDataDate(day: -14)...chartDataDate(day: 34)
      }

      var body: some View {
        CalendarHeatmap(
          "Weeks \(generation)",
          days: [
            .init(chartDataDate(day: 0), value: Double(generation + 1)),
            .init(chartDataDate(day: 5), value: Double(generation + 4)),
            .init(chartDataDate(day: 27), value: Double(generation + 8)),
          ],
          range: range,
          weekStart: generation.isMultiple(of: 2) ? .sunday : .monday,
          calendar: chartDataUTCGregorian,
          cellWidth: 2,
          showsMonthHeader: showsMonthHeader,
          showsDayLabels: showsDayLabels,
          showsScaleLegend: true
        )
        .chartLegend(showsLegend ? .bottom : .hidden)
      }
    }

    chartDataExercise(attempt: "023", proposal: .init(width: 64, height: 14)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains("Weeks \(generation)"))
      #expect(text.contains("3 days"))
      #expect(text.contains("Mon") == root.showsDayLabels)
      #expect(text.contains("Less") == root.showsLegend)
      if root.showsMonthHeader {
        #expect(text.contains("Ja"))
      }
    }
  }
}

// MARK: - Attempt 022: calendar duplicate aggregation and input order

extension FrameworkStressChartDataTests {
  @Test("stress chart data 022 calendar duplicate days aggregate after reorder")
  func chartData022CalendarDuplicateDaysAggregateAfterReorder() {
    // Hypothesis: CalendarHeatmap can retain pre-aggregation cell intensity when
    // duplicate dates reorder and their summed value changes inside a fixed range.
    struct Root: View {
      let generation: Int

      var days: [DateValue] {
        let duplicateDay = generation % 12
        let values = [
          DateValue(chartDataDate(day: duplicateDay), value: Double(3 + generation)),
          DateValue(chartDataDate(day: duplicateDay, hour: 20), value: Double(7 + generation)),
          DateValue(chartDataDate(day: (duplicateDay + 5) % 20), value: -Double(20 + generation)),
          DateValue(chartDataDate(day: 24), value: Double(2 + generation)),
          DateValue(chartDataDate(day: 40), value: 999),
        ]
        return generation.isMultiple(of: 2) ? values : Array(values.reversed())
      }

      var body: some View {
        CalendarHeatmap(
          "Calendar \(generation)",
          days: days,
          range: chartDataDate(day: 0)...chartDataDate(day: 27),
          weekStart: .sunday,
          calendar: chartDataUTCGregorian,
          cellWidth: generation.isMultiple(of: 3) ? 1 : 2,
          showsMonthHeader: true,
          showsDayLabels: true,
          showsScaleLegend: true,
          tone: generation.isMultiple(of: 2) ? .success : .warning
        )
      }
    }

    chartDataExercise(attempt: "022", proposal: .init(width: 62, height: 14)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Calendar \(generation)"))
      #expect(text.contains("5 days"))
      #expect(text.contains(generation.isMultiple(of: 3) ? "J" : "Ja"))
      #expect(text.contains("Less"))
      #expect(chartDataAccessibilityLabels(snapshot).contains("Calendar \(generation): 5 days"))
    }
  }
}

// MARK: - Attempt 021: line degenerate and extreme finite domains

extension FrameworkStressChartDataTests {
  @Test("stress chart data 021 line degenerate tiny and huge finite domains converge")
  func chartData021LineDegenerateTinyAndHugeFiniteDomainsConverge() {
    // Hypothesis: a retained domain fast path can remain stuck after a zero-span
    // frame when the next generation expands to tiny or very large finite ranges.
    struct Root: View {
      let generation: Int

      var points: [LineChartPoint] {
        switch generation % 4 {
        case 0: [.init(x: 0, y: 0)]
        case 1:
          [
            .init(x: 5, y: -5),
            .init(x: 5, y: -5),
            .init(x: 5, y: -5),
          ]
        case 2:
          [
            .init(x: -1e150, y: 1e150),
            .init(x: 0, y: 0),
            .init(x: 1e150, y: -1e150),
          ]
        default:
          [
            .init(x: -1e-150, y: -1e-150),
            .init(x: 0, y: 1e-150),
            .init(x: 1e-150, y: 0),
          ]
        }
      }

      var body: some View {
        LineChart(
          "Finite \(generation)",
          series: [.init("Domain \(generation)", points: points)],
          height: 7,
          width: 36
        )
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.bottom)
      }
    }

    chartDataExercise(attempt: "021", proposal: .init(width: 54, height: 13)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Finite \(generation)"))
      #expect(text.contains("Domain \(generation)"))
      #expect(text.contains("1 series"))
    }
  }
}

// MARK: - Attempt 020: line axis and legend topology replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 020 line axes and legend move through hidden topology")
  func chartData020LineAxesAndLegendMoveThroughHiddenTopology() {
    // Hypothesis: axis and legend branches can survive hidden/visible replacement,
    // retaining obsolete chrome or dropping the newly inserted tick topology.
    struct Root: View {
      let generation: Int

      var xAxis: LineChartXAxis {
        switch generation % 3 {
        case 0: .hidden
        case 1: .values(count: 3)
        default: .values(count: 6)
        }
      }

      var yAxis: LineChartYAxis {
        generation.isMultiple(of: 2) ? .hidden : .values(count: 5)
      }

      var legend: LineChartLegendConfig {
        switch generation % 3 {
        case 0: .hidden
        case 1: .top
        default: .bottom
        }
      }

      var body: some View {
        LineChart(
          "Chrome \(generation)",
          series: [
            .init(
              "Legend \(generation)",
              points: [
                .init(x: 0, y: Double(generation)),
                .init(x: 50, y: Double(20 - generation % 7)),
                .init(x: 100, y: Double(30 + generation)),
              ]
            )
          ],
          height: 5 + generation % 4,
          width: 34 + generation % 7
        )
        .chartXAxis(xAxis)
        .chartYAxis(yAxis)
        .chartLegend(legend)
      }
    }

    chartDataExercise(attempt: "020", proposal: .init(width: 66, height: 16)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains("Chrome \(generation)"))
      if root.legend.position == .hidden {
        #expect(!text.contains("Legend \(generation)"))
      } else {
        #expect(text.contains("Legend \(generation)"))
      }
    }
  }
}

// MARK: - Attempt 019: line series cardinality and z-order churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 019 line series shrink regrow and reorder rebuilds z ownership")
  func chartData019LineSeriesShrinkRegrowAndReorderRebuildsZOwnership() {
    // Hypothesis: composed-grid series indices can outlive a departed series or
    // point at the wrong tone after colliding series shrink, regrow, and reorder.
    struct Root: View {
      let generation: Int

      var series: [LineChartSeries] {
        let count: Int
        switch generation % 4 {
        case 0: count = 0
        case 1: count = 1
        default: count = 4
        }
        let values = (0..<count).map { index in
          LineChartSeries(
            "S\(index)-\(generation)",
            points: [
              .init(x: 0, y: Double(index - generation % 3)),
              .init(x: 5, y: Double(8 - index + generation % 5)),
              .init(x: 10, y: Double(index * 2 - 3)),
            ],
            style: index.isMultiple(of: 3) ? .area : (index.isMultiple(of: 2) ? .step : .line),
            tone: index.isMultiple(of: 2) ? .success : .warning
          )
        }
        return generation.isMultiple(of: 2) ? values : Array(values.reversed())
      }

      var body: some View {
        LineChart(
          "Series set \(generation)",
          series: series,
          height: 7,
          width: 40
        )
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.bottom)
      }
    }

    chartDataExercise(attempt: "019", proposal: .init(width: 72, height: 13)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains("Series set \(generation)"))
      #expect(text.contains("\(root.series.count) series"))
      for series in root.series {
        #expect(text.contains(series.label))
      }
      #expect(
        chartDataAccessibilityLabels(snapshot).contains(
          "Series set \(generation): \(root.series.count) series"
        )
      )
    }
  }
}

// MARK: - Attempt 018: line style and baseline replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 018 line area and step topology replace at one series slot")
  func chartData018LineAreaAndStepTopologyReplaceAtOneSeriesSlot() {
    // Hypothesis: a retained composed-series grid can preserve area fill or step
    // cells when the same series slot changes rasterization style and baseline.
    struct Root: View {
      let generation: Int

      var style: LineChartSeriesStyle {
        switch generation % 3 {
        case 1: .area
        case 2: .step
        default: .line
        }
      }

      var body: some View {
        LineChart(
          "Raster \(generation)",
          series: [
            .init(
              "Mode \(generation)",
              points: [
                .init(x: 0, y: -Double(5 + generation)),
                .init(x: 5, y: Double(15 + generation)),
                .init(x: 10, y: Double((generation % 4) - 2)),
              ],
              style: style,
              tone: .info
            )
          ],
          height: 8,
          width: 38
        )
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.bottom)
        .chartBaseline(generation.isMultiple(of: 2) ? .zero : .auto)
      }
    }

    chartDataExercise(attempt: "018", proposal: .init(width: 52, height: 13)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Raster \(generation)"))
      #expect(text.contains("Mode \(generation)"))
      if generation % 3 == 1 {
        #expect(text.contains("▒"))
      }
    }
  }
}

// MARK: - Attempt 017: line point order and domain migration

extension FrameworkStressChartDataTests {
  @Test("stress chart data 017 line point reorder rebuilds the combined numeric domain")
  func chartData017LinePointReorderRebuildsCombinedNumericDomain() {
    // Hypothesis: LineChart can retain a composed grid or domain from an earlier
    // point order when both X and Y extrema move but the series identity stays fixed.
    struct Root: View {
      let generation: Int

      var points: [LineChartPoint] {
        let values = [
          LineChartPoint(x: -Double(100 + generation), y: Double(generation - 20)),
          LineChartPoint(x: Double(generation), y: Double(40 + generation)),
          LineChartPoint(x: Double(100 + generation * 2), y: -Double(30 + generation)),
        ]
        return generation.isMultiple(of: 2) ? values : Array(values.reversed())
      }

      var body: some View {
        LineChart(
          "Line \(generation)",
          series: [
            .init(
              "Series \(generation)",
              points: points,
              style: .line,
              tone: generation.isMultiple(of: 2) ? .success : .warning
            )
          ],
          height: 7,
          width: 42
        )
        .chartXAxis(.values(count: 4))
        .chartYAxis(.values(count: 4))
        .chartLegend(.bottom)
      }
    }

    chartDataExercise(attempt: "017", proposal: .init(width: 62, height: 14)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Line \(generation)"))
      #expect(text.contains("Series \(generation)"))
      #expect(text.contains("1 series"))
      #expect(chartDataAccessibilityLabels(snapshot).contains("Line \(generation): 1 series"))
    }
  }
}

// MARK: - Attempt 016: legend cardinality and order churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 016 legend cardinality reorder and spacing replace item contracts")
  func chartData016LegendCardinalityReorderAndSpacingReplaceItemContracts() {
    // Hypothesis: Legend's index-keyed item views can preserve a departed label,
    // tone, or inter-item spacing after empty/shrink/regrow transitions.
    struct Root: View {
      let generation: Int

      var items: [LegendItem] {
        let count: Int
        switch generation % 3 {
        case 0: count = 0
        case 1: count = 1
        default: count = 5
        }
        let values = (0..<count).map { index in
          LegendItem(
            "L\(index)-\(generation)",
            tone: (index + generation).isMultiple(of: 2) ? .success : .critical
          )
        }
        return generation.isMultiple(of: 2) ? values : Array(values.reversed())
      }

      var body: some View {
        Legend(
          "Legend \(generation)",
          items: items,
          itemSpacing: [0, 1, 4][generation % 3]
        )
      }
    }

    chartDataExercise(attempt: "016", proposal: .init(width: 72, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains("Legend \(generation)"))
      for item in root.items {
        #expect(text.contains(item.label))
      }
      if root.items.isEmpty {
        #expect(!text.contains("L0-\(generation)"))
      }
    }
  }
}

// MARK: - Attempt 015: timeline order and detail topology

extension FrameworkStressChartDataTests {
  @Test("stress chart data 015 timeline reorder and optional details rebuild connectors")
  func chartData015TimelineReorderAndOptionalDetailsRebuildConnectors() {
    // Hypothesis: Timeline's index-keyed entry topology can retain an earlier
    // last-row connector or optional detail line through reorder and cardinality churn.
    struct Root: View {
      let generation: Int

      var entries: [TimelineEntry] {
        let count = generation.isMultiple(of: 3) ? 1 : 4
        let values = (0..<count).map { index in
          TimelineEntry(
            "T\(index)-\(generation)",
            detail: (index + generation).isMultiple(of: 2) ? "D\(index)-\(generation)" : nil,
            tone: index.isMultiple(of: 2) ? .success : .warning
          )
        }
        return generation.isMultiple(of: 2) ? values : Array(values.reversed())
      }

      var body: some View {
        Timeline(entries)
      }
    }

    chartDataExercise(attempt: "015", proposal: .init(width: 46, height: 16)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      for entry in root.entries {
        #expect(text.contains(entry.title))
        if let detail = entry.detail {
          #expect(text.contains(detail))
        }
      }
      if root.entries.count == 1 {
        #expect(!text.contains("T3-\(generation)"))
      }
      #expect(text.contains("╰"))
    }
  }
}

// MARK: - Attempt 014: threshold band normalization replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 014 threshold bands reorder clamp and replace tones")
  func chartData014ThresholdBandsReorderClampAndReplaceTones() {
    // Hypothesis: normalized threshold bands can be retained by authored offset,
    // leaving stale segment tones after unsorted, duplicate, or clamped bands replace them.
    struct Root: View {
      let generation: Int

      var total: Double { Double(100 + generation) }
      var value: Double { Double((generation * 17) % (100 + generation)) }

      var bands: [ThresholdBand] {
        switch generation % 4 {
        case 0: []
        case 1:
          [
            .init(upTo: total, tone: .critical),
            .init(upTo: total * 0.25, tone: .success),
            .init(upTo: total * 0.6, tone: .warning),
          ]
        case 2:
          [
            .init(upTo: total * 0.5, tone: .warning),
            .init(upTo: total * 0.5, tone: .info),
            .init(upTo: total * 2, tone: .critical),
          ]
        default:
          [
            .init(upTo: -20, tone: .critical),
            .init(upTo: total * 0.8, tone: .success),
          ]
        }
      }

      var body: some View {
        ThresholdGauge(
          "Bands \(generation)",
          value: value,
          total: total,
          bands: bands,
          barWidth: 9 + generation % 6
        )
      }
    }

    chartDataExercise(attempt: "014", proposal: .init(width: 56, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let summary = "\(Int(root.value))/\(Int(root.total))"
      let text = chartDataText(snapshot)
      #expect(text.contains("Bands \(generation)"))
      #expect(text.contains(summary))
      #expect(chartDataAccessibilityLabels(snapshot).contains("Bands \(generation): \(summary)"))
    }
  }
}

// MARK: - Attempt 013: bullet marker and fill replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 013 bullet target marker crosses live fill and total domains")
  func chartData013BulletTargetMarkerCrossesLiveFillAndTotalDomains() {
    // Hypothesis: BulletChart can retain either the target marker index or its
    // filled/empty glyph when value, target, total, and width all change together.
    struct Root: View {
      let generation: Int

      var values: (value: Double, target: Double, total: Double) {
        switch generation % 4 {
        case 0: (0, 0, 0)
        case 1: (Double(20 + generation), Double(80 + generation), 100)
        case 2: (Double(90 + generation), Double(10 + generation), 100)
        default: (5, Double(30 + generation), -1)
        }
      }

      var body: some View {
        let values = values
        BulletChart(
          "Bullet \(generation)",
          value: values.value,
          target: values.target,
          total: values.total,
          tone: generation.isMultiple(of: 2) ? .info : .critical,
          barWidth: 8 + generation % 7
        )
      }
    }

    chartDataExercise(attempt: "013", proposal: .init(width: 52, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let target = Int(Root(generation: generation).values.target)
      let text = chartDataText(snapshot)
      #expect(text.contains("Bullet \(generation)"))
      #expect(text.contains("t \(target)"))
      #expect(chartDataAccessibilityLabels(snapshot).contains("Bullet \(generation): t \(target)"))
    }
  }
}

// MARK: - Attempt 012: meter total-sign boundary churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 012 meter crosses zero total and width boundaries")
  func chartData012MeterCrossesZeroTotalAndWidthBoundaries() {
    // Hypothesis: Meter's nonpositive-total fast path can leave a stale filled
    // count or percentage after returning to a positive fractional domain.
    struct Root: View {
      let generation: Int

      var valueAndTotal: (value: Double, total: Double, percentage: Int) {
        switch generation % 4 {
        case 0: (0, 0, 0)
        case 1: (5, 0, 100)
        case 2: (-5, -2, 0)
        default: (Double(generation + 1), Double((generation + 1) * 2), 50)
        }
      }

      var body: some View {
        let pair = valueAndTotal
        Meter(
          "Meter \(generation)",
          value: pair.value,
          total: pair.total,
          tone: generation.isMultiple(of: 2) ? .success : .critical,
          barWidth: [1, 7, 13, 19][generation % 4]
        )
      }
    }

    chartDataExercise(attempt: "012", proposal: .init(width: 50, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let percentage = Root(generation: generation).valueAndTotal.percentage
      let text = chartDataText(snapshot)
      #expect(text.contains("Meter \(generation)"))
      #expect(text.contains("\(percentage)%"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains("Meter \(generation): \(percentage)%")
      )
    }
  }
}

// MARK: - Attempt 011: heat-strip normalization and order churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 011 heat strip maximum migration retargets cells and labels")
  func chartData011HeatStripMaximumMigrationRetargetsCellsAndLabels() {
    // Hypothesis: HeatStrip can retain an old maximum owner or tone at an index
    // when entries reorder while cell width and normalization both change.
    struct Root: View {
      let generation: Int

      var body: some View {
        let maximumIndex = generation % 4
        let entries = (0..<4).map { index in
          BarChartEntry(
            "\(index)\(generation % 10)",
            value: index == maximumIndex
              ? -Double(50 + generation)
              : Double((index + 1) * (generation % 5 + 1)),
            tone: index == maximumIndex ? .critical : .info
          )
        }
        HeatStrip(
          "Heat \(generation)",
          entries: generation.isMultiple(of: 2) ? entries : Array(entries.reversed()),
          cellWidth: generation.isMultiple(of: 3) ? 2 : 3
        )
      }
    }

    chartDataExercise(attempt: "011", proposal: .init(width: 52, height: 6)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Heat \(generation)"))
      #expect(text.contains("hi \(50 + generation)"))
      for index in 0..<4 {
        #expect(text.contains("\(index)\(generation % 10)"))
      }
    }
  }
}

// MARK: - Attempt 010: sparkline empty and constant-domain churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 010 sparkline empty constant and ramp domains replace cleanly")
  func chartData010SparklineEmptyConstantAndRampDomainsReplaceCleanly() {
    // Hypothesis: transitions through the empty and zero-span fast paths can
    // preserve a prior ramp string or accessibility summary in retained output.
    struct Root: View {
      let generation: Int

      var values: [Double] {
        switch generation % 3 {
        case 0: []
        case 1: Array(repeating: Double(generation), count: 4)
        default: (0..<(2 + generation % 7)).map(Double.init)
        }
      }

      var expectedSummary: String {
        switch generation % 3 {
        case 0: "no data"
        case 1: "lo \(generation) hi \(generation)"
        default: "lo 0 hi \(values.count - 1)"
        }
      }

      var expectedGlyphs: String {
        switch generation % 3 {
        case 0: "[]"
        case 1: "▄▄▄▄"
        default: sparklineGlyphString(values)
        }
      }

      var body: some View {
        Sparkline("Modes \(generation)", values: values)
      }
    }

    chartDataExercise(attempt: "010", proposal: .init(width: 54, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains(root.expectedSummary))
      #expect(text.contains(root.expectedGlyphs))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains(
          "Modes \(generation): \(root.expectedSummary)"
        )
      )
    }
  }
}

// MARK: - Attempt 009: sparkline migrating extrema

extension FrameworkStressChartDataTests {
  @Test("stress chart data 009 sparkline extrema migration renormalizes every sample")
  func chartData009SparklineExtremaMigrationRenormalizesEverySample() {
    // Hypothesis: Sparkline can retain normalized glyphs by array position when
    // the minimum and maximum migrate while sample cardinality stays constant.
    struct Root: View {
      let generation: Int

      var values: [Double] {
        let minimumIndex = generation % 8
        let maximumIndex = (minimumIndex + 3) % 8
        var result = (0..<8).map { Double(generation + $0) }
        result[minimumIndex] = -Double(20 + generation)
        result[maximumIndex] = Double(40 + generation)
        return result
      }

      var body: some View {
        Sparkline(
          "Spark \(generation)",
          values: values,
          tone: generation.isMultiple(of: 2) ? .success : .warning
        )
      }
    }

    chartDataExercise(attempt: "009", proposal: .init(width: 52, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Spark \(generation)"))
      #expect(text.contains("lo -\(20 + generation) hi \(40 + generation)"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains(
          "Spark \(generation): lo -\(20 + generation) hi \(40 + generation)"
        )
      )
    }
  }
}

// MARK: - Attempt 008: comparison cardinality and trend-tone churn

extension FrameworkStressChartDataTests {
  @Test("stress chart data 008 comparison cardinality churn retargets automatic trends")
  func chartData008ComparisonCardinalityChurnRetargetsAutomaticTrends() {
    // Hypothesis: shrinking and regrowing automatic-tone rows can restore a
    // departed row's trend style or paired baseline at the same structural index.
    struct Root: View {
      let generation: Int

      var body: some View {
        let count = generation.isMultiple(of: 4) ? 1 : 3
        let entries = (0..<count).map { index in
          let current =
            generation.isMultiple(of: 2)
            ? Double(40 + generation + index)
            : Double(10 + index)
          let baseline =
            generation.isMultiple(of: 2)
            ? Double(10 + index)
            : Double(40 + generation + index)
          return ComparisonEntry(
            "R\(index)-\(generation)",
            current: current,
            baseline: baseline,
            tone: .automatic
          )
        }
        ComparisonChart(
          "Trends \(generation)",
          entries: generation.isMultiple(of: 3) ? Array(entries.reversed()) : entries,
          barWidth: 12,
          labelWidth: 8
        )
      }
    }

    chartDataExercise(attempt: "008", proposal: .init(width: 60, height: 8)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      let count = generation.isMultiple(of: 4) ? 1 : 3
      #expect(text.contains("Trends \(generation)"))
      for index in 0..<count {
        #expect(text.contains("R\(index)-\(generation)"))
      }
      if count == 1 {
        #expect(!text.contains("R2-\(generation)"))
      }
    }
  }
}

// MARK: - Attempt 007: comparison per-row total replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 007 comparison rows replace optional totals and paired values")
  func chartData007ComparisonRowsReplaceOptionalTotalsAndPairedValues() {
    // Hypothesis: ComparisonChart can retain a row's old effective total when
    // current, baseline, and optional total all change without changing row count.
    struct Root: View {
      let generation: Int

      var firstTotal: Double? {
        generation.isMultiple(of: 2) ? nil : Double(60 + generation)
      }

      var secondTotal: Double? {
        generation.isMultiple(of: 3) ? Double(80 + generation) : nil
      }

      var expectedMaximum: Int {
        let first = firstTotal ?? max(Double(10 + generation), 15)
        let second = secondTotal ?? max(30, Double(25 + generation))
        return Int(max(first, second))
      }

      var body: some View {
        let entries = [
          ComparisonEntry(
            "A\(generation)",
            current: Double(10 + generation),
            baseline: 15,
            total: firstTotal,
            tone: .automatic
          ),
          ComparisonEntry(
            "B\(generation)",
            current: -30,
            baseline: Double(25 + generation),
            total: secondTotal,
            tone: .critical
          ),
        ]
        ComparisonChart(
          "Compare \(generation)",
          entries: generation.isMultiple(of: 2) ? entries : Array(entries.reversed()),
          barWidth: 14,
          labelWidth: 7
        )
      }
    }

    chartDataExercise(attempt: "007", proposal: .init(width: 58, height: 7)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let root = Root(generation: generation)
      let text = chartDataText(snapshot)
      #expect(text.contains("Compare \(generation)"))
      #expect(text.contains("max \(root.expectedMaximum)"))
      #expect(text.contains("\(10 + generation)/15"))
      #expect(text.contains("-30/\(25 + generation)"))
    }
  }
}

// MARK: - Attempt 006: stacked optional total replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 006 stacked optional total replacement refreshes filler and summary")
  func chartData006StackedOptionalTotalReplacementRefreshesFillerAndSummary() {
    // Hypothesis: toggling the optional authored total can leave either the old
    // filler width or the old synthesized accessibility summary on a retained chart.
    struct Root: View {
      let generation: Int

      var total: Double? {
        switch generation % 3 {
        case 1: Double(40 + generation)
        case 2: 4
        default: nil
        }
      }

      var expectedTotal: Int {
        switch generation % 3 {
        case 1: 40 + generation
        case 2: 4
        default: 12 + generation
        }
      }

      var body: some View {
        StackedBarChart(
          "Capacity \(generation)",
          entries: [
            .init("live", value: Double(5 + generation), tone: .success),
            .init("queued", value: 7, tone: .warning),
          ],
          total: total,
          barWidth: 18
        )
      }
    }

    chartDataExercise(attempt: "006", proposal: .init(width: 48, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let expectedTotal = Root(generation: generation).expectedTotal
      let expectedLabel = "Capacity \(generation): sum \(expectedTotal)"
      #expect(chartDataText(snapshot).contains("sum \(expectedTotal)"))
      #expect(chartDataAccessibilityLabels(snapshot).contains(expectedLabel))
    }
  }
}

// MARK: - Attempt 005: stacked largest-remainder reorder

extension FrameworkStressChartDataTests {
  @Test("stress chart data 005 stacked allocation follows reordered weighted segments")
  func chartData005StackedAllocationFollowsReorderedWeightedSegments() {
    // Hypothesis: largest-remainder widths or segment styles can remain keyed to
    // an earlier index after weighted segments reorder at a fixed topology.
    struct Root: View {
      let generation: Int

      var body: some View {
        let entries = [
          BarChartEntry("A", value: Double(generation + 1), tone: .success),
          BarChartEntry("B", value: 2, tone: .warning),
          BarChartEntry("C", value: 3, tone: .info),
        ]
        StackedBarChart(
          "Stack \(generation)",
          entries: generation.isMultiple(of: 2) ? entries : Array(entries.reversed()),
          barWidth: generation.isMultiple(of: 3) ? 10 : 11
        )
      }
    }

    chartDataExercise(attempt: "005", proposal: .init(width: 44, height: 5)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let expectedTotal = generation + 6
      let text = chartDataText(snapshot)
      #expect(text.contains("Stack \(generation)"))
      #expect(text.contains("sum \(expectedTotal)"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains(
          "Stack \(generation): sum \(expectedTotal)"
        )
      )
    }
  }
}

// MARK: - Attempt 004: column maximum-owner migration

extension FrameworkStressChartDataTests {
  @Test("stress chart data 004 column maximum owner migrates through reordered rows")
  func chartData004ColumnMaximumOwnerMigratesThroughReorderedRows() {
    // Hypothesis: the normalized height cache can stay attached to an old array
    // offset when the maximum value and declaration order rotate independently.
    struct Root: View {
      let generation: Int

      var body: some View {
        let maximumIndex = generation % 3
        let base = (0..<3).map { index in
          BarChartEntry(
            "\(index)\(generation % 10)",
            value: index == maximumIndex
              ? (index.isMultiple(of: 2) ? -Double(100 + generation) : Double(100 + generation))
              : Double(20 + index * 10),
            tone: index == maximumIndex ? .critical : .info
          )
        }
        let entries: [BarChartEntry]
        switch generation % 3 {
        case 1: entries = [base[1], base[2], base[0]]
        case 2: entries = [base[2], base[0], base[1]]
        default: entries = base
        }
        ColumnChart(
          "Peak \(generation)",
          entries: entries,
          chartHeight: 7,
          columnWidth: 2
        )
      }
    }

    chartDataExercise(attempt: "004", proposal: .init(width: 46, height: 12)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Peak \(generation)"))
      #expect(text.contains("max \(100 + generation)"))
      for index in 0..<3 {
        #expect(text.contains("\(index)\(generation % 10)"))
      }
    }
  }
}

// MARK: - Attempt 003: column cardinality shrink and regrow

extension FrameworkStressChartDataTests {
  @Test("stress chart data 003 column cardinality shrink and regrow rebuilds indexed cells")
  func chartData003ColumnCardinalityShrinkAndRegrowRebuildsIndexedCells() {
    // Hypothesis: ColumnChart's nested index-keyed rows can preserve departed
    // columns or fail to materialize regrown columns after repeated cardinality churn.
    struct Root: View {
      let generation: Int

      var body: some View {
        let count = generation.isMultiple(of: 3) ? 1 : 4
        let entries = (0..<count).map { index in
          BarChartEntry(
            "\(index)\(generation % 10)",
            value: Double((index + 1) * (generation + 2)),
            tone: index.isMultiple(of: 2) ? .success : .warning
          )
        }
        ColumnChart(
          "Columns \(generation)",
          entries: entries,
          chartHeight: 3 + (generation % 4),
          columnWidth: 2
        )
      }
    }

    chartDataExercise(attempt: "003", proposal: .init(width: 48, height: 12)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      let count = generation.isMultiple(of: 3) ? 1 : 4
      #expect(text.contains("Columns \(generation)"))
      for index in 0..<count {
        #expect(text.contains("\(index)\(generation % 10)"))
      }
      if count == 1 {
        #expect(!text.contains("3\(generation % 10)"))
      }
    }
  }
}

// MARK: - Attempt 002: bar signed-domain replacement

extension FrameworkStressChartDataTests {
  @Test("stress chart data 002 bar signed extrema refresh summary and track geometry")
  func chartData002BarSignedExtremaRefreshSummaryAndTrackGeometry() {
    // Hypothesis: replacing a positive maximum with a larger negative value can
    // refresh the printed number while retaining the prior normalization domain.
    struct Root: View {
      let generation: Int

      var body: some View {
        let extreme = Double(40 + generation)
        BarChart(
          "Signed \(generation)",
          entries: [
            .init("neg\(generation)", value: -extreme, tone: .critical),
            .init("pos\(generation)", value: Double((generation % 7) + 1), tone: .info),
            .init("zero\(generation)", value: 0, tone: .automatic),
          ],
          barWidth: generation.isMultiple(of: 2) ? 13 : 17,
          labelWidth: generation.isMultiple(of: 3) ? 7 : 9
        )
      }
    }

    chartDataExercise(attempt: "002", proposal: .init(width: 52, height: 8)) { generation in
      Root(generation: generation)
    } verify: { generation, snapshot in
      let text = chartDataText(snapshot)
      #expect(text.contains("Signed \(generation)"))
      #expect(text.contains("-\(40 + generation)"))
      #expect(text.contains("max \(40 + generation)"))
      #expect(
        chartDataAccessibilityLabels(snapshot).contains(
          "Signed \(generation): max \(40 + generation)"
        )
      )
    }
  }
}
