# swift-png

A pure-Swift PNG decoder.

```swift
import PNG

var source = MyBytestreamSource(buffer)
let image  = try PNG.Image.decompress(stream: &source)
let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
let (w, h) = image.size
```

The public surface (`PNG.Image`, `PNG.RGBA<T>`, `PNG.BytestreamSource`,
`PNG.DecodingError`) is the same shape as `swift-jpeg` and `swift-gif`,
so a single `BytestreamSource` adapter type can serve all three
decoders.

## Scope

This decoder implements the full PNG (RFC 2083) feature set used by
real-world files:

- 8-byte signature + chunk framing with CRC-32 verification
- All five color types (grayscale, RGB, palette, grayscale+α, RGBA)
- All legal bit depths (1, 2, 4, 8, 16) for each color type
- All five scanline filters (None, Sub, Up, Average, Paeth)
- Interlacing (Adam7, 7-pass deinterleave)
- `tRNS` transparency for color types 0, 2, and 3
- zlib-wrapped DEFLATE (`IDAT`) inflation, including:
  - Stored, fixed-Huffman, and dynamic-Huffman blocks
  - Adler-32 trailer verification
- `PLTE` palette parsing
- Ancillary chunks (`gAMA`, `cHRM`, `sRGB`, `pHYs`, `tEXt`, `iTXt`,
  `zTXt`, …) parsed and skipped after CRC validation

It deliberately does **not** include an APNG (animation) extension or
PNG encoder — the GIF and JPEG vendor packages are also decode-only.

## License

MIT. See `LICENSE`.
