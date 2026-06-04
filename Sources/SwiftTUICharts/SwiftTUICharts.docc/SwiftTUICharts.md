# ``SwiftTUICharts``

Compact charts and metric-oriented views built on the same `SwiftTUIViews` and
`SwiftTUICore` foundations as the rest of SwiftTUI.

## Overview

`SwiftTUICharts` is a separate product for operational surfaces, dashboards, and compact summaries.

It includes:

- progress and gauge views
- bar, column, comparison, bullet, and stacked-bar charts
- sparklines and timelines
- legends and support models

The module is intentionally separate from the core roadmap so charting needs do not distort the main authoring and runtime surfaces.

## Topics

### Metric Views

- ``Meter``
- ``ThresholdGauge``

### Charts

- ``BarChart``
- ``ColumnChart``
- ``ComparisonChart``
- ``BulletChart``
- ``StackedBarChart``
- ``Sparkline``
- ``Timeline``
- ``HeatStrip``
- ``CalendarHeatmap``
- ``LineChart``

### Support Types

- ``BarChartEntry``
- ``ComparisonEntry``
- ``TimelineEntry``
- ``Legend``
- ``LegendItem``
- ``BannerTone``
- ``ThresholdBand``
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

### Guide

- <doc:Building-Dashboards>
