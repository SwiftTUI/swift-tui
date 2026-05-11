import Foundation
import SwiftTUICharts
import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

// AnyView policy: retain erased fixture roots here for test support only.
@Suite
@MainActor
struct NonAggregatingViewFixtureTests {
  @Test("non-aggregating view fixture matches", arguments: nonAggregatingFixtureNames)
  func renderedFixtureMatches(named fixtureName: String) throws {
    let fixture = fixture(named: fixtureName)

    try assertRenderedTextFixtures(
      named: fixture.name,
      size: fixture.size,
      view: fixture.view,
      identity: fixture.identity,
      environmentValues: fixture.environmentValues
    )
  }

  private func fixture(named name: String) -> FixtureSpec {
    switch name {
    case "empty-view":
      return FixtureSpec(
        name: name,
        size: .init(width: 4, height: 2),
        view: AnyView(EmptyView())
      )

    case "text":
      return FixtureSpec(
        name: name,
        size: .init(width: 14, height: 2),
        view: AnyView(Text("Wide: 界e\u{301}"))
      )

    case "spacer":
      return FixtureSpec(
        name: name,
        size: .init(width: 6, height: 2),
        view: AnyView(Spacer(minLength: 2))
      )

    case "divider":
      return FixtureSpec(
        name: name,
        size: .init(width: 14, height: 1),
        view: AnyView(Divider())
      )

    case "label":
      return FixtureSpec(
        name: name,
        size: .init(width: 16, height: 1),
        view: AnyView(
          Label("Endpoint", icon: { Text("◎") })
        )
      )

    case "labeled-content":
      return FixtureSpec(
        name: name,
        size: .init(width: 20, height: 1),
        view: AnyView(LabeledContent("Mode", value: "Inspect"))
      )

    case "toggle":
      return FixtureSpec(
        name: name,
        size: .init(width: 22, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Toggle("Accent Preview", isOn: .constant(true))
        )
      )

    case "stepper":
      return FixtureSpec(
        name: name,
        size: .init(width: 24, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Stepper("Retries", value: .constant(3), in: 0...9)
        )
      )

    case "text-field":
      return FixtureSpec(
        name: name,
        size: .init(width: 18, height: 3),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          TextField("Name", text: .constant("Ada"))
            .textFieldStyle(.roundedBorder)
            .frame(width: 14, alignment: .leading)
        )
      )

    case "slider":
      return FixtureSpec(
        name: name,
        size: .init(width: 26, height: 1),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Slider("Blend", value: .constant(42), in: 0...100)
        )
      )

    case "button":
      return FixtureSpec(
        name: name,
        size: .init(width: 18, height: 3),
        environmentValues: focusedEnvironmentValues(),
        view: AnyView(
          Button("Deploy", action: {})
            .buttonStyle(.borderedProminent)
        )
      )

    case "progress-view":
      return FixtureSpec(
        name: name,
        size: .init(width: 26, height: 1),
        view: AnyView(
          ProgressView("Rollout", value: 7, total: 10)
        )
      )

    case "meter":
      return FixtureSpec(
        name: name,
        size: .init(width: 26, height: 1),
        view: AnyView(
          Meter("Budget", value: 84, total: 100, tone: .warning)
        )
      )

    case "sparkline":
      return FixtureSpec(
        name: name,
        size: .init(width: 28, height: 2),
        view: AnyView(
          Sparkline("Traffic", values: trafficSeries, tone: .info)
        )
      )

    case "timeline":
      return FixtureSpec(
        name: name,
        size: .init(width: 28, height: 5),
        view: AnyView(Timeline(timelineEntries))
      )

    case "legend":
      return FixtureSpec(
        name: name,
        size: .init(width: 30, height: 2),
        view: AnyView(
          Legend("Series", items: legendItems, itemSpacing: 1)
        )
      )

    case "bullet-chart":
      return FixtureSpec(
        name: name,
        size: .init(width: 28, height: 2),
        view: AnyView(
          BulletChart("Rollout", value: 72, target: 90, total: 100, tone: .success, barWidth: 14)
        )
      )

    case "comparison-chart":
      return FixtureSpec(
        name: name,
        size: .init(width: 30, height: 4),
        view: AnyView(
          ComparisonChart("Regions", entries: comparisonEntries, barWidth: 10, labelWidth: 6)
        )
      )

    case "stacked-bar-chart":
      return FixtureSpec(
        name: name,
        size: .init(width: 28, height: 2),
        view: AnyView(
          StackedBarChart("Mix", entries: distributionEntries, total: 100, barWidth: 16)
        )
      )

    case "bar-chart":
      return FixtureSpec(
        name: name,
        size: .init(width: 30, height: 4),
        view: AnyView(
          BarChart("Queues", entries: queueEntries, barWidth: 12, labelWidth: 8)
        )
      )

    case "threshold-gauge":
      return FixtureSpec(
        name: name,
        size: .init(width: 28, height: 2),
        view: AnyView(
          ThresholdGauge("SLO", value: 84, total: 100, bands: thresholdBands, barWidth: 14)
        )
      )

    case "column-chart":
      return FixtureSpec(
        name: name,
        size: .init(width: 24, height: 6),
        view: AnyView(
          ColumnChart("Load", entries: queueEntries, chartHeight: 4, columnWidth: 2)
        )
      )

    case "heat-strip":
      return FixtureSpec(
        name: name,
        size: .init(width: 24, height: 3),
        view: AnyView(
          HeatStrip("Errors", entries: distributionEntries, cellWidth: 2)
        )
      )

    case "calendar-heatmap":
      return FixtureSpec(
        name: name,
        size: .init(width: 60, height: 11),
        view: AnyView(
          CalendarHeatmap(
            "Activity",
            days: calendarHeatmapDays,
            range: calendarHeatmapRange,
            weekStart: .monday,
            calendar: utcGregorianCalendar,
            cellWidth: 1
          )
        )
      )

    case "line-chart-three-series":
      return FixtureSpec(
        name: name,
        size: .init(width: 60, height: 12),
        view: AnyView(
          LineChart(
            "Tokens per Day",
            series: tokenSeries(),
            height: 8
          )
          .chartXAxis(.dates(every: .week))
          .chartYAxis(.values(count: 5))
          .chartLegend(.bottom)
        )
      )

    default:
      return FixtureSpec(
        name: name,
        size: .init(width: 1, height: 1),
        view: AnyView(Text("invalid"))
      )
    }
  }
}

private let nonAggregatingFixtureNames = [
  "empty-view",
  "text",
  "spacer",
  "divider",
  "label",
  "labeled-content",
  "toggle",
  "stepper",
  "text-field",
  "slider",
  "button",
  "progress-view",
  "meter",
  "sparkline",
  "timeline",
  "legend",
  "bullet-chart",
  "comparison-chart",
  "stacked-bar-chart",
  "bar-chart",
  "threshold-gauge",
  "column-chart",
  "heat-strip",
  "calendar-heatmap",
  "line-chart-three-series",
]

private struct FixtureSpec {
  let name: String
  let size: CellSize
  let identity: Identity
  let environmentValues: EnvironmentValues
  let view: AnyView

  init(
    name: String,
    size: CellSize,
    identity: Identity = testIdentity("Fixture"),
    environmentValues: EnvironmentValues = .init(),
    view: AnyView
  ) {
    self.name = name
    self.size = size
    self.identity = identity
    self.environmentValues = environmentValues
    self.view = view
  }
}

private func focusedEnvironmentValues(
  identity: Identity = testIdentity("Fixture")
) -> EnvironmentValues {
  var values = EnvironmentValues()
  values.focusedIdentity = identity
  return values
}

private let trafficSeries: [Double] = [24, 36, 32, 54, 72, 66, 84]

private let timelineEntries: [TimelineEntry] = [
  .init("Queued", detail: "Deploy added to wave 3", tone: .info),
  .init("Canary", detail: "4/10 hosts healthy", tone: .warning),
  .init("Complete", detail: "Waiting for regional closeout", tone: .success),
]

private let legendItems: [LegendItem] = [
  .init("live", tone: .info),
  .init("preset", tone: .success),
  .init("delta", tone: .warning),
]

private let comparisonEntries: [ComparisonEntry] = [
  .init("usw2", current: 72, baseline: 64, total: 100, tone: .success),
  .init("use1", current: 58, baseline: 61, total: 100, tone: .warning),
  .init("euw1", current: 81, baseline: 73, total: 100, tone: .info),
]

private let distributionEntries: [BarChartEntry] = [
  .init("A", value: 34, tone: .info),
  .init("B", value: 28, tone: .success),
  .init("C", value: 18, tone: .warning),
  .init("D", value: 20, tone: .critical),
]

private let queueEntries: [BarChartEntry] = [
  .init("sync", value: 18, tone: .info),
  .init("api", value: 12, tone: .success),
  .init("jobs", value: 8, tone: .warning),
]

private let thresholdBands: [ThresholdBand] = [
  .init(upTo: 50, tone: .critical),
  .init(upTo: 80, tone: .warning),
  .init(upTo: 100, tone: .success),
]

private let utcGregorianCalendar: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

private let calendarHeatmapRange: ClosedRange<Date> = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  formatter.timeZone = TimeZone(identifier: "UTC")
  return formatter.date(from: "2024-09-01")!...formatter.date(from: "2024-12-29")!
}()

private let calendarHeatmapDays: [DateValue] = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  formatter.timeZone = TimeZone(identifier: "UTC")
  func d(_ s: String) -> Date { formatter.date(from: s)! }
  return [
    DateValue(d("2024-09-03"), value: 2),
    DateValue(d("2024-09-04"), value: 1),
    DateValue(d("2024-09-10"), value: 4),
    DateValue(d("2024-09-17"), value: 5),
    DateValue(d("2024-10-01"), value: 8),
    DateValue(d("2024-10-15"), value: 6),
    DateValue(d("2024-11-04"), value: 3),
    DateValue(d("2024-11-22"), value: 9),
    DateValue(d("2024-12-09"), value: 7),
    DateValue(d("2024-12-23"), value: 10),
  ]
}()

private func tokenSeries() -> [LineChartSeries] {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  formatter.timeZone = TimeZone(identifier: "UTC")
  func d(_ s: String) -> Date { formatter.date(from: s)! }
  return [
    LineChartSeries("Opus 4.7", points: [
      .init(date: d("2024-09-01"), value: 1_200_000),
      .init(date: d("2024-09-08"), value: 3_400_000),
      .init(date: d("2024-09-15"), value: 5_100_000),
      .init(date: d("2024-09-22"), value: 4_200_000),
    ], tone: .info),
    LineChartSeries("Opus 4.6", points: [
      .init(date: d("2024-09-01"), value: 800_000),
      .init(date: d("2024-09-08"), value: 2_100_000),
      .init(date: d("2024-09-15"), value: 1_900_000),
      .init(date: d("2024-09-22"), value: 2_500_000),
    ], tone: .success),
    LineChartSeries("Haiku 4.5", points: [
      .init(date: d("2024-09-01"), value: 400_000),
      .init(date: d("2024-09-08"), value: 700_000),
      .init(date: d("2024-09-15"), value: 1_100_000),
      .init(date: d("2024-09-22"), value: 900_000),
    ], tone: .warning),
  ]
}
