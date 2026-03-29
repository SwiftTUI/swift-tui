import TerminalUICharts
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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
          Label("Endpoint") {
            Text("◎")
          }
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
]

private struct FixtureSpec {
  let name: String
  let size: Size
  let identity: Identity
  let environmentValues: EnvironmentValues
  let view: AnyView

  init(
    name: String,
    size: Size,
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
  values.parallelFocusedIdentity = identity
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
