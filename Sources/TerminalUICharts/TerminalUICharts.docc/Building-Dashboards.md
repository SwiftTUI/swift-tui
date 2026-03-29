# Building Dashboards

## Overview

`TerminalUICharts` is designed for dense operational surfaces rather than for decorative charting.

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
