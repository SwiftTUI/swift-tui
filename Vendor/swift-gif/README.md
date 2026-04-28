# swift-gif

A pure-Swift GIF decoder.

```swift
import GIF

var source = MyBytestreamSource(buffer)
let image  = try GIF.Image.decompress(stream: &source)
let pixels = image.unpack(as: GIF.RGBA<UInt8>.self)
let (w, h) = image.size
```

## Scope

This decoder implements the GIF87a and GIF89a formats, including:

- Logical Screen Descriptor + global / local color tables
- LZW-compressed pixel data with variable code-size growth (9–12 bits)
- Interlaced GIFs (4-pass deinterleave)
- Graphics Control Extensions (transparent index, frame delay, disposal)
- Comment / Application / Plain-Text extensions (parsed and skipped)
- Multiple frames (decoded into ``GIF.Frame`` values)

`GIF.Image.unpack(as:)` returns the **first frame composited onto the
logical screen** as `RGBA<T>` — the typical "static GIF preview" view.
For animation, walk ``GIF.Image/frames`` and use ``GIF.Image/composited(frameIndex:)``
to get later frames.

## License

MIT. See `LICENSE`.
