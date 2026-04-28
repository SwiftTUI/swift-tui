# swift-gif

A pure-Swift GIF decoder and indexed-color encoder.

```swift
import GIF

var source = MyBytestreamSource(buffer)
let image  = try GIF.Image.decompress(stream: &source)
let pixels = image.unpack(as: GIF.RGBA<UInt8>.self)
let (w, h) = image.size

let encoded = try GIF.Encoder.encode(
  GIF.IndexedImage(
    size: (x: 1, y: 1),
    globalColorTable: [(r: 255, g: 0, b: 0)],
    frames: [
      GIF.IndexedFrame(width: 1, height: 1, indices: [0])
    ]
  )
)
```

## Scope

The decoder implements the GIF87a and GIF89a formats, including:

- Logical Screen Descriptor + global / local color tables
- LZW-compressed pixel data with variable code-size growth (9–12 bits)
- Interlaced GIFs (4-pass deinterleave)
- Graphics Control Extensions (transparent index, frame delay, disposal)
- Comment / Application / Plain-Text extensions (parsed and skipped)
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
