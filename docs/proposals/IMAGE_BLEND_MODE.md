# Image Blend Mode Proposal

Status: proposal.

## Summary

SwiftTUI currently treats blend modes as terminal-cell compositing and treats
images as host presentation attachments. The two systems share the same
resolve -> measure -> place -> draw -> raster pipeline, but image pixels are
not blended by `View.blendMode(_:)`.

This proposal scopes the work required for `Image(...).blendMode(...)` and
`AnimatedImage(...).blendMode(...)` to affect image pixels while preserving the
current image attachment path for unblended images.

## Current Behavior

- `View.blendMode(_:)` and `View.compositingGroup()` lower into ordered draw
  effects. The rasterizer applies those effects when writing terminal cells.
- `Image` resolves to an image draw payload. Rasterization records that payload
  as a `RasterImageAttachment` instead of writing pixels into the cell grid.
- Terminal, WebHost, WASI/browser, and SwiftUI host presentation draw cells
  first, then draw image attachments on top.
- `SwiftTUIAnimatedImage` feeds each pre-composed frame through `Image(data:)`,
  so it inherits the same attachment behavior.

The shipped behavior is deliberate: terminal graphics protocols and browser or
native hosts can display high-fidelity images without forcing every image
through a cell fallback. The cost is that image attachments sit outside the
cell compositor. A blended background behind an image can still matter for
transparent image pixels, but the image pixels themselves are not multiplied,
screened, darkened, or lightened.

## Desired Contract

The target behavior should be SwiftUI-shaped but terminal-honest:

- Applying `.blendMode(mode)` to an `Image` blends the source image pixels with
  the visual backdrop at the image's visible bounds.
- Modifier order remains significant. `.blendMode(.multiply).compositingGroup()`
  blends inside the isolated group, while
  `.compositingGroup().blendMode(.multiply)` blends the flattened group against
  the parent backdrop.
- `AnimatedImage` needs no special public API. Each displayed frame should use
  the same image blending path as `Image(data:)`.
- Unblended images should keep the current native attachment path and should not
  pay a decode/precomposition cost solely because blend support exists.
- SwiftTUI should not claim arbitrary pixel-composition support. The terminal
  backend can approximate glyph-shaped backdrops because the framework does not
  own the user's terminal font rasterization.

## Non-Goals

- A general Skia, Metal, or CoreGraphics scene graph.
- Pixel-precise layout outside an image's own pixels and terminal cell bounds.
- Raw GIF decoding in the root `SwiftTUI` image surface. GIF playback remains
  owned by `SwiftTUIAnimatedImage`, which already produces PNG frame bytes.
- A public replacement for `Image`, `AnimatedImage`, or `blendMode(_:)`.

## Design Options

### Option 1: Force Blended Images Through Cell Fallback

When an image has an active blend mode, decode it to the existing half-block or
ASCII fallback overlay and run those cells through the current cell writer.

This is small, but it discards the main reason image attachments exist: high
fidelity graphics in Kitty, Sixel, WebHost, WASI/browser, and SwiftUI host
surfaces. It also makes blended images visibly lower quality than unblended
images. This should only be kept as a terminal fallback behavior.

### Option 2: Add an Ordered Graphics Scene Above RasterSurface

Move presentation from "final cell grid plus image attachments" to an ordered
layer list that can replay cells and images in authoring order. Web and SwiftUI
hosts could use native blend modes, and terminal hosts could interleave text and
graphics writes more faithfully.

This is the most complete model, but it is also a new presentation seam. It
would touch `RasterSurface`, terminal presentation planning, WebHost transport,
WASI transport, SwiftUI host drawing, snapshots, damage, and public-surface
baselines. It should be reserved for a broader graphics-native rendering
tranche, not the first image-blend implementation.

### Option 3: Precompose Blended Image Variants

Keep `RasterSurface` as the host boundary, but record enough compositing
metadata on image attachments for the runtime or host to create a blended image
variant. The variant is produced by decoding the source image, sampling the
captured backdrop for the image's visible bounds, applying `Color.composited`
with the active `BlendMode`, and presenting the resulting image through the
normal attachment path.

This is the recommended first implementation. It preserves high-fidelity image
presentation, keeps unblended images fast, and confines image decoding to the
runtime/host side rather than pulling image codecs into `SwiftTUICore`.

## Proposed Architecture

### Core Raster Model

Add an image compositing payload, for example:

```swift
public struct RasterImageCompositing: Equatable, Sendable {
  public var blendMode: BlendMode
  public var backdrop: RasterCellBackdrop
  public var cellPixelSize: PixelSize
}
```

The exact type names can change, but the responsibilities should not:

- `BlendMode` records the image's active blend mode at the point the image draw
  command is encountered.
- The backdrop captures the cells under `visibleBounds` before the image is
  appended.
- `cellPixelSize` lets the compositor expand the backdrop into the same pixel
  coordinate space as the scaled image.

`RasterImageAttachment` should gain an optional compositing field with a default
of `nil`. That keeps existing attachments and public initializers source
compatible.

### Rasterizer Changes

The rasterizer already threads `activeBlendMode` through the draw tree. The
image command branch should stop ignoring it. When `activeBlendMode` is non-nil,
the rasterizer should:

1. Clip the image bounds to `visibleBounds` as it does today.
2. Capture a cell backdrop slice from the current `cells` grid.
3. Attach `RasterImageCompositing` to the emitted `RasterImageAttachment`.

Compositing groups need a second pass. Today `paintCompositingGroup` carries
image attachments out of the isolated layer unblended. The new behavior should
either:

- precompose blended images while flattening the group layer, or
- preserve the group-local backdrop and defer precomposition until the runtime
  has the image bytes.

The second path fits the current layering better because `SwiftTUICore` should
remain terminal-IO-free and codec-free.

### Runtime Image Compositor

Add an `ImageBlendCompositor` beside `ImageAssetRepository` in
`SwiftTUIRuntime`. It should:

- Resolve and decode the attachment source through `ImageAssetRepository`.
- Scale and crop pixels using the same rules as the existing image renderers.
- Expand the captured cell backdrop to RGBA pixels.
- Apply the active `BlendMode` with the existing `Color.composited` math in
  linear sRGB.
- Return a new embedded image reference or decoded image variant.

The cache key must include:

- source image reference or embedded bytes identity,
- source crop and output pixel size,
- blend mode,
- cell pixel size,
- backdrop style/content signature,
- scaling mode,
- frame identity for animated images.

### Host Integration

Terminal graphics:

- Kitty and Sixel should transmit the blended variant when an attachment has
  image compositing metadata.
- Transparent source pixels need a defined rule. For the first tranche, fully
  transparent pixels should leave the captured backdrop unchanged in the
  precomposed output.
- Damage planning must replay graphics when either the source image changes or
  a dirty cell intersects the captured backdrop under a blended image.

Terminal fallback:

- The fallback overlay can keep using cells, but it should be generated from
  the blended variant so graphics and fallback agree.

WebHost and WASI/browser:

- The transport can send the blended image bytes as the normal image payload.
  This avoids requiring JavaScript `globalCompositeOperation` to reproduce the
  same order.
- A future ordered-layer transport could switch WebHost to native canvas blend
  modes, but that is not required for this proposal.

SwiftUI host:

- The native host should draw the blended variant when present.
- Host-native `CGContext` blend modes should wait for an ordered-layer model;
  drawing all cells first and then relying on native blend would blend against
  the wrong backdrop when later cells overlap the image bounds.

## Testing Plan

Core tests:

- `RasterizerTests` should assert that image attachments preserve bounds and
  also carry compositing metadata when an active blend mode exists.
- Existing blend-mode and compositing-group order tests should gain image cases
  that prove order is preserved at the metadata/backdrop level.

Runtime tests:

- Unit-test the image compositor with tiny RGBA fixtures for every `BlendMode`.
- Verify alpha behavior for transparent and translucent image pixels.
- Verify cache invalidation when only the backdrop color changes.
- Verify scaled-to-fit and scaled-to-fill source cropping.

Host tests:

- Terminal graphics tests should assert that blended attachments transmit a
  distinct image ID or payload from the unblended source.
- Terminal fallback tests should assert that the half-block overlay matches the
  blended colors.
- WASI transport tests should assert that blended image bytes are emitted only
  when needed and are retransmitted when the backdrop signature changes.
- WebHost canvas tests should verify that blended images draw through the same
  image path and do not require a new row format.
- SwiftUI host tests should cover source selection for blended variants, with
  visual snapshot testing deferred unless the host test harness already supports
  stable image comparisons.
- `SwiftTUIAnimatedImageTests` should assert that each frame can produce its own
  blended reference and that reduced-motion still renders the first blended
  frame.

## Work Breakdown

1. Define the behavioral contract in docs and tests.
2. Extend the raster model with optional image compositing metadata.
3. Capture backdrop cells when rasterizing image draw commands under an active
   blend mode.
4. Implement the runtime image compositor and cache keys.
5. Route terminal Kitty, Sixel, and fallback renderers through blended variants.
6. Route WASI/browser transport through blended variants.
7. Route SwiftUI host drawing through blended variants.
8. Add animated-image coverage.
9. Update `RENDER-PIPELINE.md`, DocC authoring docs, public API inventory, and
   host documentation once behavior ships.
10. Run `bun run test` before considering the implementation complete.

## Risks

- **Backdrop fidelity.** Terminal hosts cannot know exact glyph antialiasing
  from the user's terminal font. The implementation should document whether
  glyph foregrounds are approximated as solid cell coverage or whether the
  first tranche blends only against cell backgrounds.
- **Damage soundness.** A blended image depends on the cells behind it. Any
  damage inside that backdrop must invalidate the blended variant and replay
  graphics.
- **Cache growth.** Animated images over changing backgrounds can produce many
  blended variants. The runtime needs bounded storage or a frame-generation
  eviction policy.
- **Host divergence.** Native canvas/CoreGraphics blend modes may be tempting,
  but using them without ordered layers would blend against content that was
  painted later in authoring order.
- **Public API drift.** Adding fields to `RasterImageAttachment` is feasible,
  but it still affects the public inventory and must be handled deliberately.

## Recommended First Tranche

Start with the precomposed-variant path for non-overlapping images over cell
backgrounds. That tranche should prove the API behavior for
`Image(...).blendMode(...)`, preserve current unblended rendering, and expose
the damage/cache shape before taking on overlapping image layers or exact
glyph-shaped backdrop blending.
