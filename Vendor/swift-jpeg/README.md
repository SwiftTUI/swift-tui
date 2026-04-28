# swift-jpeg

A pure-Swift baseline JPEG decoder. The public surface mirrors
[`swift-png`](../swift-png) so call sites are nearly identical:

```swift
import JPEG

var source = MyBytestreamSource(buffer)
let image  = try JPEG.Image.decompress(stream: &source)
let pixels = image.unpack(as: JPEG.RGBA<UInt8>.self)
let (w, h) = image.size
```

## Scope

This decoder implements **baseline sequential JPEG** (the variant produced
by virtually all cameras, browsers, and editors), specifically:

- 8-bit precision, baseline DCT (`SOF0`)
- 1-component grayscale, 3-component YCbCr (JFIF), 4-component CMYK / YCCK
- Common chroma subsamplings (`4:4:4`, `4:2:2`, `4:2:0`, `4:1:1`, `4:4:0`)
- Restart markers (`DRI` / `RST0–RST7`)
- Standard `APPn` / `COM` segments (parsed but ignored)

It deliberately does **not** implement progressive (`SOF2`), lossless
(`SOF3`), arithmetic coding, hierarchical, or 12-bit precision. Files using
those modes will throw a clear `JPEG.DecodingError`.

## License

MIT. See `LICENSE`.
