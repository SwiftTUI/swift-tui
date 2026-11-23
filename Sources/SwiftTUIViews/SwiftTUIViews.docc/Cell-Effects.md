# Transforming a view’s painted cells

Apply a Swift shader to the cells a view draws, including the different styles
of its descendants. The view keeps its layout, identity, focus and actions.

## Change a glyph

A layer shader receives an output position, an immutable snapshot of the
source layer, and a `CellEffectContext`. To replace a digit with a bullet,
edit its character and return the copied glyph. Spaces, other glyphs, and
holes pass through.

```swift
import SwiftTUIViews

struct MaskDigits: CellLayerKernel {
  func shade(
    at position: CellPoint, in source: CellLayer, context: CellEffectContext
  ) -> CellSample {
    let sample = source.sample(at: position)
    guard case .glyph(var glyph) = sample,
      glyph.width == 1, glyph.character.isNumber
    else { return sample }
    glyph.character = "•"
    return .glyph(glyph)
  }
}

struct TicketNumber: View {
  let number: String
  let masked: Bool

  var body: some View {
    Text(number).layerEffect(CellLayerShader(MaskDigits()), maxSampleOffset: .zero,
                             isEnabled: masked)
  }
}
```

`CellLayerKernel` is `Equatable` and `Sendable`. Two shaders wrapping the
same concrete kernel type and equal values compare equal. Use values for
parameters that change between frames. The renderer may evaluate the same
sample again, including on its raster worker. Keep the result independent
of the number and order of calls.

An inline closure has the same arguments and return type. This example keeps
only glyphs whose stored paper is explicitly painted.

```swift
Text("Status").layerEffect(maxSampleOffset: .zero) { position, source, _ in
  let sample = source.sample(at: position)
  if case .glyph(let glyph) = sample, glyph.paint.background == .default {
    return .empty
  }
  return sample
}
```

`CellLayerShader.Function` names that `@Sendable` function type.
`CellLayerShader.init(_:)` accepts a named kernel or a function. Each function
initializer creates its own identity. Copies of the resulting shader share
that identity. Set `isEnabled` to `false` to bypass the shader. For an animated
transition, make this decision from the sampled progress in the animatable
modifier’s body so the last frame renders the ordinary view.

## Read by column or by glyph

`CellLayer.sample(at:)` distinguishes three structural values.

| Sample | Meaning |
| --- | --- |
| `.empty` | This layer leaves the column open. Lower paint shows through. |
| `.glyph(glyph)` | The first column of a character, including a painted space. |
| `.continuation(columnsBack: d)` | Part of a wide glyph whose lead lies `d` columns to the left. |

For a two-column 界 at x = 7, querying x = 8 yields
`.continuation(columnsBack: 1)`. Calling `glyph(occupying:)` at x = 8 gives
the complete 界 and its paint even when `maxSampleOffset` is `.zero`.
The query point must lie inside `readableBounds`. An uncovered column or a
glyph cut by a hard clip yields `nil`. To reproduce the source, return its
structural sample. The renderer builds output spans from accepted leads in
left-to-right order. To split a wide glyph, emit a new single-column glyph
at each output position.

A copied `CellGlyph` carries its `paint`, `emphasis`, `underline`,
`strikethrough`, and `link`. Its `width` reflects its character after a
substitution. Constructing a glyph with `CellGlyph(_:paint:emphasis:underline:strikethrough:)`
creates an unlinked glyph. Use `copyLink(from:)` to attach a sampled glyph’s
link or `removeLink()` to drop it. A link in departing content loses its
actionable destination on removal.

## Place, read and paint

`CellEffectContext.sourceBounds`, `outputBounds` and `viewport` use the
subject’s local axes. X grows to the right and Y grows down. Add `originInRoot`
to obtain the root position. A viewport extending left of the subject starts
at a negative local X. `appearance` supplies the terminal defaults and
palette, and `cellPixelMetrics` supplies the host’s cell dimensions.

`CellLayer.bounds` describes the input extent. Its `readableBounds` reflects
the read window at this output position. `CellSampleOffset.cells(x:y:)` permits
the specified distance in each axis, `.zero` permits the current column,
and `.layerBounds` permits the entire input. A direct read outside the
window returns `.empty`. Retaining the layer retains this snapshot and window.

Select the output extent with `drawing(in:)` on the shader. A
`CellDrawingRegion` can select the subject with `.source`, expand it on each
axis with `.outset(x:y:)`, or select the `.viewport` or a local `.rect(_:)`.
Ancestor clipping limits the output. Read reach and output extent are
independent. For example, a shader moving an entire row across a panel can
select a viewport output and declare `.layerBounds` for its reads.

`CellPaint.foreground` and `background` each carry a `CellChannel`. Keep
`.default` to inherit terminal defaults, use `.color(_:)` for an explicit
color, or use `.indexed(_:)` for a palette entry. `CellPaint.coverage` varies
from zero to one for the whole glyph. Zero exposes the lower layer.
`resolvedColors(for:emphasis:over:)` resolves ink and paper in display order
using the context’s appearance, the glyph’s emphasis, and an optional lower
paper color. Read the stored channels directly when preserving palette tokens.
