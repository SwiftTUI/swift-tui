# Calendar Heatmap and Line Chart

Extend `SwiftTUICharts` with two new dashboard-grade primitives:

- **`CalendarHeatmap`** — a GitHub-style weekday × week intensity grid for
  daily activity over a long horizon.
- **`LineChart`** — a multi-series continuous plot with line, area, and
  step variants and a Date- or numeric-aware X axis.

Both views slot into the existing primitive-per-shape pattern used by
`BarChart`, `ColumnChart`, `Sparkline`, `HeatStrip`, etc. They reuse
`BannerTone`, `Legend`, `metricAccentStyle(for:)`, and the
`<Label, Summary>` generic ViewBuilder slots already established by the
module. No new protocols, no `Chart { ... }` builder, no environment
plumbing.

A deliberate light-composition layer is added on top of `LineChart` —
instance-method modifiers that return a transformed copy — to keep
axis and legend configuration off the initializer's argument list
without distorting the module's existing surface.

## Public surface

### New value types

All `Hashable & Sendable`, mirroring `BarChartEntry` / `ComparisonEntry`.

`DateValue` lives in `ChartModels.swift` alongside the other entry
types. The line-chart types get their own `LineChartModels.swift`
because there are more of them.

```swift
// ChartModels.swift
public struct DateValue: Hashable, Sendable {
  public var date: Date
  public var value: Double
  public init(_ date: Date, value: Double)
}

// LineChartModels.swift
public struct LineChartPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double)
}

extension LineChartPoint {
  public init(date: Date, value: Double)   // x = date.timeIntervalSinceReferenceDate
}

public struct LineChartSeries: Hashable, Sendable {
  public var label: String
  public var points: [LineChartPoint]
  public var style: LineChartSeriesStyle
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ label: S,
    points: [LineChartPoint],
    style: LineChartSeriesStyle = .line,
    tone: BannerTone = .automatic
  )
}

public enum LineChartSeriesStyle: Hashable, Sendable {
  case line     // single-cell line raster
  case area     // line + shaded fill below to baseline
  case step     // staircase between samples
}
```

Notes on the choices:

- `LineChartPoint` is a plain `(Double, Double)` so non-time data
  works too. The `Date` initializer is sugar that converts via
  `timeIntervalSinceReferenceDate`. The X-axis formatter is what
  knows the values represent a date — points stay numeric.
- `LineChartSeries` carries a `BannerTone` exactly like every other
  entry type; `.automatic` resolves to `.tint`, so wrapping a chart
  in `.foregroundStyle(.green)` colors all `.automatic` series, as
  it does for the existing primitives.
- `style` is a per-series enum, not a chart-wide flag. Mixed
  line/area/step in one plot is common in dashboards; chart-wide
  one-style-fits-all is the rare case.

### `CalendarHeatmap`

```swift
public struct CalendarHeatmap<Label: View, Summary: View>: View, ResolvableView {
  public var days: [DateValue]
  public var range: ClosedRange<Date>?         // nil → infer from days
  public var weekStart: CalendarHeatmapWeekStart
  public var calendar: Calendar
  public var cellWidth: Int
  public var showsMonthHeader: Bool
  public var showsDayLabels: Bool
  public var showsScaleLegend: Bool             // "Less ░ ▒ ▓ █ More"
  public var tone: BannerTone

  public init(
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  )
}

public enum CalendarHeatmapWeekStart: Hashable, Sendable {
  case sunday
  case monday
}

extension CalendarHeatmap where Label == EmptyView, Summary == Text { /* ... */ }
extension CalendarHeatmap where Label == Text,      Summary == Text {
  public init<S: StringProtocol>(_ title: S, days: [DateValue], ...)
}
```

The chart internally:

- Computes the displayed range (from `range` if provided, otherwise
  inferred from `days`).
- Buckets days into a 7-row × N-column grid using `calendar` and
  `weekStart`. Duplicate dates have their values summed; missing
  in-range dates render as a single `·`; out-of-range cells render
  as a single space.
- Computes per-cell intensity using the existing `heatStripGlyph`
  4-step ramp (`░▒▓█`) for visual coherence with `HeatStrip`.
- Renders a month-header row aligned to the first column where each
  new month begins.
- Renders day-of-week labels on the left, every other row labeled to
  match the screenshot reference (`Mon`, `Wed`, `Fri`).
- Renders the "Less ░ ▒ ▓ █ More" scale legend underneath via a
  `Legend`-style strip when `showsScaleLegend == true`.

### `LineChart`

```swift
public struct LineChart<Label: View, Summary: View>: View, ResolvableView {
  public var series: [LineChartSeries]
  public var height: Int
  public var width: Int?                        // nil → use available
  public var xAxis: LineChartXAxis
  public var yAxis: LineChartYAxis
  public var legend: LineChartLegendConfig
  public var baseline: LineChartBaseline        // .zero / .auto

  public init(
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  )
}

extension LineChart where Label == EmptyView, Summary == Text { /* ... */ }
extension LineChart where Label == Text,      Summary == Text {
  public init<S: StringProtocol>(_ title: S, series: [LineChartSeries], ...)
}
```

### The modifier surface

Plain instance methods that return a transformed copy of the chart.
Not environment-driven `ViewModifier`s. Every other chart in this
module is configured by initializer arguments; struct mutators let us
keep that flavor while still reading like SwiftUI at the call site.
This also avoids leaking modifier state through environment, which
would distort the module's existing surface (see the module's own
docc note warning against this).

```swift
extension LineChart {
  public func chartXAxis(_ axis: LineChartXAxis) -> Self
  public func chartYAxis(_ axis: LineChartYAxis) -> Self
  public func chartLegend(_ config: LineChartLegendConfig) -> Self
  public func chartBaseline(_ baseline: LineChartBaseline) -> Self
}

public struct LineChartXAxis: Hashable, Sendable {
  public var ticks: Ticks
  public var format: Format
  public var isHidden: Bool

  public enum Ticks: Hashable, Sendable {
    case automatic               // 4–6 evenly spaced
    case count(Int)
    case every(stride: Double)
    case dates(every: DateAxisStride)
  }

  public enum Format: Hashable, Sendable {
    case automatic
    case number(FloatingPointFormatStyle<Double>)
    case date(Date.FormatStyle)
  }

  public static func dates(
    every: DateAxisStride,
    format: Date.FormatStyle = .dateTime.month(.abbreviated).day()
  ) -> Self
  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number
  ) -> Self
  public static let automatic: Self
  public static let hidden: Self
}

public struct LineChartYAxis: Hashable, Sendable {
  public var ticks: Ticks       // same as X, minus .dates
  public var format: FloatingPointFormatStyle<Double>
  public var isHidden: Bool
  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number.notation(.compactName)
  ) -> Self
  public static let automatic: Self
  public static let hidden: Self
}

public enum DateAxisStride: Hashable, Sendable {
  case day, week, month, quarter, year
}

public struct LineChartLegendConfig: Hashable, Sendable {
  public enum Position: Hashable, Sendable { case top, bottom, hidden }
  public var position: Position
  public var itemSpacing: Int
  public static let bottom: Self
  public static let top: Self
  public static let hidden: Self
}

public enum LineChartBaseline: Hashable, Sendable {
  case zero       // areas/step bars anchored at 0
  case auto       // anchored at min(Y) across visible series
}
```

`CalendarHeatmap` gets only one modifier — its layout is fixed by
the date math:

```swift
extension CalendarHeatmap {
  public func chartLegend(_ config: LineChartLegendConfig) -> Self
}
```

`LineChartBaseline` separates "where do `.area` fills anchor" from
"what Y range does the axis show". `.auto` is right for non-zero
time series (e.g., token counts in the 1M–5M range — anchoring at 0
would waste 70% of the plot height); `.zero` is right for counts
and percentages.

### Call sites

```swift
// Calendar heatmap, GitHub-style
CalendarHeatmap("Activity", days: dailyCounts, weekStart: .monday)

// Token-usage line chart with three series and a Date X axis
LineChart(
  "Tokens per Day",
  series: [
    .init("Opus 4.7", points: opus47, tone: .info),
    .init("Opus 4.6", points: opus46, tone: .success),
    .init("Haiku 4.5", points: haiku45, tone: .warning),
  ],
  height: 8
)
.chartXAxis(.dates(every: .week, format: .dateTime.month(.abbreviated).day()))
.chartYAxis(.values(count: 6, format: .number.notation(.compactName)))
.chartLegend(.bottom)
```

## Internal rendering

Two new internal-helper files match the existing `ChartSupport.swift`
style: free `@MainActor func`s and `@ViewBuilder` builders, no
protocols.

### `CalendarHeatmapSupport.swift`

```text
1. inferDateRange(_ days: [DateValue]) -> ClosedRange<Date>
2. bucketDays(_ days: [DateValue],
              range: ClosedRange<Date>,
              calendar: Calendar,
              weekStart: CalendarHeatmapWeekStart)
   -> (grid: [[Double?]], monthHeader: [String], dayLabels: [String])
3. heatStripGlyph(value:maximumValue:)    // already exists in ChartSupport, reused
4. @ViewBuilder calendarHeatmapBody(grid:monthHeader:dayLabels:cellWidth:tone:)
```

The grid is 7 rows (weekdays) × N columns (weeks). `nil` cells fall
into two visual classes:

- **Out of range** → single space.
- **In range, zero or missing** → single `·` (matches the dot density
  in the screenshot reference and distinguishes "no activity" from
  "not in the chart's window").

### `LineChartSupport.swift`

```text
1. plotDomain(series:) -> (x: ClosedRange<Double>, y: ClosedRange<Double>)
2. plotGrid(width:height:domain:) -> CellRect            // reuses CellRect from Core
3. rasterize(series:into:baseline:) -> [[Cell]]          // per-style branch
   - line:  Bresenham between consecutive (x,y) cells, glyph "•" or "█"
   - area:  same line plus shaded fill below to baseline (shade glyph "▒")
   - step:  horizontal segment then vertical, no diagonal
4. yAxisTickLabels(domain:ticks:format:) -> [(row: Int, text: String)]
5. xAxisTickLabels(domain:ticks:format:plotWidth:) -> [(col: Int, text: String)]
6. @ViewBuilder lineChartBody(...)
```

`Y` domain is computed over the actual point range, including
negatives. With `LineChartBaseline.zero`, area fills anchor at 0 and
are clipped by the plot rectangle when 0 falls outside the visible Y
range. With `.auto`, fills anchor at `min(Y)` across visible series.

`.dates(every: .week)` (and the other `DateAxisStride` cases) snap
ticks to calendar boundaries — i.e., every tick is the start of a
week / month / quarter in the chart's calendar (defaulted to
`Calendar(identifier: .gregorian)` for determinism in tests; callers
can override via the future `.dates(every:format:calendar:)` overload
if needed). It does **not** mean "step by N days from the first
sample." This matches the behavior of Apple Charts' `.stride(by:)`
on a `Date` domain and is the only interpretation that produces
month-aligned labels in the screenshot reference.

Z-order rule when multiple series overlap in the same cell: last
series in the array wins, but `.area` fills are drawn first across
all series, then lines and steps on top. Lines remain visible when
an area passes behind them — matching the screenshot reference.

### Forward compatibility with an interactive cursor

The existing `ChartCoordinateConversion.swift` already provides
`chartFraction(at:in:axis:)` and
`chartDomainValue(at:in:domain:axis:)`. The cursor is not in v1, but
designing `rasterize` to emit a coordinate-mapped grid keeps the
door open: a future tranche can add a `LineChart` extension plus a
`@FocusState` and read `plotDomain` without an internal refactor.

## Files added or changed

```text
Sources/SwiftTUICharts/
  ChartModels.swift                    [+ DateValue]
  CalendarHeatmap.swift                [new]
  CalendarHeatmapSupport.swift         [new, internal]
  LineChart.swift                      [new]
  LineChartModels.swift                [new]
  LineChartAxes.swift                  [new]
  LineChartSupport.swift               [new, internal]
  SwiftTUICharts.docc/
    SwiftTUICharts.md                  [+ Charts/Support Types entries]
    Building-Dashboards.md             [+ section showing both visualizations]
```

Eight files, two of them tiny model files, four under ~150 lines
each — in line with the rest of the target (`Sparkline.swift` at 96
lines, `BarChart.swift` at 113 lines, the support file at ~615 lines
being the outlier we're matching for shared helpers).

`CalendarHeatmap.swift`, `CalendarHeatmapSupport.swift`, and the
`Date`-convenience extensions in `LineChartModels.swift` and
`LineChartAxes.swift` `import Foundation`. The existing chart files
don't, but `Date.FormatStyle` and `Calendar` make Foundation
unavoidable here. The core `LineChart` view itself stays
Foundation-free — only the optional Date sugar pulls it in.

## Tests

Snapshot-style "render to string and compare" tests, added to the
existing `Tests/SwiftTUITests` umbrella (where chart-adjacent tests
already live based on the test target's dependencies):

```text
Tests/SwiftTUITests/Charts/
  CalendarHeatmapRenderTests.swift     // grid bucketing + rendered output
  CalendarHeatmapDateMathTests.swift   // weekStart, Calendar edge cases, DST
  LineChartRenderTests.swift           // line / area / step rasterization
  LineChartAxisTests.swift             // tick selection, formatting
  LineChartSeriesTests.swift           // multi-series z-order, empty series
  Fixtures/
    calendar-heatmap-year.txt
    line-chart-three-series.txt
    line-chart-area-and-step.txt
```

Goldens are plain `.txt` for trivial diffability. Date math tests
pin `Calendar(identifier: .gregorian)` and an explicit `TimeZone`
to keep results deterministic across CI machines.

## Out of scope

Named explicitly so they don't leak into implementation:

- Interactive cursor / value readout (infra is ready in
  `ChartCoordinateConversion.swift`; defer until needed).
- Stacked area (`.area` is solo-fill; layering multiple areas
  renders, but does not sum them).
- Logarithmic or non-linear Y.
- Dual Y-axis.
- Annotations and trendlines.
- A generic `Plottable` X-axis type — `Double` + Date sugar is
  enough for the two motivating examples and keeps the surface
  matching the rest of the module.
- Custom heatmap ramps (locked to `░▒▓█` for visual coherence with
  `HeatStrip`).
- The "All time / Last 7 / Last 30" chip row — caller pre-filters
  the series it hands to `LineChart`. If this becomes a common
  pattern, a thin `TimeWindowPicker` view could be added to
  `SwiftTUIViews` in a separate tranche; it does not belong inside
  the chart.
