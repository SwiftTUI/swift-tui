# ``CellPixelMetrics``

Read-only display metrics describing how terminal cells map to device pixels.

## Overview

SwiftTUI measures layout in integer cells. `CellPixelMetrics` is advisory
runtime metadata. It tells you how those cells map to pixels on the current
terminal. You can use this mapping for aspect correction in shapes, motion, or
image sizing without inventing a fallback.

Access via `GeometryProxy.cellPixelMetrics` inside a `GeometryReader`,
or via `EnvironmentValues.cellPixelMetrics` anywhere an environment
is available.

The value always identifies the source of its dimensions. The terminal reports
them when `source == .reported`. Otherwise, they are the conventional 8x16
fallback, and `source == .estimated`. Before you use pixel accuracy, make sure
that `source == .reported`.

## Topics

### Reading the metrics

- ``width``
- ``height``
- ``aspectRatio``
- ``source``

### Fallback value

- ``estimated``
