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

The context describes the same logical rectangles throughout a paint, even
when the renderer gathers a large source in tiles. A compositing group
isolates its paint while preserving the enclosing viewport.

`CellPaint.foreground` and `background` each carry a `CellChannel`. Keep
`.default` to inherit terminal defaults, use `.color(_:)` for an explicit
color, or use `.indexed(_:)` for a palette entry. `CellPaint.coverage` varies
from zero to one for the whole glyph. Zero exposes the lower layer.
`resolvedColors(for:emphasis:over:)` resolves ink and paper in display order
using the context’s appearance, the glyph’s emphasis, and an optional lower
paper color. Read the stored channels directly when preserving palette tokens.

## Recolor or move a glyph

Use `colorEffect` to change ink, paper or coverage. The program receives
the stored paint of each glyph’s lead column, including a painted space.
It preserves the character, width, decorations and link. This example
changes the ink of every covered glyph to ANSI palette entry 196.

```swift
struct PaletteInk: CellColorKernel {
  var index: UInt8

  func shade(at position: CellPoint, paint: CellPaint, context: CellEffectContext) -> CellPaint {
    var result = paint
    result.foreground = .indexed(index)
    return result
  }
}

let label = Text("Warning").colorEffect(CellColorShader(PaletteInk(index: 196)))
```

The `colorEffect(isEnabled:_:)` trailing closure receives the same three
arguments. The rendered `ResolvedTextStyle` includes both the resolved
`foregroundColor` or `backgroundColor` and the corresponding
`foregroundPaletteIndex` or `backgroundPaletteIndex` for an indexed channel.
Assigning a new resolved color clears that channel’s index. A capable terminal
can emit the index directly. Color-only hosts receive its resolved color.

Use `distortionEffect` to move source cells. For each output column, return
the absolute position of the input column to read, in subject-local
coordinates. Returning `nil` leaves that output open. For example, move the
first four letters of a label one column right inside its existing extent.

```swift
let shifted = Text("HELLO").distortionEffect(maxSampleOffset: .cells(x: 1, y: 0)) {
  destination, _ in
  guard destination.x > 0 else { return nil }
  return CellPoint(x: destination.x - 1, y: destination.y)
}
```

A `CellDistortionKernel` implements `sourcePosition(for:context:)`. Wrap
the value in `CellDistortionShader` to pass it to
`distortionEffect(_:maxSampleOffset:isEnabled:)`. Its `drawing(in:)`
method selects the output region, so a motion can travel past the subject.
Color and distortion shaders use the same kernel-value and closure-identity
equality rules as layer shaders.

## Read lower paint at the current position

A compositing shader receives the subject and a snapshot of everything drawn
beneath it at this point in the frame. Both layers use subject-local positions.
Each sampler enforces the declared read distance. At a continuation column,
`glyph(occupying:)` returns the entire visible glyph even with a zero read
distance. A compositing group starts a separate destination.

```swift
let alternate = CellLayerShader.compositing { point, source, lower, _ in
  guard point.x.isMultiple(of: 2) else { return .keepDestination }
  return .replace(source.sample(at: point))
}
Text("arrival").layerEffect(alternate, maxSampleOffset: .zero)
```

`CellCompositeResult.keepDestination` preserves the current lower glyph.
`.replace(.empty)` clears its span from the current destination. An enclosing
layer can show through the hole. For a reusable program, conform to
`CellCompositingKernel` and implement `composite(at:source:backdrop:context:)`.
`CellLayerShader.CompositingFunction` names the equivalent closure type.

## Move cells in an ordered region

Use `CellLayerShader.region` for ordered writes. The buffer initially contains
the source contribution within `bounds`. Later reads see earlier writes.
A snapshot retains what the buffer contained when you took it.

```swift
let move = CellLayerShader.region { _, buffer, _ in
  let original = buffer.snapshot()
  let first = buffer.bounds.origin
  let next = CellPoint(x: first.x + 1, y: first.y)
  buffer.clear(at: first)
  if let glyph = original.glyph(occupying: first) {
    buffer.set(glyph, at: next)
  }
}
```

`CellEffectBuffer(bounds:)` creates a buffer of holes. Its `sample(at:)`
distinguishes leads, continuations and holes. Writing or clearing one column
repairs the whole span underneath it. `blit(_:from:to:)` copies glyphs and
holes from a stable layer, including an overlapping snapshot of the same
buffer. A glyph cut by the source or destination rectangle contributes a
hole. A region kernel can read the whole output rectangle with a zero offset.
A finite offset expands that rectangle before intersecting the input bounds.
`CellRegionKernel.apply(source:to:context:)` and
`CellLayerShader.RegionFunction` provide the named and closure forms.

Use `backdropEffect(_:in:maxSampleOffset:isEnabled:)` on a dialog to process
the lower cells first and then paint the dialog. For example, applying
`move` with `in: .viewport` lets it operate on the lower viewport beyond
the dialog’s layout slot. If a compositing shader runs on this target, both
input layers initially represent the designated lower region. Higher siblings
paint afterwards. An image intersecting a backdrop read contributes its
cell fallback at the original image command. The remainder retains its native
placement. Disabling the descriptor restores the ordinary image path.

## Keep state across samples

A `CellPreparedLayerKernel` owns its `State` for the lifetime of the mounted
effect. Return the initial value from `makeState()`. In
`prepare(_:source:context:)`, advance it using `context.delta` and return a
shader that captures immutable values for this sample. The first call has
zero elapsed time, zero delta and no previous bounds. A later call includes
all time since the previous sample and the previous source bounds. A retry at
the same logical time reuses the prepared shader. The source may be retained
as an immutable snapshot. Its `bounds` describe the entire input. With a
finite sample offset, `readableBounds` covers the source inside the enclosing
paint domain plus the declared reach. Use `.layerBounds` to read the full input.
All fragments of a shape mask share one preparation. Drive the samples with
your animation or timeline.

## Draw a change of placement

`placementEffect(maxSampleOffset:isEnabled:_:)` receives the previous and new
layout rectangles of a view within the same parent. Its shader reads the new
layout. Subtract the new origin from the previous origin for the displacement
at the start. A spring can supply progress outside zero through one.
Use `.drawing(in: .viewport)` when the flight leaves the view's bounds.
A view at rest draws normally.

## Shade a border stroke

Pass a `CellLayerShader` to the stroke-style border. The shader receives the
actual stroke glyphs, including joined line arms. Dash gaps and cells occupied
only by the content are holes. A title overlaid on the border paints afterwards.

```swift
Text("Status").padding()
  .border(Color.cyan, style: .rounded, effect: strokeShader, maxSampleOffset: .zero)
```
