# ``SwiftTUIAnimatedImage``

Animate finite pre-composed image sequences and import or export GIFs.

## Overview

`SwiftTUIAnimatedImage` ships inside the batteries-included `SwiftTUI`
product — `import SwiftTUI` re-exports it — and is also available as a
standalone SwiftPM library product for narrower compositions. It keeps GIF
decoding and animated playback out of the core runtime while rendering
through the same `SwiftTUIViews` surface as static images. `Image(data:)`
never decodes GIF containers itself; to animate a GIF, decode it with
``AnimatedGIF`` and display the result with ``AnimatedImage``.

## Loading and playing a GIF

``AnimatedGIF`` turns GIF container bytes into an ``AnimatedImageSequence``
— fully composited RGBA frames plus one display delay per frame — and
``AnimatedImage`` plays that sequence as a view:

```swift
let animation = try AnimatedGIF.decode(contentsOf: "nyan.gif")
// or, with the container bytes already in memory:
// let animation = try AnimatedGIF.decode(data: gifBytes)

struct GIFPlayer: View {
  let animation: AnimatedImageSequence

  var body: some View {
    AnimatedImage(animation)
  }
}
```

The throwing initializers `AnimatedImage(gifData:)` and
`AnimatedImage(gifContentsOf:)` collapse the decode step when you do not
need the sequence value itself. Decoding normalizes GIF timing: a zero
delay becomes 100 ms, and all delays are floored at 20 ms.

## Playback

A sequence with more than one frame starts playing when the view appears
and loops indefinitely, waiting each frame's own delay before advancing;
the playback task is cancelled with the view. Changing the view's sequence
value restarts playback from the first frame. A single-frame sequence
renders as a static image with no playback task. The test suite drives a
real run loop and asserts that every GIF-decoded frame is presented and
that a two-frame round trip preserves distinct 50 ms and 120 ms delays.

Each frame reaches the renderer as PNG bytes through the same
`Image(data:)` surface as static images — encoded once per frame and
cached — so modifiers such as `.blendMode(...)` composite the current
frame exactly as they would a static image.

## Authoring frames in code

Frames are plain values: an ``AnimatedImageFrame`` is a pixel size plus a
row-major array of 8-bit RGBA ``AnimatedImagePixel`` values. All frames in
one sequence must share the same pixel size. Provide timing as a uniform
frame rate or as one explicit delay per frame:

```swift
let red = AnimatedImageFrame(
  width: 1,
  height: 1,
  pixels: [AnimatedImagePixel(red: 255, green: 0, blue: 0)]
)
let blue = AnimatedImageFrame(
  width: 1,
  height: 1,
  pixels: [AnimatedImagePixel(red: 0, green: 0, blue: 255)]
)

AnimatedImage(frames: [red, blue], framesPerSecond: 12)
AnimatedImage(
  frames: [red, blue],
  frameDelays: [.milliseconds(80), .milliseconds(120)]
)
```

## Exporting a GIF

``AnimatedGIF`` also encodes a sequence back into GIF file bytes. The
default `loopCount` of `0` marks the file to loop forever:

```swift
let sequence = AnimatedImageSequence(
  frames: [red, blue],
  frameDelays: [.milliseconds(50), .milliseconds(120)]
)
let gifBytes = try AnimatedGIF.encode(sequence)
```

The encoder builds a palette of up to 256 distinct colors and snaps any
extra colors to the nearest palette entry. Fully transparent pixels stay
transparent; partial alpha becomes opaque. Delays round up to whole
centiseconds, the GIF container's resolution, so centisecond-precision
delays — and every frame's pixels — survive an encode/decode round trip
exactly.

## Reduced motion and stable output

Under reduced motion — the `--reduce-motion` flag,
`SWIFTTUI_REDUCE_MOTION=1`, or the `--accessible` /
`SWIFTTUI_ACCESSIBLE=1` alias — ``AnimatedImage`` renders only the first
frame and starts no playback task. Stable-output capture (CI, a non-TTY
stdout, or `SWIFTTUI_STABLE_OUTPUT=1`) pins the first frame the same way
without reporting a reduced-motion preference to app code through
`accessibilityReduceMotion`. Tests assert both: the first frame is the
rendered attachment and the task registry stays empty.

## Topics

### Views

- ``AnimatedImage``

### Sequences

- ``AnimatedImageSequence``
- ``AnimatedImageFrame``
- ``AnimatedImagePixel``

### GIF

- ``AnimatedGIF``
