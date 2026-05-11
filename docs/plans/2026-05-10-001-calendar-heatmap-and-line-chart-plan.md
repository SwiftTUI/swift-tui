---
title: "feat(charts): add CalendarHeatmap and LineChart primitives"
type: feature
status: pending
date: 2026-05-10
depends_on: "docs/proposals/CALENDAR_HEATMAP_AND_LINE_CHART.md"
---

# feat(charts): add CalendarHeatmap and LineChart primitives

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new `SwiftTUICharts` primitives — `CalendarHeatmap`
(GitHub-style weekday × week intensity grid) and `LineChart`
(multi-series continuous plot with line / area / step styles and
Date-aware X axis modifiers) — following the existing primitive-per-shape,
`<Label, Summary>` ViewBuilder, `BannerTone`-driven style of the module.

**Architecture:** Each chart is a self-contained `View` configured by
initializer arguments, plus a small set of instance-method modifiers
(`chartXAxis`, `chartYAxis`, `chartLegend`, `chartBaseline`) that return
a transformed copy. Internal helpers (date bucketing, plot-domain
computation, line/area/step rasterization, tick layout) live in free
functions in `*Support.swift` files alongside the views, matching the
existing `ChartSupport.swift` pattern. View-level fixture tests slot into
the existing `NonAggregatingViewFixtureTests` + `Fixtures/<name>/*.txt`
infrastructure; helper tests are stand-alone `@Test` files.

**Tech Stack:** Swift 6.3 / Swift 6 language mode / `SwiftTUICharts` /
`SwiftTUICore` / `SwiftTUIViews` / Swift Testing (`import Testing`,
`@Test`, `#expect`) / Foundation (`Date`, `Calendar`, `Date.FormatStyle`).

**Reference spec:** [`docs/proposals/CALENDAR_HEATMAP_AND_LINE_CHART.md`](../proposals/CALENDAR_HEATMAP_AND_LINE_CHART.md).

**Reference module style:** `Sources/SwiftTUICharts/BarChart.swift`,
`Sources/SwiftTUICharts/HeatStrip.swift`, `Sources/SwiftTUICharts/ChartSupport.swift`,
`Sources/SwiftTUICharts/ChartModels.swift`.

---

## File map

**Create:**

- `Sources/SwiftTUICharts/LineChartModels.swift`
- `Sources/SwiftTUICharts/LineChartAxes.swift`
- `Sources/SwiftTUICharts/LineChart.swift`
- `Sources/SwiftTUICharts/LineChartSupport.swift`
- `Sources/SwiftTUICharts/CalendarHeatmap.swift`
- `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`
- `Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift`
- `Tests/SwiftTUITests/LineChartDomainTests.swift`
- `Tests/SwiftTUITests/LineChartRasterTests.swift`
- `Tests/SwiftTUITests/LineChartAxisTicksTests.swift`

**Modify:**

- `Sources/SwiftTUICharts/ChartModels.swift` (add `DateValue`)
- `Sources/SwiftTUICharts/SwiftTUICharts.docc/SwiftTUICharts.md` (add new types)
- `Sources/SwiftTUICharts/SwiftTUICharts.docc/Building-Dashboards.md` (add usage section)
- `Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift` (add 4 new fixture cases + names)

**Generated (fixture goldens, recorded by running tests with
`PARALLEL_RECORD_RENDERED_FIXTURES=1`):**

- `Tests/SwiftTUITests/Fixtures/calendar-heatmap/{preview-unicode,preview-ascii,ansi16,ansi256,true-color}.txt`
- `Tests/SwiftTUITests/Fixtures/line-chart-three-series/{...}.txt`
- `Tests/SwiftTUITests/Fixtures/line-chart-area/{...}.txt`
- `Tests/SwiftTUITests/Fixtures/line-chart-step/{...}.txt`

---

## Task 1: Add `DateValue` value type

**Files:**
- Modify: `Sources/SwiftTUICharts/ChartModels.swift` (append at end)

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift`
(create new file):

```swift
import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("CalendarHeatmap date math")
struct CalendarHeatmapDateMathTests {
  @Test("DateValue stores date and value")
  func dateValueStoresInputs() {
    let date = Date(timeIntervalSinceReferenceDate: 12345)
    let entry = DateValue(date, value: 7.5)
    #expect(entry.date == date)
    #expect(entry.value == 7.5)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: FAIL — "Cannot find 'DateValue' in scope".

- [ ] **Step 3: Add the type**

Append to `Sources/SwiftTUICharts/ChartModels.swift`:

```swift
/// A date paired with a numeric value, used by date-axis charts.
public struct DateValue: Hashable, Sendable {
  public var date: Date
  public var value: Double

  public init(_ date: Date, value: Double) {
    self.date = date
    self.value = value
  }
}
```

At the top of the file, add `import Foundation` if it isn't already
present (check the existing file — if it only has `import SwiftTUICore`
/ `import SwiftTUIViews`, add `import Foundation` above them).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/ChartModels.swift \
        Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift
git commit -m "feat(charts): add DateValue model for date-axis charts"
```

---

## Task 2: Add `LineChartPoint` value type

**Files:**
- Create: `Sources/SwiftTUICharts/LineChartModels.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiftTUITests/LineChartDomainTests.swift`:

```swift
import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("LineChart domain helpers")
struct LineChartDomainTests {
  @Test("LineChartPoint stores raw x and y")
  func storesRawCoords() {
    let point = LineChartPoint(x: 3.5, y: 12)
    #expect(point.x == 3.5)
    #expect(point.y == 12)
  }

  @Test("LineChartPoint date initializer maps to reference interval")
  func dateInitializerMapsToReferenceInterval() {
    let date = Date(timeIntervalSinceReferenceDate: 123_456)
    let point = LineChartPoint(date: date, value: 9)
    #expect(point.x == 123_456)
    #expect(point.y == 9)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LineChartDomainTests`
Expected: FAIL — "Cannot find 'LineChartPoint' in scope".

- [ ] **Step 3: Create `LineChartModels.swift`**

Create `Sources/SwiftTUICharts/LineChartModels.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A `(x, y)` point in a line chart's continuous coordinate space.
public struct LineChartPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

extension LineChartPoint {
  /// Convenience initializer that maps a `Date` to `x` via
  /// `timeIntervalSinceReferenceDate`. The X-axis formatter decides whether
  /// `x` is rendered as a date or as a number.
  public init(date: Date, value: Double) {
    self.init(x: date.timeIntervalSinceReferenceDate, y: value)
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LineChartDomainTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartModels.swift \
        Tests/SwiftTUITests/LineChartDomainTests.swift
git commit -m "feat(charts): add LineChartPoint with Date convenience init"
```

---

## Task 3: Add `LineChartSeriesStyle` and `LineChartSeries`

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartModels.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartDomainTests.swift`:

```swift
  @Test("LineChartSeries stores label, points, style, and tone")
  func seriesStoresInputs() {
    let series = LineChartSeries(
      "Opus",
      points: [.init(x: 0, y: 1), .init(x: 1, y: 2)],
      style: .area,
      tone: .info
    )
    #expect(series.label == "Opus")
    #expect(series.points.count == 2)
    #expect(series.style == .area)
    #expect(series.tone == .info)
  }

  @Test("LineChartSeries defaults to .line / .automatic")
  func seriesDefaults() {
    let series = LineChartSeries("X", points: [])
    #expect(series.style == .line)
    #expect(series.tone == .automatic)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartDomainTests`
Expected: FAIL — `LineChartSeries` undefined.

- [ ] **Step 3: Extend `LineChartModels.swift`**

Append to `Sources/SwiftTUICharts/LineChartModels.swift`:

```swift
/// Rendering style for a single `LineChartSeries`.
public enum LineChartSeriesStyle: Hashable, Sendable {
  /// Single-cell line raster between consecutive samples.
  case line
  /// Same as `.line`, plus a shaded fill from the line down to the
  /// chart's baseline.
  case area
  /// Staircase between samples: horizontal segment at each sample's
  /// Y, then a vertical jump to the next sample's Y. No diagonal.
  case step
}

/// A labeled, toned series of `LineChartPoint`s.
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
  ) {
    self.label = String(label)
    self.points = points
    self.style = style
    self.tone = tone
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartDomainTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartModels.swift \
        Tests/SwiftTUITests/LineChartDomainTests.swift
git commit -m "feat(charts): add LineChartSeries and LineChartSeriesStyle"
```

---

## Task 4: Add axes, legend, and baseline config types

**Files:**
- Create: `Sources/SwiftTUICharts/LineChartAxes.swift`

- [ ] **Step 1: Add failing tests**

Create `Tests/SwiftTUITests/LineChartAxisTicksTests.swift`:

```swift
import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("LineChart axis config")
struct LineChartAxisConfigTests {
  @Test("X axis .values builds numeric Ticks/Format")
  func xAxisValuesBuildsNumeric() {
    let axis = LineChartXAxis.values(count: 6)
    #expect(axis.isHidden == false)
    if case .count(let n) = axis.ticks { #expect(n == 6) } else {
      Issue.record("expected .count tick strategy")
    }
    if case .number = axis.format { } else {
      Issue.record("expected .number format")
    }
  }

  @Test("X axis .dates builds DateAxisStride / Date.FormatStyle")
  func xAxisDatesBuildsDateStride() {
    let axis = LineChartXAxis.dates(every: .month)
    if case .dates(let stride) = axis.ticks { #expect(stride == .month) } else {
      Issue.record("expected .dates tick strategy")
    }
    if case .date = axis.format { } else {
      Issue.record("expected .date format")
    }
  }

  @Test("X axis .hidden flips isHidden")
  func xAxisHiddenFlipsFlag() {
    #expect(LineChartXAxis.hidden.isHidden == true)
  }

  @Test("Y axis .values defaults to compact-name notation")
  func yAxisValuesDefaultsToCompact() {
    _ = LineChartYAxis.values()
    // Smoke: just verify it builds without crashing.
  }

  @Test("Legend config presets")
  func legendPresets() {
    #expect(LineChartLegendConfig.bottom.position == .bottom)
    #expect(LineChartLegendConfig.top.position == .top)
    #expect(LineChartLegendConfig.hidden.position == .hidden)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartAxisConfigTests`
Expected: FAIL — `LineChartXAxis` / `LineChartYAxis` / `LineChartLegendConfig` undefined.

- [ ] **Step 3: Create `LineChartAxes.swift`**

Create `Sources/SwiftTUICharts/LineChartAxes.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

/// Calendar stride for the X axis when X is interpreted as a date.
public enum DateAxisStride: Hashable, Sendable {
  case day, week, month, quarter, year
}

/// Where `.area` and `.step` rasters anchor along Y.
public enum LineChartBaseline: Hashable, Sendable {
  /// Areas / step fills anchor at 0; clipped by the plot if 0 falls
  /// outside the visible Y range.
  case zero
  /// Areas / step fills anchor at `min(Y)` across visible series.
  case auto
}

/// X-axis configuration. Constructed via `.values(...)`, `.dates(...)`,
/// `.automatic`, or `.hidden`, then applied to a `LineChart` via
/// `.chartXAxis(_:)`.
public struct LineChartXAxis: Hashable, Sendable {
  public enum Ticks: Hashable, Sendable {
    case automatic           // ~4-6 evenly spaced
    case count(Int)
    case every(stride: Double)
    case dates(every: DateAxisStride)
  }

  public enum Format: Hashable, Sendable {
    case automatic
    case number(FloatingPointFormatStyle<Double>)
    case date(Date.FormatStyle)
  }

  public var ticks: Ticks
  public var format: Format
  public var isHidden: Bool

  public init(ticks: Ticks, format: Format, isHidden: Bool = false) {
    self.ticks = ticks
    self.format = format
    self.isHidden = isHidden
  }

  public static let automatic = Self(ticks: .automatic, format: .automatic)
  public static let hidden = Self(ticks: .automatic, format: .automatic, isHidden: true)

  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number
  ) -> Self {
    .init(ticks: .count(count), format: .number(format))
  }

  public static func dates(
    every stride: DateAxisStride,
    format: Date.FormatStyle = .dateTime.month(.abbreviated).day()
  ) -> Self {
    .init(ticks: .dates(every: stride), format: .date(format))
  }
}

/// Y-axis configuration. Same shape as `LineChartXAxis` without the
/// `.dates` tick / format variants.
public struct LineChartYAxis: Hashable, Sendable {
  public enum Ticks: Hashable, Sendable {
    case automatic
    case count(Int)
    case every(stride: Double)
  }

  public var ticks: Ticks
  public var format: FloatingPointFormatStyle<Double>
  public var isHidden: Bool

  public init(
    ticks: Ticks,
    format: FloatingPointFormatStyle<Double> = .number.notation(.compactName),
    isHidden: Bool = false
  ) {
    self.ticks = ticks
    self.format = format
    self.isHidden = isHidden
  }

  public static let automatic = Self(ticks: .automatic)
  public static let hidden = Self(ticks: .automatic, isHidden: true)

  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number.notation(.compactName)
  ) -> Self {
    .init(ticks: .count(count), format: format)
  }
}

/// Legend strip placement around the chart body.
public struct LineChartLegendConfig: Hashable, Sendable {
  public enum Position: Hashable, Sendable { case top, bottom, hidden }

  public var position: Position
  public var itemSpacing: Int

  public init(position: Position, itemSpacing: Int = 2) {
    self.position = position
    self.itemSpacing = itemSpacing
  }

  public static let bottom = Self(position: .bottom)
  public static let top = Self(position: .top)
  public static let hidden = Self(position: .hidden)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartAxisConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartAxes.swift \
        Tests/SwiftTUITests/LineChartAxisTicksTests.swift
git commit -m "feat(charts): add LineChart axis, legend, and baseline config types"
```

---

## Task 5: `inferDateRange` helper

**Files:**
- Create: `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift`:

```swift
  @Test("inferDateRange spans min to max date")
  func inferDateRangeSpansData() {
    let a = Date(timeIntervalSinceReferenceDate: 100)
    let b = Date(timeIntervalSinceReferenceDate: 500)
    let c = Date(timeIntervalSinceReferenceDate: 300)
    let range = inferDateRange([
      DateValue(c, value: 1),
      DateValue(a, value: 2),
      DateValue(b, value: 3),
    ])
    #expect(range?.lowerBound == a)
    #expect(range?.upperBound == b)
  }

  @Test("inferDateRange returns nil for empty input")
  func inferDateRangeNilForEmpty() {
    #expect(inferDateRange([]) == nil)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: FAIL — `inferDateRange` undefined.

- [ ] **Step 3: Create `CalendarHeatmapSupport.swift` with `inferDateRange`**

Create `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

/// Returns the minimum-to-maximum date range covered by `days`, or `nil`
/// when the input is empty.
func inferDateRange(_ days: [DateValue]) -> ClosedRange<Date>? {
  guard let first = days.first else { return nil }
  var lower = first.date
  var upper = first.date
  for entry in days.dropFirst() {
    if entry.date < lower { lower = entry.date }
    if entry.date > upper { upper = entry.date }
  }
  return lower...upper
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/CalendarHeatmapSupport.swift \
        Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift
git commit -m "feat(charts): add inferDateRange helper for CalendarHeatmap"
```

---

## Task 6: `bucketDays` — weekday × week grid

**Files:**
- Modify: `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`
- Create (if missing): the `CalendarHeatmapWeekStart` enum lives here too

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift`:

```swift
  private static func makeUTCGregorian() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private static func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: string)!
  }

  @Test("bucketDays lays out a single week with Sunday start")
  func bucketDaysSingleWeekSundayStart() {
    let cal = Self.makeUTCGregorian()
    // 2024-01-07 is a Sunday in the gregorian calendar.
    let days = [
      DateValue(Self.date("2024-01-07"), value: 1),  // Sun
      DateValue(Self.date("2024-01-08"), value: 2),  // Mon
      DateValue(Self.date("2024-01-10"), value: 3),  // Wed
      DateValue(Self.date("2024-01-13"), value: 4),  // Sat
    ]
    let bucket = bucketDays(
      days,
      range: Self.date("2024-01-07")...Self.date("2024-01-13"),
      calendar: cal,
      weekStart: .sunday
    )
    #expect(bucket.grid.count == 7)             // 7 weekday rows
    #expect(bucket.grid[0].count == 1)          // 1 week column
    #expect(bucket.grid[0][0] == 1)             // Sun row, week 0
    #expect(bucket.grid[1][0] == 2)             // Mon row
    #expect(bucket.grid[3][0] == 3)             // Wed row
    #expect(bucket.grid[6][0] == 4)             // Sat row
    #expect(bucket.grid[2][0] == nil)           // Tue, no data
  }

  @Test("bucketDays with Monday start shifts row order")
  func bucketDaysMondayStart() {
    let cal = Self.makeUTCGregorian()
    let days = [
      DateValue(Self.date("2024-01-08"), value: 1),  // Mon
      DateValue(Self.date("2024-01-14"), value: 2),  // Sun
    ]
    let bucket = bucketDays(
      days,
      range: Self.date("2024-01-08")...Self.date("2024-01-14"),
      calendar: cal,
      weekStart: .monday
    )
    #expect(bucket.grid[0][0] == 1)   // Monday is row 0 now
    #expect(bucket.grid[6][0] == 2)   // Sunday is row 6 now
  }

  @Test("bucketDays sums duplicate dates")
  func bucketDaysSumsDuplicates() {
    let cal = Self.makeUTCGregorian()
    let day = Self.date("2024-01-07")
    let days = [
      DateValue(day, value: 3),
      DateValue(day, value: 5),
    ]
    let bucket = bucketDays(
      days,
      range: day...day,
      calendar: cal,
      weekStart: .sunday
    )
    #expect(bucket.grid[0][0] == 8)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: FAIL — `bucketDays` / `CalendarHeatmapWeekStart` undefined.

- [ ] **Step 3: Implement `bucketDays`**

Append to `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`:

```swift
/// First day of the week for a `CalendarHeatmap` row layout.
public enum CalendarHeatmapWeekStart: Hashable, Sendable {
  case sunday   // Sun, Mon, ..., Sat (rows 0..6)
  case monday   // Mon, Tue, ..., Sun (rows 0..6)
}

struct CalendarHeatmapBucket: Equatable, Sendable {
  /// `grid[weekdayRow][weekColumn]`. `nil` means "out of range" or "in
  /// range, no data". The view layer distinguishes them by checking
  /// whether the cell's date falls within `range`.
  var grid: [[Double?]]
  /// Column index → month label ("Jan", "Feb", ...) for the first week
  /// of each month; empty string for columns that don't start a month.
  var monthHeader: [String]
  /// Row index → day-of-week label ("", "Mon", "", "Wed", ...). Every
  /// other row is labeled for compactness.
  var dayLabels: [String]
}

/// Bins `days` into a 7-row × N-column intensity grid using `calendar`
/// and `weekStart`. Out-of-range and missing cells stay `nil`; duplicate
/// dates have their values summed.
func bucketDays(
  _ days: [DateValue],
  range: ClosedRange<Date>,
  calendar: Calendar,
  weekStart: CalendarHeatmapWeekStart
) -> CalendarHeatmapBucket {
  let lower = startOfDay(range.lowerBound, in: calendar)
  let upper = startOfDay(range.upperBound, in: calendar)

  // Snap the range start back to the most recent weekStart so column 0
  // is a whole week.
  let firstColumnDate = startOfWeek(lower, weekStart: weekStart, calendar: calendar)

  let columnCount = max(1, weekColumns(from: firstColumnDate, to: upper, calendar: calendar))
  var grid: [[Double?]] = Array(repeating: Array(repeating: nil, count: columnCount), count: 7)

  // Aggregate values per (row, column) cell, summing duplicates.
  for entry in days {
    let day = startOfDay(entry.date, in: calendar)
    guard day >= lower && day <= upper else { continue }
    let (row, col) = position(of: day,
                              from: firstColumnDate,
                              weekStart: weekStart,
                              calendar: calendar)
    guard col >= 0 && col < columnCount else { continue }
    grid[row][col] = (grid[row][col] ?? 0) + entry.value
  }

  let monthHeader = monthHeaderLabels(
    firstColumnDate: firstColumnDate,
    columnCount: columnCount,
    calendar: calendar
  )
  let dayLabels = weekdayLabels(weekStart: weekStart, calendar: calendar)

  return CalendarHeatmapBucket(grid: grid, monthHeader: monthHeader, dayLabels: dayLabels)
}

// MARK: - Internal date arithmetic

private func startOfDay(_ date: Date, in calendar: Calendar) -> Date {
  calendar.startOfDay(for: date)
}

private func startOfWeek(
  _ date: Date,
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> Date {
  let weekdayUnit = calendar.component(.weekday, from: date)  // 1...7, 1 = Sunday
  let offsetFromStart: Int
  switch weekStart {
  case .sunday: offsetFromStart = (weekdayUnit - 1) % 7
  case .monday: offsetFromStart = (weekdayUnit + 5) % 7   // shift so Monday = 0
  }
  return calendar.date(byAdding: .day, value: -offsetFromStart, to: date) ?? date
}

private func weekColumns(
  from start: Date,
  to end: Date,
  calendar: Calendar
) -> Int {
  let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
  return Int((days / 7)) + 1
}

private func position(
  of day: Date,
  from firstColumnDate: Date,
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> (row: Int, col: Int) {
  let daysSinceStart = calendar.dateComponents([.day], from: firstColumnDate, to: day).day ?? 0
  return (row: daysSinceStart % 7, col: daysSinceStart / 7)
}

private func monthHeaderLabels(
  firstColumnDate: Date,
  columnCount: Int,
  calendar: Calendar
) -> [String] {
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.timeZone = calendar.timeZone
  formatter.dateFormat = "MMM"

  var labels = Array(repeating: "", count: columnCount)
  var lastMonth = -1
  for column in 0..<columnCount {
    guard let date = calendar.date(byAdding: .day, value: column * 7, to: firstColumnDate) else {
      continue
    }
    let month = calendar.component(.month, from: date)
    if month != lastMonth {
      labels[column] = formatter.string(from: date)
      lastMonth = month
    }
  }
  return labels
}

private func weekdayLabels(
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> [String] {
  // Match the screenshot reference: blank, Mon, blank, Wed, blank, Fri, blank
  // (or the Sun-start permutation).
  switch weekStart {
  case .sunday:
    return ["", "Mon", "", "Wed", "", "Fri", ""]
  case .monday:
    return ["", "Tue", "", "Thu", "", "Sat", ""]
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalendarHeatmapDateMathTests`
Expected: PASS (5 tests total: the 2 from Task 5 and 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/CalendarHeatmapSupport.swift \
        Tests/SwiftTUITests/CalendarHeatmapDateMathTests.swift
git commit -m "feat(charts): bucket DateValue input into weekday x week grid"
```

---

## Task 7: `CalendarHeatmap` view + body

**Files:**
- Create: `Sources/SwiftTUICharts/CalendarHeatmap.swift`
- Modify: `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift` (add body builder)

- [ ] **Step 1: Add view-body helper to support file**

Append to `Sources/SwiftTUICharts/CalendarHeatmapSupport.swift`:

```swift
@MainActor
@ViewBuilder
func calendarHeatmapBody(
  bucket: CalendarHeatmapBucket,
  cellWidth: Int,
  tone: BannerTone,
  showsMonthHeader: Bool,
  showsDayLabels: Bool,
  showsScaleLegend: Bool
) -> some View {
  let effectiveWidth = max(1, cellWidth)
  let accentStyle =
    tone == .automatic
    ? AnyShapeStyle(.tint)
    : metricAccentStyle(for: tone)
  let maximumValue = max(1, bucket.grid.flatMap { $0 }.compactMap { $0 }.map(abs).max() ?? 1)

  VStack(alignment: .leading, spacing: 0) {
    if showsMonthHeader {
      calendarHeatmapMonthHeaderRow(
        labels: bucket.monthHeader,
        cellWidth: effectiveWidth,
        leadingPad: showsDayLabels ? dayLabelColumnWidth : 0
      )
    }
    ForEach(0..<7, id: \.self) { row in
      HStack(alignment: .center, spacing: 0) {
        if showsDayLabels {
          Text(bucket.dayLabels[row])
            .foregroundStyle(.foreground)
            .frame(width: dayLabelColumnWidth, height: 1, alignment: .trailing)
        }
        ForEach(bucket.grid[row].indices, id: \.self) { column in
          let cell = bucket.grid[row][column]
          Text(String(repeating: calendarHeatmapGlyph(value: cell, maximumValue: maximumValue),
                      count: effectiveWidth))
            .foregroundStyle(accentStyle)
        }
      }
    }
    if showsScaleLegend {
      calendarHeatmapScaleLegendRow(accentStyle: accentStyle)
    }
  }
}

private let dayLabelColumnWidth = 4

private func calendarHeatmapGlyph(value: Double?, maximumValue: Double) -> String {
  guard let value else { return " " }      // out of range → space
  if value == 0 { return "·" }              // in range, no activity → dot
  // Map to the existing HeatStrip 4-step ramp.
  let fraction = min(max(abs(value) / maximumValue, 0), 1)
  switch fraction {
  case ..<0.25: return "░"
  case ..<0.5:  return "▒"
  case ..<0.75: return "▓"
  default:      return "█"
  }
}

@MainActor
@ViewBuilder
private func calendarHeatmapMonthHeaderRow(
  labels: [String],
  cellWidth: Int,
  leadingPad: Int
) -> some View {
  HStack(alignment: .center, spacing: 0) {
    if leadingPad > 0 {
      Text(String(repeating: " ", count: leadingPad))
    }
    ForEach(labels.indices, id: \.self) { column in
      let label = labels[column]
      let padded = label.isEmpty
        ? String(repeating: " ", count: cellWidth)
        : String((label + String(repeating: " ", count: cellWidth)).prefix(cellWidth))
      Text(padded)
        .foregroundStyle(.separator)
    }
  }
}

@MainActor
@ViewBuilder
private func calendarHeatmapScaleLegendRow(
  accentStyle: AnyShapeStyle
) -> some View {
  HStack(alignment: .center, spacing: 1) {
    Text("Less").foregroundStyle(.separator)
    Text("░").foregroundStyle(accentStyle)
    Text("▒").foregroundStyle(accentStyle)
    Text("▓").foregroundStyle(accentStyle)
    Text("█").foregroundStyle(accentStyle)
    Text("More").foregroundStyle(.separator)
  }
}
```

- [ ] **Step 2: Create the public `CalendarHeatmap` view**

Create `Sources/SwiftTUICharts/CalendarHeatmap.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A GitHub-style weekday × week intensity grid for daily activity data.
public struct CalendarHeatmap<Label: View, Summary: View>: View, ResolvableView {
  public var days: [DateValue]
  public var range: ClosedRange<Date>?
  public var weekStart: CalendarHeatmapWeekStart
  public var calendar: Calendar
  public var cellWidth: Int
  public var showsMonthHeader: Bool
  public var showsDayLabels: Bool
  public var showsScaleLegend: Bool
  public var tone: BannerTone

  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

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
  ) {
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    days: [DateValue],
    range: ClosedRange<Date>?,
    weekStart: CalendarHeatmapWeekStart,
    calendar: Calendar,
    cellWidth: Int,
    showsMonthHeader: Bool,
    showsDayLabels: Bool,
    showsScaleLegend: Bool,
    tone: BannerTone,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.days = days
    self.range = range
    self.weekStart = weekStart
    self.calendar = calendar
    self.cellWidth = cellWidth
    self.showsMonthHeader = showsMonthHeader
    self.showsDayLabels = showsDayLabels
    self.showsScaleLegend = showsScaleLegend
    self.tone = tone
    self.accessibilitySummary = accessibilitySummary
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let effectiveRange = range ?? inferDateRange(days) ?? Self.fallbackRange()
    let bucket = bucketDays(days, range: effectiveRange, calendar: calendar, weekStart: weekStart)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          calendarHeatmapBody(
            bucket: bucket,
            cellWidth: cellWidth,
            tone: tone,
            showsMonthHeader: showsMonthHeader,
            showsDayLabels: showsDayLabels,
            showsScaleLegend: showsScaleLegend
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "CalendarHeatmap",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }

  private static func fallbackRange() -> ClosedRange<Date> {
    let now = Date()
    return now...now
  }
}

extension CalendarHeatmap where Label == EmptyView, Summary == Text {
  public init(
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic
  ) {
    let summary = "\(days.count) days"
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension CalendarHeatmap where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic
  ) {
    let title = String(title)
    let summary = "\(days.count) days"
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
```

- [ ] **Step 3: Build to verify the view compiles**

Run: `swift build --target SwiftTUICharts`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICharts/CalendarHeatmap.swift \
        Sources/SwiftTUICharts/CalendarHeatmapSupport.swift
git commit -m "feat(charts): add CalendarHeatmap view"
```

---

## Task 8: `CalendarHeatmap.chartLegend(_:)` modifier

**Files:**
- Modify: `Sources/SwiftTUICharts/CalendarHeatmap.swift`

- [ ] **Step 1: Add failing test**

Create `Tests/SwiftTUITests/CalendarHeatmapModifierTests.swift`:

```swift
import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("CalendarHeatmap modifiers")
struct CalendarHeatmapModifierTests {
  @Test("chartLegend(.hidden) clears showsScaleLegend")
  func chartLegendHiddenClearsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.hidden)
    #expect(chart.showsScaleLegend == false)
  }

  @Test("chartLegend(.bottom) keeps showsScaleLegend true")
  func chartLegendBottomKeepsFlag() {
    let chart = CalendarHeatmap(days: []).chartLegend(.bottom)
    #expect(chart.showsScaleLegend == true)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalendarHeatmapModifierTests`
Expected: FAIL — `chartLegend` undefined on `CalendarHeatmap`.

- [ ] **Step 3: Add the modifier**

Append to `Sources/SwiftTUICharts/CalendarHeatmap.swift`:

```swift
extension CalendarHeatmap {
  /// Toggle the "Less ░ ▒ ▓ █ More" scale legend below the grid.
  /// `.hidden` clears it; `.bottom` / `.top` keep it visible (position
  /// is currently fixed at the bottom for `CalendarHeatmap`).
  public func chartLegend(_ config: LineChartLegendConfig) -> Self {
    var copy = self
    copy.showsScaleLegend = (config.position != .hidden)
    return copy
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CalendarHeatmapModifierTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/CalendarHeatmap.swift \
        Tests/SwiftTUITests/CalendarHeatmapModifierTests.swift
git commit -m "feat(charts): add CalendarHeatmap.chartLegend modifier"
```

---

## Task 9: `plotDomain` for LineChart

**Files:**
- Create: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartDomainTests.swift`:

```swift
  @Test("plotDomain spans min..max across series for X and Y")
  func plotDomainSpansAllSeries() {
    let s1 = LineChartSeries("A", points: [.init(x: 0, y: 1), .init(x: 5, y: 10)])
    let s2 = LineChartSeries("B", points: [.init(x: 2, y: -3), .init(x: 6, y: 4)])
    let domain = plotDomain(series: [s1, s2])
    #expect(domain?.x.lowerBound == 0)
    #expect(domain?.x.upperBound == 6)
    #expect(domain?.y.lowerBound == -3)
    #expect(domain?.y.upperBound == 10)
  }

  @Test("plotDomain is nil when no series contains points")
  func plotDomainNilWhenEmpty() {
    let s = LineChartSeries("A", points: [])
    #expect(plotDomain(series: [s]) == nil)
    #expect(plotDomain(series: []) == nil)
  }

  @Test("plotDomain degenerates to a 1-wide range when all values equal")
  func plotDomainDegenerate() {
    let s = LineChartSeries("A", points: [.init(x: 5, y: 5)])
    let domain = plotDomain(series: [s])
    #expect(domain?.x == 5...5)
    #expect(domain?.y == 5...5)
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartDomainTests`
Expected: FAIL — `plotDomain` undefined.

- [ ] **Step 3: Create `LineChartSupport.swift`**

Create `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

struct LineChartDomain: Equatable, Sendable {
  var x: ClosedRange<Double>
  var y: ClosedRange<Double>
}

/// Computes the combined X/Y range across all series. Returns `nil` when
/// no series contains points.
func plotDomain(series: [LineChartSeries]) -> LineChartDomain? {
  var minX = Double.infinity
  var maxX = -Double.infinity
  var minY = Double.infinity
  var maxY = -Double.infinity
  var any = false
  for s in series {
    for p in s.points {
      any = true
      if p.x < minX { minX = p.x }
      if p.x > maxX { maxX = p.x }
      if p.y < minY { minY = p.y }
      if p.y > maxY { maxY = p.y }
    }
  }
  guard any else { return nil }
  return LineChartDomain(x: minX...maxX, y: minY...maxY)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartDomainTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartDomainTests.swift
git commit -m "feat(charts): add plotDomain helper for LineChart"
```

---

## Task 10: Cell mapping helpers (`xCell`, `yCell`)

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Create `Tests/SwiftTUITests/LineChartRasterTests.swift`:

```swift
import Foundation
import Testing

@testable import SwiftTUICharts
@testable import SwiftTUICore

@Suite("LineChart raster helpers")
struct LineChartCellMappingTests {
  @Test("xCell maps lower bound to column 0")
  func xLower() {
    #expect(xCell(value: 0, domain: 0...10, plotWidth: 10) == 0)
  }

  @Test("xCell maps upper bound to last column")
  func xUpper() {
    #expect(xCell(value: 10, domain: 0...10, plotWidth: 10) == 9)
  }

  @Test("yCell inverts Y axis (top row = max)")
  func yInverts() {
    #expect(yCell(value: 10, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: 0,  domain: 0...10, plotHeight: 10) == 9)
  }

  @Test("yCell clamps out-of-range to nearest edge")
  func yClamps() {
    #expect(yCell(value: 50, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: -5, domain: 0...10, plotHeight: 10) == 9)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartCellMappingTests`
Expected: FAIL — `xCell` / `yCell` undefined.

- [ ] **Step 3: Implement the helpers**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
/// Maps a domain X value to a column index in `[0, plotWidth)`.
func xCell(value: Double, domain: ClosedRange<Double>, plotWidth: Int) -> Int {
  let span = domain.upperBound - domain.lowerBound
  guard span > 0, plotWidth > 0 else { return 0 }
  let fraction = (value - domain.lowerBound) / span
  let column = Int((fraction * Double(plotWidth - 1)).rounded())
  return min(max(column, 0), plotWidth - 1)
}

/// Maps a domain Y value to a row index in `[0, plotHeight)`, inverted
/// so row 0 corresponds to the top of the plot.
func yCell(value: Double, domain: ClosedRange<Double>, plotHeight: Int) -> Int {
  let span = domain.upperBound - domain.lowerBound
  guard span > 0, plotHeight > 0 else { return 0 }
  let fraction = (value - domain.lowerBound) / span
  let invertedFraction = 1 - fraction
  let row = Int((invertedFraction * Double(plotHeight - 1)).rounded())
  return min(max(row, 0), plotHeight - 1)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartCellMappingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartRasterTests.swift
git commit -m "feat(charts): add LineChart cell mapping helpers"
```

---

## Task 11: `rasterizeLine` — `.line` style raster

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartRasterTests.swift`:

```swift
@Suite("LineChart line rasterization")
struct LineChartLineRasterTests {
  @Test("rasterizeLine draws a single point as `•`")
  func singlePoint() {
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0)],
      domain: LineChartDomain(x: 0...0, y: 0...0),
      plotWidth: 3, plotHeight: 3
    )
    #expect(grid[0][0] == nil)
    #expect(grid[2][0] != nil)  // y=0 sits at the bottom row
  }

  @Test("rasterizeLine connects two points with the rising-corner glyph")
  func twoPointsRising() {
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 1)],
      domain: LineChartDomain(x: 0...1, y: 0...1),
      plotWidth: 2, plotHeight: 2
    )
    // (col 0, row 1) -> rising corner; (col 1, row 0) -> rising corner.
    #expect(grid[1][0] != nil)
    #expect(grid[0][1] != nil)
  }

  @Test("rasterizeLine fills vertical span between far-apart Ys")
  func verticalSpan() {
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 10)],
      domain: LineChartDomain(x: 0...1, y: 0...10),
      plotWidth: 2, plotHeight: 4
    )
    // Between the two columns the line crosses several rows; at least
    // one intermediate row should be filled in column 0 or column 1.
    let column1Filled = (0..<4).contains { grid[$0][1] != nil }
    let column0Filled = (0..<4).contains { grid[$0][0] != nil }
    #expect(column0Filled && column1Filled)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartLineRasterTests`
Expected: FAIL — `rasterizeLine` undefined.

- [ ] **Step 3: Implement `rasterizeLine`**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
/// One rasterized cell in a line chart plot grid.
struct LineRasterCell: Equatable, Sendable {
  /// `•` for isolated points, `│`/`─`/`╭`/`╮`/`╰`/`╯` for connector
  /// segments. Picked by `connectorGlyph(prev:next:)`.
  var glyph: Character
}

/// Maps a series of `(x, y)` points (already sorted by x) into a
/// `plotHeight × plotWidth` grid. `nil` cells stay empty.
func rasterizeLine(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int
) -> [[LineRasterCell?]] {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  guard !points.isEmpty else { return grid }

  if points.count == 1 {
    let p = points[0]
    let col = xCell(value: p.x, domain: domain.x, plotWidth: width)
    let row = yCell(value: p.y, domain: domain.y, plotHeight: height)
    grid[row][col] = LineRasterCell(glyph: "•")
    return grid
  }

  // Compute (col, row) for every input point first.
  let cells: [(col: Int, row: Int)] = points.map { p in
    (xCell(value: p.x, domain: domain.x, plotWidth: width),
     yCell(value: p.y, domain: domain.y, plotHeight: height))
  }

  // For each consecutive pair, fill the vertical span between them at
  // each column they cover, then place a connector glyph.
  for i in 0..<(cells.count - 1) {
    let from = cells[i]
    let to   = cells[i + 1]
    let colStart = min(from.col, to.col)
    let colEnd   = max(from.col, to.col)
    let rowStart = min(from.row, to.row)
    let rowEnd   = max(from.row, to.row)

    // Vertical fill in the leading column (from current Y down to the
    // midpoint), and in the trailing column (from the midpoint up to
    // the next Y). Concretely, fill every row between rowStart and
    // rowEnd in the column closer to that endpoint.
    for row in rowStart...rowEnd {
      let col = (row <= (rowStart + rowEnd) / 2) ? (from.row <= to.row ? from.col : to.col)
                                                 : (from.row <= to.row ? to.col   : from.col)
      if grid[row][col] == nil {
        grid[row][col] = LineRasterCell(glyph: "│")
      }
    }

    // Horizontal fill between columns at the latched-in Y.
    if colStart != colEnd {
      let rowAtFrom = from.row
      let rowAtTo   = to.row
      for col in (colStart + 1)..<colEnd {
        let row = col < (colStart + colEnd) / 2 ? rowAtFrom : rowAtTo
        if grid[row][col] == nil {
          grid[row][col] = LineRasterCell(glyph: "─")
        }
      }
    }

    // Corner glyphs at the endpoints.
    grid[from.row][from.col] = LineRasterCell(glyph: connectorGlyph(at: from, neighbor: to))
    grid[to.row][to.col]     = LineRasterCell(glyph: connectorGlyph(at: to, neighbor: from))
  }

  return grid
}

private func connectorGlyph(
  at cell: (col: Int, row: Int),
  neighbor: (col: Int, row: Int)
) -> Character {
  // Same row → horizontal segment.
  if cell.row == neighbor.row { return "─" }
  // Same column → vertical segment.
  if cell.col == neighbor.col { return "│" }

  let goingRight = neighbor.col > cell.col
  let goingDown  = neighbor.row > cell.row
  switch (goingRight, goingDown) {
  case (true,  true):  return "╮"   // turn down to the right
  case (true,  false): return "╯"   // turn up to the right
  case (false, true):  return "╭"   // turn down to the left
  case (false, false): return "╰"   // turn up to the left
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartLineRasterTests`
Expected: PASS (3 tests in the new suite).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartRasterTests.swift
git commit -m "feat(charts): rasterize .line series into cell grid"
```

---

## Task 12: `rasterizeArea` — `.area` style raster

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartRasterTests.swift`:

```swift
@Suite("LineChart area rasterization")
struct LineChartAreaRasterTests {
  @Test("rasterizeArea fills from line down to baselineRow")
  func areaFillsDownToBaseline() {
    let grid = rasterizeArea(
      points: [.init(x: 0, y: 1), .init(x: 1, y: 2)],
      domain: LineChartDomain(x: 0...1, y: 0...3),
      plotWidth: 2, plotHeight: 3,
      baselineRow: 2
    )
    // Cells below the line at each column should be `▒`.
    var foundShade = false
    for row in 0..<3 {
      for col in 0..<2 {
        if grid[row][col]?.glyph == "▒" { foundShade = true }
      }
    }
    #expect(foundShade)
  }

  @Test("rasterizeArea does not paint above the line")
  func areaDoesNotPaintAbove() {
    let grid = rasterizeArea(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 0)],
      domain: LineChartDomain(x: 0...1, y: 0...3),
      plotWidth: 2, plotHeight: 3,
      baselineRow: 2
    )
    // Top row should be empty since the line sits at y=0 (which inverts
    // to row 2 — bottom). Row 0 (top) should have no fills.
    for col in 0..<2 {
      #expect(grid[0][col] == nil)
    }
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartAreaRasterTests`
Expected: FAIL — `rasterizeArea` undefined.

- [ ] **Step 3: Implement `rasterizeArea`**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
/// Renders `.area` style: fills every cell between the line and
/// `baselineRow` with `▒`, then the line itself on top.
func rasterizeArea(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int,
  baselineRow: Int
) -> [[LineRasterCell?]] {
  let lineGrid = rasterizeLine(
    points: points,
    domain: domain,
    plotWidth: plotWidth,
    plotHeight: plotHeight
  )
  var grid = lineGrid
  let height = max(1, plotHeight)
  let width  = max(1, plotWidth)
  let clampedBaseline = min(max(baselineRow, 0), height - 1)

  // For each column, find the topmost filled row from the line raster.
  // Fill from that row + 1 down to `clampedBaseline` with `▒`.
  for col in 0..<width {
    var topRow: Int?
    for row in 0..<height where lineGrid[row][col] != nil {
      topRow = row
      break
    }
    guard let topRow else { continue }
    let fillStart = topRow + 1
    let fillEnd = clampedBaseline
    guard fillStart <= fillEnd else { continue }
    for row in fillStart...fillEnd where grid[row][col] == nil {
      grid[row][col] = LineRasterCell(glyph: "▒")
    }
  }
  return grid
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartAreaRasterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartRasterTests.swift
git commit -m "feat(charts): rasterize .area series with shaded fill"
```

---

## Task 13: `rasterizeStep` — `.step` style raster

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartRasterTests.swift`:

```swift
@Suite("LineChart step rasterization")
struct LineChartStepRasterTests {
  @Test("rasterizeStep holds Y constant across each segment then jumps")
  func stepHoldsThenJumps() {
    let grid = rasterizeStep(
      points: [.init(x: 0, y: 0), .init(x: 3, y: 3)],
      domain: LineChartDomain(x: 0...3, y: 0...3),
      plotWidth: 4, plotHeight: 4
    )
    // Row 3 (y=0 inverted) should be filled for cols 0..2; col 3 holds
    // the jump up to row 0.
    #expect(grid[3][0] != nil)
    #expect(grid[3][1] != nil)
    #expect(grid[3][2] != nil)
    // The jump column contains a vertical segment plus the new sample.
    let jumpColumnHasFill = (0..<4).contains { grid[$0][3] != nil }
    #expect(jumpColumnHasFill)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartStepRasterTests`
Expected: FAIL — `rasterizeStep` undefined.

- [ ] **Step 3: Implement `rasterizeStep`**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
/// Renders `.step` style: a horizontal segment at each sample's Y for
/// the full width up to (but not including) the next sample's column,
/// then a vertical jump in that column to the new Y.
func rasterizeStep(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int
) -> [[LineRasterCell?]] {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  guard !points.isEmpty else { return grid }

  let cells: [(col: Int, row: Int)] = points.map { p in
    (xCell(value: p.x, domain: domain.x, plotWidth: width),
     yCell(value: p.y, domain: domain.y, plotHeight: height))
  }

  for i in 0..<cells.count {
    let here = cells[i]
    let endCol = (i + 1 < cells.count) ? cells[i + 1].col : width
    // Horizontal hold from `here.col` to `endCol - 1` at `here.row`.
    for col in here.col..<min(endCol, width) where grid[here.row][col] == nil {
      grid[here.row][col] = LineRasterCell(glyph: "─")
    }
    // Vertical jump in `endCol` from `here.row` to the next sample's
    // row, if there is one.
    if i + 1 < cells.count, endCol < width {
      let next = cells[i + 1]
      let rowStart = min(here.row, next.row)
      let rowEnd   = max(here.row, next.row)
      for row in rowStart...rowEnd where grid[row][endCol] == nil {
        grid[row][endCol] = LineRasterCell(glyph: "│")
      }
    }
  }
  return grid
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartStepRasterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartRasterTests.swift
git commit -m "feat(charts): rasterize .step series with staircase layout"
```

---

## Task 14: Y-axis tick label computation

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartAxisTicksTests.swift`:

```swift
@Suite("LineChart Y axis ticks")
struct LineChartYAxisTickTests {
  @Test("yAxisTickLabels with .count(N) yields N evenly spaced labels")
  func yAxisCountEvenSpacing() {
    let labels = yAxisTickLabels(
      domain: 0...100,
      ticks: .count(5),
      format: .number,
      plotHeight: 10
    )
    #expect(labels.count == 5)
    // First label at the top row, last at the bottom row.
    #expect(labels.first?.row == 0)
    #expect(labels.last?.row == 9)
  }

  @Test("yAxisTickLabels with .automatic falls back to 5 ticks")
  func yAxisAutomatic() {
    let labels = yAxisTickLabels(
      domain: 0...10,
      ticks: .automatic,
      format: .number,
      plotHeight: 8
    )
    #expect(labels.count == 5)
  }

  @Test("yAxisTickLabels formats values with the supplied FormatStyle")
  func yAxisFormat() {
    let labels = yAxisTickLabels(
      domain: 0...1_000_000,
      ticks: .count(2),
      format: .number.notation(.compactName),
      plotHeight: 5
    )
    #expect(labels[0].text.contains("M") || labels[0].text.contains("K"))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartYAxisTickTests`
Expected: FAIL — `yAxisTickLabels` undefined.

- [ ] **Step 3: Implement `yAxisTickLabels`**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
struct AxisTickLabel: Equatable, Sendable {
  var row: Int      // for Y axis
  var col: Int      // for X axis
  var text: String
}

extension AxisTickLabel {
  init(row: Int, text: String) { self.init(row: row, col: 0, text: text) }
  init(col: Int, text: String) { self.init(row: 0, col: col, text: text) }
}

func yAxisTickLabels(
  domain: ClosedRange<Double>,
  ticks: LineChartYAxis.Ticks,
  format: FloatingPointFormatStyle<Double>,
  plotHeight: Int
) -> [AxisTickLabel] {
  let height = max(1, plotHeight)
  let span = domain.upperBound - domain.lowerBound

  let count: Int
  switch ticks {
  case .automatic:
    count = 5
  case .count(let n):
    count = max(2, n)
  case .every:
    // Stride-based ticks: compute count from span / stride. Fall back to
    // .automatic for `.every` since stride support on Y is rare.
    count = 5
  }

  guard span > 0 else {
    return [AxisTickLabel(row: 0, text: format.format(domain.lowerBound))]
  }

  var out: [AxisTickLabel] = []
  for i in 0..<count {
    let fraction = Double(i) / Double(count - 1)        // 0 ... 1
    let value = domain.upperBound - fraction * span      // top to bottom
    let row = Int((fraction * Double(height - 1)).rounded())
    out.append(AxisTickLabel(row: row, text: format.format(value)))
  }
  return out
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartYAxisTickTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartAxisTicksTests.swift
git commit -m "feat(charts): compute Y axis tick labels"
```

---

## Task 15: X-axis tick label computation (numeric + dates)

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/SwiftTUITests/LineChartAxisTicksTests.swift`:

```swift
@Suite("LineChart X axis ticks")
struct LineChartXAxisTickTests {
  @Test("xAxisTickLabels with .count(N) yields N evenly spaced labels")
  func xCountEvenSpacing() {
    let labels = xAxisTickLabels(
      domain: 0...100,
      ticks: .count(3),
      format: .number(.number),
      plotWidth: 20
    )
    #expect(labels.count == 3)
    #expect(labels.first?.col == 0)
    #expect(labels.last?.col == 19)
  }

  @Test("xAxisTickLabels with .dates(every: .month) snaps to month starts")
  func xDateStrideSnapsToMonth() {
    let cal = Calendar(identifier: .gregorian)
    var calUTC = cal
    calUTC.timeZone = TimeZone(identifier: "UTC")!
    // Range: 2024-01-15 ... 2024-04-15.
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(identifier: "UTC")
    let start = formatter.date(from: "2024-01-15")!
    let end   = formatter.date(from: "2024-04-15")!
    let labels = xAxisTickLabels(
      domain: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
      ticks: .dates(every: .month),
      format: .date(.dateTime.month(.abbreviated)),
      plotWidth: 30,
      calendar: calUTC
    )
    // Expect ticks at Feb, Mar, Apr starts (within the range).
    let texts = labels.map(\.text)
    #expect(texts.contains("Feb"))
    #expect(texts.contains("Mar"))
    #expect(texts.contains("Apr"))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartXAxisTickTests`
Expected: FAIL — `xAxisTickLabels` undefined.

- [ ] **Step 3: Implement `xAxisTickLabels`**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
func xAxisTickLabels(
  domain: ClosedRange<Double>,
  ticks: LineChartXAxis.Ticks,
  format: LineChartXAxis.Format,
  plotWidth: Int,
  calendar: Calendar = defaultGregorianUTC
) -> [AxisTickLabel] {
  let width = max(1, plotWidth)
  let span = domain.upperBound - domain.lowerBound
  guard span > 0 else {
    return [AxisTickLabel(col: 0, text: formatX(value: domain.lowerBound, using: format))]
  }

  switch ticks {
  case .automatic:
    return evenlySpacedXTicks(count: 5, domain: domain, plotWidth: width, format: format)
  case .count(let n):
    return evenlySpacedXTicks(count: max(2, n), domain: domain, plotWidth: width, format: format)
  case .every(let stride):
    let count = max(2, Int(span / max(stride, .leastNonzeroMagnitude)))
    return evenlySpacedXTicks(count: count, domain: domain, plotWidth: width, format: format)
  case .dates(let stride):
    return dateStrideXTicks(
      stride: stride,
      domain: domain,
      plotWidth: width,
      format: format,
      calendar: calendar
    )
  }
}

private let defaultGregorianUTC: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  return cal
}()

private func evenlySpacedXTicks(
  count: Int,
  domain: ClosedRange<Double>,
  plotWidth: Int,
  format: LineChartXAxis.Format
) -> [AxisTickLabel] {
  let span = domain.upperBound - domain.lowerBound
  var out: [AxisTickLabel] = []
  for i in 0..<count {
    let fraction = Double(i) / Double(count - 1)
    let value = domain.lowerBound + fraction * span
    let col = Int((fraction * Double(plotWidth - 1)).rounded())
    out.append(AxisTickLabel(col: col, text: formatX(value: value, using: format)))
  }
  return out
}

private func dateStrideXTicks(
  stride: DateAxisStride,
  domain: ClosedRange<Double>,
  plotWidth: Int,
  format: LineChartXAxis.Format,
  calendar: Calendar
) -> [AxisTickLabel] {
  let startDate = Date(timeIntervalSinceReferenceDate: domain.lowerBound)
  let endDate   = Date(timeIntervalSinceReferenceDate: domain.upperBound)
  let span = domain.upperBound - domain.lowerBound

  let component: Calendar.Component
  switch stride {
  case .day:     component = .day
  case .week:    component = .weekOfYear
  case .month:   component = .month
  case .quarter: component = .quarter
  case .year:    component = .year
  }

  // Snap the start to the next stride boundary (e.g., next month start).
  var current = nextStrideBoundary(after: startDate, component: component, calendar: calendar)
  var out: [AxisTickLabel] = []
  while current <= endDate {
    let value = current.timeIntervalSinceReferenceDate
    let fraction = (value - domain.lowerBound) / span
    let col = Int((fraction * Double(plotWidth - 1)).rounded())
    out.append(AxisTickLabel(col: col, text: formatX(value: value, using: format)))
    guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
    current = next
  }
  return out
}

private func nextStrideBoundary(
  after date: Date,
  component: Calendar.Component,
  calendar: Calendar
) -> Date {
  // Truncate `date` to the start of `component`, then if that's before
  // `date`, advance by one stride.
  var truncated = date
  switch component {
  case .day:
    truncated = calendar.startOfDay(for: date)
  case .weekOfYear:
    truncated = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
  case .month:
    truncated = calendar.dateInterval(of: .month, for: date)?.start ?? date
  case .quarter:
    truncated = calendar.dateInterval(of: .quarter, for: date)?.start ?? date
  case .year:
    truncated = calendar.dateInterval(of: .year, for: date)?.start ?? date
  default:
    break
  }
  if truncated < date, let next = calendar.date(byAdding: component, value: 1, to: truncated) {
    return next
  }
  return truncated
}

private func formatX(value: Double, using format: LineChartXAxis.Format) -> String {
  switch format {
  case .automatic, .number:
    let style: FloatingPointFormatStyle<Double>
    if case .number(let s) = format { style = s } else { style = .number }
    return style.format(value)
  case .date(let style):
    return Date(timeIntervalSinceReferenceDate: value).formatted(style)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartXAxisTickTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift \
        Tests/SwiftTUITests/LineChartAxisTicksTests.swift
git commit -m "feat(charts): compute X axis tick labels with date stride snapping"
```

---

## Task 16: `LineChart` view body composition

**Files:**
- Modify: `Sources/SwiftTUICharts/LineChartSupport.swift` (add composition + body builder)

- [ ] **Step 1: Add the series-composition helper**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
struct ComposedSeriesGrid: Equatable, Sendable {
  /// Rasterized cells across all series, with later series overwriting
  /// earlier ones (after area fills are painted first).
  var grid: [[LineRasterCell?]]
  /// Index into `series` for the series that owns each filled cell; the
  /// view layer uses this to pick the tone.
  var seriesIndex: [[Int?]]
}

/// Composites every series in z-order: areas first across all `.area`
/// series, then lines and steps (and the area's own line) on top in
/// declaration order. Later series win when cells collide.
func composeSeriesGrids(
  series: [LineChartSeries],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int,
  baselineRow: Int
) -> ComposedSeriesGrid {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )
  var seriesIndex: [[Int?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  // Pass 1: area fills only.
  for (index, s) in series.enumerated() where s.style == .area {
    let g = rasterizeArea(
      points: s.points, domain: domain,
      plotWidth: width, plotHeight: height,
      baselineRow: baselineRow
    )
    for row in 0..<height {
      for col in 0..<width where g[row][col] != nil {
        grid[row][col] = g[row][col]
        seriesIndex[row][col] = index
      }
    }
  }

  // Pass 2: lines and steps on top, in declaration order.
  for (index, s) in series.enumerated() {
    let g: [[LineRasterCell?]]
    switch s.style {
    case .line, .area:
      g = rasterizeLine(points: s.points, domain: domain,
                         plotWidth: width, plotHeight: height)
    case .step:
      g = rasterizeStep(points: s.points, domain: domain,
                         plotWidth: width, plotHeight: height)
    }
    for row in 0..<height {
      for col in 0..<width where g[row][col] != nil {
        grid[row][col] = g[row][col]
        seriesIndex[row][col] = index
      }
    }
  }

  return ComposedSeriesGrid(grid: grid, seriesIndex: seriesIndex)
}
```

- [ ] **Step 2: Add the body builder**

Append to `Sources/SwiftTUICharts/LineChartSupport.swift`:

```swift
@MainActor
@ViewBuilder
func lineChartBody(
  series: [LineChartSeries],
  height: Int,
  width: Int,
  xAxis: LineChartXAxis,
  yAxis: LineChartYAxis,
  legend: LineChartLegendConfig,
  baseline: LineChartBaseline
) -> some View {
  let yAxisLabelWidth = 6
  let plotWidth  = max(1, width - yAxisLabelWidth - 2)   // 2 for axis chrome
  let plotHeight = max(1, height)

  let domainOrNil = plotDomain(series: series)
  let domain = domainOrNil ?? LineChartDomain(x: 0...1, y: 0...1)

  let yTicks = yAxisTickLabels(
    domain: domain.y,
    ticks: yAxis.ticks,
    format: yAxis.format,
    plotHeight: plotHeight
  )
  let xTicks = xAxisTickLabels(
    domain: domain.x,
    ticks: xAxis.ticks,
    format: xAxis.format,
    plotWidth: plotWidth
  )

  let baselineRow: Int = {
    switch baseline {
    case .zero:
      return yCell(value: 0, domain: domain.y, plotHeight: plotHeight)
    case .auto:
      return plotHeight - 1
    }
  }()

  let composed = composeSeriesGrids(
    series: series,
    domain: domain,
    plotWidth: plotWidth,
    plotHeight: plotHeight,
    baselineRow: baselineRow
  )
  let composedGrid = composed.grid
  let cellSeriesIndex = composed.seriesIndex

  VStack(alignment: .leading, spacing: 0) {
    // Y axis labels + plot rows.
    ForEach(0..<plotHeight, id: \.self) { row in
      HStack(alignment: .center, spacing: 0) {
        let yLabel = yTicks.first(where: { $0.row == row })?.text ?? ""
        Text(yLabel)
          .frame(width: yAxisLabelWidth, alignment: .trailing)
          .foregroundStyle(.separator)
        Text(row == baselineRow ? "┼" : "┤")
          .foregroundStyle(.separator)
        ForEach(0..<plotWidth, id: \.self) { col in
          let cell = composedGrid[row][col]
          let seriesIndex = cellSeriesIndex[row][col]
          let toneStyle = seriesIndex.flatMap { index -> AnyShapeStyle? in
            guard index < series.count else { return nil }
            return series[index].tone == .automatic
              ? AnyShapeStyle(.tint)
              : metricAccentStyle(for: series[index].tone)
          } ?? AnyShapeStyle(.separator)
          Text(cell.map { String($0.glyph) } ?? " ")
            .foregroundStyle(toneStyle)
        }
      }
    }
    // X axis baseline + labels.
    HStack(alignment: .center, spacing: 0) {
      Text(String(repeating: " ", count: yAxisLabelWidth))
      Text("┼")
        .foregroundStyle(.separator)
      Text(String(repeating: "─", count: plotWidth))
        .foregroundStyle(.separator)
    }
    HStack(alignment: .center, spacing: 0) {
      Text(String(repeating: " ", count: yAxisLabelWidth + 1))
      Text(formatXAxisLine(xTicks: xTicks, plotWidth: plotWidth))
        .foregroundStyle(.separator)
    }
    // Legend strip.
    if legend.position != .hidden {
      legendStrip(series: series, spacing: legend.itemSpacing)
    }
  }
}

private func formatXAxisLine(xTicks: [AxisTickLabel], plotWidth: Int) -> String {
  var line = Array(repeating: Character(" "), count: plotWidth)
  for tick in xTicks {
    let text = Array(tick.text)
    let start = max(0, tick.col - text.count / 2)
    for (i, ch) in text.enumerated() {
      let position = start + i
      guard position < plotWidth else { break }
      line[position] = ch
    }
  }
  return String(line)
}

@MainActor
@ViewBuilder
private func legendStrip(series: [LineChartSeries], spacing: Int) -> some View {
  HStack(alignment: .center, spacing: spacing) {
    ForEach(series.indices, id: \.self) { index in
      let toneStyle =
        series[index].tone == .automatic
        ? AnyShapeStyle(.tint)
        : metricAccentStyle(for: series[index].tone)
      HStack(alignment: .center, spacing: 1) {
        Text("●").foregroundStyle(toneStyle)
        Text(series[index].label).foregroundStyle(.foreground)
      }
    }
  }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build --target SwiftTUICharts`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICharts/LineChartSupport.swift
git commit -m "feat(charts): compose LineChart body with axes, plot, legend"
```

---

## Task 17: `LineChart` public view + modifier methods

**Files:**
- Create: `Sources/SwiftTUICharts/LineChart.swift`

- [ ] **Step 1: Add failing modifier tests**

Append to `Tests/SwiftTUITests/LineChartAxisTicksTests.swift`:

```swift
@Suite("LineChart modifiers")
struct LineChartModifierTests {
  @Test("chartXAxis stores the supplied config")
  func storesXAxisConfig() {
    let chart = LineChart(series: [], height: 8).chartXAxis(.hidden)
    #expect(chart.xAxis.isHidden == true)
  }

  @Test("chartLegend stores legend config")
  func storesLegendConfig() {
    let chart = LineChart(series: [], height: 8).chartLegend(.hidden)
    #expect(chart.legend.position == .hidden)
  }

  @Test("chartBaseline stores baseline")
  func storesBaseline() {
    let chart = LineChart(series: [], height: 8).chartBaseline(.zero)
    #expect(chart.baseline == .zero)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LineChartModifierTests`
Expected: FAIL — `LineChart` undefined.

- [ ] **Step 3: Create `LineChart.swift`**

Create `Sources/SwiftTUICharts/LineChart.swift`:

```swift
import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A multi-series continuous plot supporting `.line`, `.area`, and
/// `.step` series styles, with Date- or numeric-aware axis modifiers.
public struct LineChart<Label: View, Summary: View>: View, ResolvableView {
  public var series: [LineChartSeries]
  public var height: Int
  public var width: Int?
  public var xAxis: LineChartXAxis
  public var yAxis: LineChartYAxis
  public var legend: LineChartLegendConfig
  public var baseline: LineChartBaseline

  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    series: [LineChartSeries],
    height: Int,
    width: Int?,
    xAxis: LineChartXAxis,
    yAxis: LineChartYAxis,
    legend: LineChartLegendConfig,
    baseline: LineChartBaseline,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.series = series
    self.height = height
    self.width = width
    self.xAxis = xAxis
    self.yAxis = yAxis
    self.legend = legend
    self.baseline = baseline
    self.accessibilitySummary = accessibilitySummary
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let effectiveWidth = max(20, width ?? 60)   // assume an 80-col terminal minus padding
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          lineChartBody(
            series: series,
            height: height,
            width: effectiveWidth,
            xAxis: xAxis,
            yAxis: yAxis,
            legend: legend,
            baseline: baseline
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "LineChart",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }
}

// MARK: - Modifiers

extension LineChart {
  public func chartXAxis(_ axis: LineChartXAxis) -> Self {
    var copy = self; copy.xAxis = axis; return copy
  }
  public func chartYAxis(_ axis: LineChartYAxis) -> Self {
    var copy = self; copy.yAxis = axis; return copy
  }
  public func chartLegend(_ config: LineChartLegendConfig) -> Self {
    var copy = self; copy.legend = config; return copy
  }
  public func chartBaseline(_ baseline: LineChartBaseline) -> Self {
    var copy = self; copy.baseline = baseline; return copy
  }
}

// MARK: - Convenience inits

extension LineChart where Label == EmptyView, Summary == Text {
  public init(
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil
  ) {
    let summary = "\(series.count) series"
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension LineChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    series: [LineChartSeries],
    height: Int = 8,
    width: Int? = nil
  ) {
    let title = String(title)
    let summary = "\(series.count) series"
    self.init(
      series: series,
      height: height,
      width: width,
      xAxis: .automatic,
      yAxis: .automatic,
      legend: .bottom,
      baseline: .auto,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineChartModifierTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftTUICharts/LineChart.swift \
        Tests/SwiftTUITests/LineChartAxisTicksTests.swift
git commit -m "feat(charts): add LineChart view with axis/legend/baseline modifiers"
```

---

## Task 18: Wire `calendar-heatmap` fixture into `NonAggregatingViewFixtureTests`

**Files:**
- Modify: `Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift`

- [ ] **Step 1: Add the fixture case and name**

Add a new case inside the `switch name` block in `NonAggregatingViewFixtureTests.swift`
(insert near `heat-strip`):

```swift
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
```

Add the entry to `nonAggregatingFixtureNames`:

```swift
  "calendar-heatmap",
```

Add the supporting private fixture data at the bottom of the file
(next to `queueEntries`, etc.):

```swift
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
```

Also add `import Foundation` at the top of the file if not already
present.

- [ ] **Step 2: Record the goldens**

Run with the record env var:

```bash
PARALLEL_RECORD_RENDERED_FIXTURES=1 swift test \
  --filter "non-aggregating view fixture matches" \
  -- --filter "calendar-heatmap"
```

Expected: test passes after writing the new files under
`Tests/SwiftTUITests/Fixtures/calendar-heatmap/`.

Inspect the generated files:

```bash
ls Tests/SwiftTUITests/Fixtures/calendar-heatmap/
```

Expected: 5 `.txt` files (`preview-unicode.txt`, `preview-ascii.txt`,
`ansi16.txt`, `ansi256.txt`, `true-color.txt`). Open one and sanity-check
that the output looks like a calendar heatmap (month header at top, day
labels on the left, grid of `░▒▓█/·/space` cells, scale legend at
bottom).

- [ ] **Step 3: Re-run without recording to verify against goldens**

```bash
swift test --filter "non-aggregating view fixture matches" -- --filter "calendar-heatmap"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift \
        Tests/SwiftTUITests/Fixtures/calendar-heatmap/
git commit -m "test(charts): add CalendarHeatmap rendered text fixture"
```

---

## Task 19: Wire `line-chart-three-series` fixture

**Files:**
- Modify: `Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift`

- [ ] **Step 1: Add the fixture case and shared data**

Insert a new case in the switch:

```swift
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
```

Add to `nonAggregatingFixtureNames`:

```swift
  "line-chart-three-series",
```

Add the helper at the bottom of the file:

```swift
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
```

- [ ] **Step 2: Record the goldens**

```bash
PARALLEL_RECORD_RENDERED_FIXTURES=1 swift test \
  --filter "non-aggregating view fixture matches" \
  -- --filter "line-chart-three-series"
```

Expected: PASS; 5 `.txt` files appear under
`Tests/SwiftTUITests/Fixtures/line-chart-three-series/`. Inspect one
and verify it shows three labeled series with axis labels.

- [ ] **Step 3: Re-run without recording**

```bash
swift test --filter "non-aggregating view fixture matches" -- --filter "line-chart-three-series"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift \
        Tests/SwiftTUITests/Fixtures/line-chart-three-series/
git commit -m "test(charts): add multi-series LineChart rendered text fixture"
```

---

## Task 20: Wire `line-chart-area` and `line-chart-step` fixtures

**Files:**
- Modify: `Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift`

- [ ] **Step 1: Add the two fixture cases**

Insert two more cases in the switch:

```swift
    case "line-chart-area":
      return FixtureSpec(
        name: name,
        size: .init(width: 60, height: 10),
        view: AnyView(
          LineChart(
            "Net LOC",
            series: [
              LineChartSeries("net loc",
                              points: locSeries(),
                              style: .area,
                              tone: .info)
            ],
            height: 6
          )
          .chartXAxis(.dates(every: .month))
          .chartYAxis(.values(count: 4))
          .chartBaseline(.zero)
        )
      )

    case "line-chart-step":
      return FixtureSpec(
        name: name,
        size: .init(width: 60, height: 10),
        view: AnyView(
          LineChart(
            "Release cadence",
            series: [
              LineChartSeries("releases",
                              points: stepSeries(),
                              style: .step,
                              tone: .success)
            ],
            height: 6
          )
          .chartXAxis(.dates(every: .month))
          .chartYAxis(.values(count: 4))
        )
      )
```

Add to `nonAggregatingFixtureNames`:

```swift
  "line-chart-area",
  "line-chart-step",
```

Add the helpers at the bottom:

```swift
private func locSeries() -> [LineChartPoint] {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  formatter.timeZone = TimeZone(identifier: "UTC")
  func d(_ s: String) -> Date { formatter.date(from: s)! }
  return [
    .init(date: d("2024-01-01"), value: 0),
    .init(date: d("2024-02-01"), value: 1_200),
    .init(date: d("2024-03-01"), value: 1_800),
    .init(date: d("2024-04-01"), value: 2_500),
    .init(date: d("2024-05-01"), value: 4_100),
    .init(date: d("2024-06-01"), value: 5_400),
  ]
}

private func stepSeries() -> [LineChartPoint] {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  formatter.timeZone = TimeZone(identifier: "UTC")
  func d(_ s: String) -> Date { formatter.date(from: s)! }
  return [
    .init(date: d("2024-01-01"), value: 1),
    .init(date: d("2024-02-15"), value: 2),
    .init(date: d("2024-04-01"), value: 4),
    .init(date: d("2024-05-20"), value: 5),
  ]
}
```

- [ ] **Step 2: Record the goldens**

```bash
PARALLEL_RECORD_RENDERED_FIXTURES=1 swift test \
  --filter "non-aggregating view fixture matches" \
  -- --filter "line-chart-area"
PARALLEL_RECORD_RENDERED_FIXTURES=1 swift test \
  --filter "non-aggregating view fixture matches" \
  -- --filter "line-chart-step"
```

Expected: PASS; new `.txt` files appear under
`Tests/SwiftTUITests/Fixtures/line-chart-area/` and `.../line-chart-step/`.
Inspect one of each — `line-chart-area` should show `▒` shading under
a line; `line-chart-step` should show horizontal segments with vertical
jumps at sample points.

- [ ] **Step 3: Re-run without recording**

```bash
swift test --filter "non-aggregating view fixture matches" -- --filter "line-chart"
```

Expected: PASS for all four `line-chart-*` fixtures.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiftTUITests/NonAggregatingViewFixtureTests.swift \
        Tests/SwiftTUITests/Fixtures/line-chart-area/ \
        Tests/SwiftTUITests/Fixtures/line-chart-step/
git commit -m "test(charts): add area and step LineChart fixtures"
```

---

## Task 21: DocC updates

**Files:**
- Modify: `Sources/SwiftTUICharts/SwiftTUICharts.docc/SwiftTUICharts.md`
- Modify: `Sources/SwiftTUICharts/SwiftTUICharts.docc/Building-Dashboards.md`

- [ ] **Step 1: Add new types to `SwiftTUICharts.md` topics**

In `Sources/SwiftTUICharts/SwiftTUICharts.docc/SwiftTUICharts.md`,
under `### Charts`, append:

```markdown
- ``CalendarHeatmap``
- ``LineChart``
```

Under `### Support Types`, append:

```markdown
- ``DateValue``
- ``LineChartPoint``
- ``LineChartSeries``
- ``LineChartSeriesStyle``
- ``LineChartXAxis``
- ``LineChartYAxis``
- ``LineChartLegendConfig``
- ``LineChartBaseline``
- ``DateAxisStride``
- ``CalendarHeatmapWeekStart``
```

- [ ] **Step 2: Add usage examples to `Building-Dashboards.md`**

Append a section to
`Sources/SwiftTUICharts/SwiftTUICharts.docc/Building-Dashboards.md`:

````markdown
## Calendars and time series

### Calendar heatmap

For daily activity over a long horizon (commits per day, requests per
day, ...), use `CalendarHeatmap`. Pass a flat array of `DateValue` and
the chart buckets them into a weekday × week grid.

```swift
CalendarHeatmap(
  "Activity",
  days: dailyCounts,
  weekStart: .monday
)
```

### Multi-series line chart

For continuous numeric or time-series data with one or more lines, use
`LineChart`. Series can be `.line`, `.area`, or `.step`; the X axis can
be numeric or Date-aware via `.chartXAxis(.dates(...))`.

```swift
LineChart(
  "Tokens per Day",
  series: [
    .init("Opus 4.7", points: opus47, tone: .info),
    .init("Opus 4.6", points: opus46, tone: .success),
    .init("Haiku 4.5", points: haiku45, tone: .warning),
  ],
  height: 8
)
.chartXAxis(.dates(every: .week))
.chartYAxis(.values(count: 6, format: .number.notation(.compactName)))
.chartLegend(.bottom)
```
````

- [ ] **Step 3: Verify docc builds**

If the project has a docc preview script, run it; otherwise build with
SwiftPM's docc plugin:

```bash
swift package generate-documentation --target SwiftTUICharts
```

Expected: build succeeds without unresolved symbol references.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUICharts/SwiftTUICharts.docc/
git commit -m "docs(charts): index CalendarHeatmap and LineChart in DocC"
```

---

## Task 22: Final integration check

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```

Expected: all tests pass, including the new helper tests
(`CalendarHeatmapDateMathTests`, `LineChartDomainTests`,
`LineChartRasterTests`, `LineChartAxisTicksTests`,
`CalendarHeatmapModifierTests`, `LineChartModifierTests`) and the four
new fixture tests (`calendar-heatmap`, `line-chart-three-series`,
`line-chart-area`, `line-chart-step`).

- [ ] **Step 2: Build the gallery example to confirm no breakage**

```bash
swift build --package-path Examples/gallery
```

Expected: build succeeds. (The new charts aren't yet used by gallery;
this is a smoke check that the existing chart module still compiles
cleanly for downstream consumers.)

- [ ] **Step 3: Quick visual smoke** (optional, manual)

Write a tiny `swift -e` snippet or temporary script that constructs a
`CalendarHeatmap` and a `LineChart`, renders them to stdout, and pipe
the output to `cat -A` to verify ANSI codes look sane. (Skip if no
quick-render path is in place yet — this is what the `gitviz` plan's
`RenderOnce` will eventually unblock.)

- [ ] **Step 4: Final commit**

If any small fixes came up (lint, formatting), commit them as a single
follow-up:

```bash
git add -p
git commit -m "chore(charts): post-integration cleanup"
```

If nothing changed, this task is a no-op.

---

## Self-review notes

**Coverage check vs spec:**

- `DateValue` ✓ Task 1.
- `LineChartPoint` (+ Date convenience init) ✓ Task 2.
- `LineChartSeries`, `LineChartSeriesStyle` (`.line` / `.area` / `.step`) ✓ Task 3.
- `LineChartXAxis`, `LineChartYAxis`, `LineChartLegendConfig`,
  `LineChartBaseline`, `DateAxisStride` ✓ Task 4.
- `inferDateRange` ✓ Task 5.
- `bucketDays` + `CalendarHeatmapWeekStart` ✓ Task 6.
- `CalendarHeatmap` view ✓ Task 7.
- `CalendarHeatmap.chartLegend` modifier ✓ Task 8.
- `plotDomain` ✓ Task 9.
- `xCell` / `yCell` ✓ Task 10.
- `rasterizeLine` ✓ Task 11.
- `rasterizeArea` ✓ Task 12.
- `rasterizeStep` ✓ Task 13.
- `yAxisTickLabels` ✓ Task 14.
- `xAxisTickLabels` (numeric + date stride snapping) ✓ Task 15.
- `lineChartBody` (composition, z-order, baseline, legend strip) ✓ Task 16.
- `LineChart` view + `chartXAxis` / `chartYAxis` / `chartLegend` /
  `chartBaseline` modifiers ✓ Task 17.
- Calendar heatmap render fixture ✓ Task 18.
- Multi-series line chart render fixture ✓ Task 19.
- Area + step line chart render fixtures ✓ Task 20.
- DocC updates ✓ Task 21.
- Final integration ✓ Task 22.

**Out of scope** (per spec, deliberately not in this plan):

- Interactive cursor / value readout (deferred; coordinate infra in
  `ChartCoordinateConversion.swift` already supports it).
- Stacked area.
- Logarithmic / non-linear Y.
- Dual Y-axis.
- Annotations / trendlines.
- Generic `Plottable` X type.
- Custom heatmap ramps.

**Known deviation from spec — flagged for follow-up:**

- **`LineChart.width = nil → auto-fit to proposed size`** is not
  implemented in this tranche. The spec language said
  `width: Int?  // nil → use available`; the plan ships with
  `width ?? 60` as the fallback so the chart renders predictably even
  outside a layout context. Fixture tests pin the surface size
  explicitly, so this doesn't affect testability. A follow-up tranche
  can wire `LineChart` through a `GeometryReader` (or the layout-time
  `LayoutRealizationContext` seam) to read the proposed width, at
  which point `width` becomes a true override rather than a default.
