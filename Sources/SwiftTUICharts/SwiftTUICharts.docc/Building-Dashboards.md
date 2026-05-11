# Building Dashboards

## Overview

`SwiftTUICharts` is designed for dense operational surfaces rather than for decorative charting.

The views in this module work best when they are paired with:

- `GroupBox` and `Section` for framing
- `LabeledContent` for precise labels
- `ViewThatFits` or custom `Layout` for adapting between wide and narrow terminal widths

## Choosing A Chart

- Use ``ProgressView`` or ``Meter`` when the user cares about a single current value
- Use ``ThresholdGauge`` when tone changes matter at well-defined boundaries
- Use ``BarChart`` or ``ColumnChart`` when comparing multiple values directly
- Use ``ComparisonChart`` or ``BulletChart`` when a baseline or target is important
- Use ``Sparkline`` or ``Timeline`` for compact trend summaries

## Layout Guidance

Terminal dashboards are narrow compared to pixel-based UIs. Prefer:

- short labels
- explicit widths when comparison matters
- summary text outside the chart when the chart body is already dense
- stacked layouts that degrade cleanly under reduced width

## Pointer Coordinates

Chart helper math follows the package-wide coordinate split. Plot bounds are
integer `CellRect` values from layout, and pointer or hover locations are
continuous cell-space `Point` values. Convert from the continuous point into a
domain value at the chart boundary; keep chart layout itself cell-denominated
so the same view works with cell-only pointer fallback.

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
