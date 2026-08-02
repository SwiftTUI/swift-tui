# Aspect-correct shapes in terminals

SwiftTUI's Braille-subpixel shape rasterizer consumes
`CellPixelMetrics` from the resolve environment so that
``Circle``, ``Ellipse``, and ``Capsule`` render honestly regardless of
the terminal's cell aspect ratio.

## The math in one paragraph

A Braille subpixel is `cellPixelMetrics.width / 2` pixels wide and
`cellPixelMetrics.height / 4` pixels tall. At the conventional 8x16 cell
these are both 4 pixels. Thus, subpixels are square, and circles are round.
On terminals with different cell aspect — for example 10x16 — subpixels
are oblong (5x4). The rasterizer scales the x-axis and y-axis independently in
subpixel units. Thus, the emitted pixel shape has the correct proportions.

Aspect correction is a no-op at the conventional 8x16 cell: the formula
collapses to the pre-correction code, and shape output is identical.

## Worked example

The gallery physics toy ships a circular subject whose cell-frame is
intentionally non-square at the authoring layer (6 cells wide,
`6/aspectRatio` cells tall). The ``Circle`` rasterizer then applies its
own aspect correction, producing a visually round ball on any terminal
whose cell dimensions it can read.

## See Also

The `SwiftTUICore` regression suites cover the rasterizer-equivalence guarantee
at `.estimated` metrics. They also cover fixture regeneration and
integer-division quantization. Quantization determines which metrics exercise
the aspect-correction path. See `CellPixelMetrics` for the complete metrics
type documentation.
