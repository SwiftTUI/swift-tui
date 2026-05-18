# ``CellPixelMetrics``

Read-only display metrics describing how terminal cells map to device pixels.

## Overview

SwiftTUI measures layout in integer cells. `CellPixelMetrics` is advisory
runtime metadata that tells you how those cells map to pixels on the current
terminal — so you can apply aspect correction to shapes, motion, or image
sizing without reinventing the fallback.

Access via `GeometryProxy.cellPixelMetrics` inside a `GeometryReader`,
or via `EnvironmentValues.cellPixelMetrics` anywhere an environment
is available.

The value always has honest dimensions: either the terminal reported them
(`source == .reported`) or they are the conventional 8x16 fallback
(`source == .estimated`). Check `source` before making decisions that
require pixel accuracy.

## Topics

### Reading the metrics

- ``width``
- ``height``
- ``aspectRatio``
- ``source``

### Fallback value

- ``estimated``

## See Also
