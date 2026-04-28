# Aspect-correct shapes in terminals

TerminalUI's Braille-subpixel shape rasterizer consumes
``/Core/CellPixelMetrics`` from the resolve environment so that
``Circle``, ``Ellipse``, and ``Capsule`` render honestly regardless of
the terminal's cell aspect ratio.

## The math in one paragraph

A Braille subpixel is `cellPixelMetrics.width / 2` pixels wide and
`cellPixelMetrics.height / 4` pixels tall. At the conventional 8x16 cell
these are both 4 pixels, so subpixels are square and circles "just work."
On terminals with different cell aspect — for example 10x16 — subpixels
are oblong (5x4), and the rasterizer scales the x and y semi-axes
independently in subpixel units so the emitted pixel shape is true.

Aspect correction is a no-op at the conventional 8x16 cell: the formula
collapses to the pre-correction code, and shape output is identical.

## Worked example

The gallery physics toy ships a circular subject whose cell-frame is
intentionally non-square at the authoring layer (6 cells wide,
`6/aspectRatio` cells tall). The ``Circle`` rasterizer then applies its
own aspect correction, producing a visually round ball on any terminal
whose cell dimensions it can read.

## See Also

The rasterizer-equivalence guarantee at `.estimated` metrics, fixture regeneration policy, and the integer-division quantization caveat that determines which metrics actually exercise the aspect-correction path:

- [Cell Pixel Metrics proposal](https://github.com/adamz/swift-terminal-ui/blob/main/docs/proposals/CELL_PIXEL_METRICS.md)
