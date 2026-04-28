import PNG

@testable import Core

/// Builds a minimal RGBA8 PNG bytestream from `pixels` arranged in
/// row-major order. Used by tests that need real PNG bytes flowing
/// through the renderer's decode path; correctness — not byte-size —
/// is the goal, so the IDAT payload uses uncompressed deflate "stored"
/// blocks. Works without an external encoder dependency, so the test
/// surface stays consistent across the swift-png decode-only vendor.
func makePNGBytes(
  width: Int,
  height: Int,
  pixels: [PNG.RGBA<UInt8>]
) throws -> [UInt8] {
  precondition(
    pixels.count == width * height,
    "pixel buffer must be width*height (got \(pixels.count), expected \(width * height))"
  )

  // Raw scanlines: each row is prefixed with a single filter byte (0 =
  // no filtering), followed by RGBA bytes in left-to-right order.
  var raw: [UInt8] = []
  raw.reserveCapacity(height * (1 + width * 4))
  for row in 0..<height {
    raw.append(0)  // no filter
    for col in 0..<width {
      let p = pixels[row * width + col]
      raw.append(p.r)
      raw.append(p.g)
      raw.append(p.b)
      raw.append(p.a)
    }
  }

  let idat = makeUncompressedZlibStream(of: raw)

  var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  out.append(
    contentsOf: makePNGChunk(
      type: "IHDR",
      data: makeIHDRData(width: width, height: height)
    ))
  out.append(contentsOf: makePNGChunk(type: "IDAT", data: idat))
  out.append(contentsOf: makePNGChunk(type: "IEND", data: []))
  return out
}

func makeRasterImageAttachment(
  pngBytes: [UInt8],
  pixelSize: Size,
  bounds: Rect,
  visibleBounds: Rect? = nil,
  identity: Identity = testIdentity("Root", "Image")
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: identity,
    bounds: bounds,
    visibleBounds: visibleBounds,
    source: .data(pngBytes),
    resolvedReference: .embeddedImage(pngBytes),
    pixelSize: pixelSize,
    isResizable: false,
    scalingMode: .stretch
  )
}

func rgbaPixel(
  red: UInt8,
  green: UInt8,
  blue: UInt8,
  alpha: UInt8 = 255
) -> PNG.RGBA<UInt8> {
  .init(red, green, blue, alpha)
}

// MARK: - Minimal PNG encoder (RGBA8, uncompressed deflate)

private func makeIHDRData(
  width: Int,
  height: Int
) -> [UInt8] {
  var data = [UInt8]()
  data.reserveCapacity(13)
  data.append(contentsOf: bigEndianUInt32(UInt32(width)))
  data.append(contentsOf: bigEndianUInt32(UInt32(height)))
  data.append(8)  // bit depth
  data.append(6)  // color type: RGBA
  data.append(0)  // compression method: deflate
  data.append(0)  // filter method: 0
  data.append(0)  // interlace method: none
  return data
}

private func makePNGChunk(
  type: String,
  data: [UInt8]
) -> [UInt8] {
  var out = [UInt8]()
  out.reserveCapacity(8 + data.count + 4)
  out.append(contentsOf: bigEndianUInt32(UInt32(data.count)))
  let typeBytes = Array(type.utf8)
  out.append(contentsOf: typeBytes)
  out.append(contentsOf: data)
  out.append(contentsOf: bigEndianUInt32(crc32(typeBytes + data)))
  return out
}

/// Wraps `raw` in a zlib stream whose deflate payload is one or more
/// `BTYPE=00` (stored, uncompressed) blocks. This is the simplest valid
/// deflate output: each block carries up to 65535 raw bytes verbatim.
private func makeUncompressedZlibStream(of raw: [UInt8]) -> [UInt8] {
  var out: [UInt8] = []

  // zlib header: deflate method, 32K window, FCHECK chosen so
  // (CMF * 256 + FLG) is divisible by 31.
  let cmf: UInt8 = 0x78
  let flg: UInt8 = 0x01
  out.append(cmf)
  out.append(flg)

  // Stored deflate blocks.
  let maxBlock = 65_535
  var index = 0
  while index < raw.count {
    let remaining = raw.count - index
    let chunk = min(remaining, maxBlock)
    let isFinal = (index + chunk) == raw.count
    out.append(isFinal ? 0x01 : 0x00)  // BFINAL + BTYPE=00
    let len = UInt16(chunk)
    out.append(UInt8(len & 0xFF))
    out.append(UInt8((len >> 8) & 0xFF))
    let nlen = ~len
    out.append(UInt8(nlen & 0xFF))
    out.append(UInt8((nlen >> 8) & 0xFF))
    out.append(contentsOf: raw[index..<(index + chunk)])
    index += chunk
  }

  // Empty stream guard: deflate must contain at least one block.
  if raw.isEmpty {
    out.append(0x01)  // BFINAL + BTYPE=00
    out.append(0x00)
    out.append(0x00)
    out.append(0xFF)
    out.append(0xFF)
  }

  // Adler-32 of raw bytes, big-endian.
  out.append(contentsOf: bigEndianUInt32(adler32(raw)))
  return out
}

private func bigEndianUInt32(_ value: UInt32) -> [UInt8] {
  [
    UInt8((value >> 24) & 0xFF),
    UInt8((value >> 16) & 0xFF),
    UInt8((value >> 8) & 0xFF),
    UInt8(value & 0xFF),
  ]
}

/// CRC-32/ISO-HDLC, the variant required by PNG (poly 0xEDB88320,
/// initial 0xFFFFFFFF, final XOR 0xFFFFFFFF).
private func crc32(_ bytes: [UInt8]) -> UInt32 {
  var crc: UInt32 = 0xFFFF_FFFF
  for byte in bytes {
    crc ^= UInt32(byte)
    for _ in 0..<8 {
      let mask = UInt32(0) &- (crc & 1)
      crc = (crc >> 1) ^ (0xEDB8_8320 & mask)
    }
  }
  return crc ^ 0xFFFF_FFFF
}

/// Adler-32 (RFC 1950) — required by zlib stream trailer.
private func adler32(_ bytes: [UInt8]) -> UInt32 {
  var a: UInt32 = 1
  var b: UInt32 = 0
  let modulus: UInt32 = 65_521
  for byte in bytes {
    a = (a + UInt32(byte)) % modulus
    b = (b + a) % modulus
  }
  return (b << 16) | a
}
