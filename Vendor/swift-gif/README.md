# swift-gif

A pure-Swift GIF decoder and indexed-color encoder.

```swift
import GIF

var source = MyBytestreamSource(buffer)
let image  = try GIF.Image.decompress(stream: &source)
let pixels = image.unpack(as: GIF.RGBA<UInt8>.self)
let (w, h) = image.size
let plays  = image.loopCount ?? 1  // no NETSCAPE block == plays once

let encoded = try GIF.Encoder.encode(
  GIF.IndexedImage(
    size: (x: 2, y: 1),
    globalColorTable: [(r: 255, g: 0, b: 0), (r: 0, g: 0, b: 255)],
    loopCount: 0,  // forever; 1 plays once
    frames: [
      GIF.IndexedFrame(left: 0, top: 0, width: 2, height: 1, indices: [0, 1])
    ]
  )
)
```

A frame's `left` / `top` place it inside the logical screen, so a frame
need not cover the whole canvas — that is what makes delta-coded
animations (each frame carrying only the rectangle that changed)
expressible.

## Scope

The decoder implements the GIF87a and GIF89a formats, including:

- Logical Screen Descriptor + global / local color tables
- LZW-compressed pixel data with variable code-size growth (9–12 bits)
- Interlaced GIFs (4-pass deinterleave)
- Graphics Control Extensions (transparent index, frame delay, disposal)
- The `NETSCAPE2.0` / `ANIMEXTS1.0` looping extension, surfaced as
  ``GIF.Image/loopCount`` (`nil` when the file declares none)
- Comment / Plain-Text and every other Application extension (skipped)
- Multiple frames (decoded into ``GIF.Frame`` values)

The encoder writes GIF89a indexed images with:

- One global color table, padded to the required power-of-two size
- GIF LZW compression with sub-block framing
- Graphics Control Extensions for delay, disposal, and transparency
- Netscape looping extension for animated images

`GIF.Image.unpack(as:)` returns the **first frame composited onto the
logical screen** as `RGBA<T>` — the typical "static GIF preview" view.
For animation, walk ``GIF.Image/frames`` and use ``GIF.Image/composited(frameIndex:)``
to get later frames.

## License

MIT. See `LICENSE`.
