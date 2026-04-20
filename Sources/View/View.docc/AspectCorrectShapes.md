# Aspect-correct shapes in terminals

TerminalUI's Braille-subpixel shape rasterizer consumes
``Core/CellPixelMetrics`` from the resolve environment so that
``Circle``, ``Ellipse``, and ``Capsule`` render honestly regardless of
the terminal's cell aspect ratio.

## The math in one paragraph

A Braille subpixel is `cellPixelMetrics.width / 2` pixels wide and
`cellPixelMetrics.height / 4` pixels tall. At the conventional 8x16 cell
these are both 4 pixels, so subpixels are square and circles "just work."
On terminals with different cell aspect — for example 10x16 — subpixels
are oblong (5x4), and the rasterizer scales the x and y semi-axes
independently in subpixel units so the emitted pixel shape is true.

## Worked example

The gallery physics toy ships a circular subject whose cell-frame is
intentionally non-square at the authoring layer (6 cells wide,
`6/aspectRatio` cells tall). The ``Circle`` rasterizer then applies its
own aspect correction, producing a visually round ball on any terminal
whose cell dimensions it can read.

## Behavior at `.estimated` metrics

The aspect-correction formula collapses to the pre-correction code when
`cellPixelMetrics.aspectRatio == 2.0` (i.e. the conventional 8x16
fallback). That means fixtures captured against the old rasterizer at
default metrics remain bit-identical against the new code.

## Quantization caveat

Because sub-pixel dimensions are computed via integer division
(`metrics.width / 2`, `metrics.height / 4`), some non-default metrics
produce the same sub-pixel aspect as 8x16. For example, 6x14 produces
sub-pixels that are 3x3 — square — so the rasterizer output matches
8x16 even though the cell itself is different. Aspect correction
produces visibly different output only when the integer-divided
sub-pixel dimensions differ.
