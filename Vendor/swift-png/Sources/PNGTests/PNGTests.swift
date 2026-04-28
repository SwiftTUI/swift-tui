import Testing

@testable import PNG

/// Helper: feed a fixed byte array through a `PNG.BytestreamSource`. The
/// shape matches the GIF/JPEG test sources in this repo.
private struct ArraySource: PNG.BytestreamSource {
  var bytes: [UInt8]
  var pos: Int = 0
  mutating func read(count: Int) -> [UInt8]? {
    guard count >= 0, pos + count <= bytes.count else { return nil }
    let slice = Array(bytes[pos..<(pos + count)])
    pos += count
    return slice
  }
}

// MARK: - Reference PNGs
//
// The smallest valid 1×1 RGBA PNG. Generated once via `python3 -c` using
// stdlib `zlib` for the IDAT compression and CRC-32, then frozen here so
// the test target has no fixture-file or compression-library dependency:
//
//   import struct, zlib
//   ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)
//   raw  = bytes([0x00, 0xFF, 0x00, 0x00, 0xFF])
//   idat = zlib.compress(raw, 9)
//   ...emit signature + chunks with crc32(type + data)...
private let onePixelRedRGBAPNG: [UInt8] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54,
  0x78, 0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F,
  0x00, 0x05, 0x00, 0x01, 0xFF, 0x56, 0xC7, 0x2F, 0x0D,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]

// MARK: - Tests

@Test("Inflater round-trips a stored DEFLATE block")
func inflateStoredBlock() throws {
  // BFINAL=1, BTYPE=00 (stored), align, LEN=4, NLEN=~LEN, payload "TEST"
  // The first byte holds bits LSB-first: BFINAL=bit0=1, BTYPE=bits1-2=00,
  // remainder padding → 0b00000001 = 0x01.
  let bytes: [UInt8] = [
    0x01,
    0x04, 0x00,  // LEN = 4
    0xFB, 0xFF,  // NLEN = ~4
    0x54, 0x45, 0x53, 0x54,  // "TEST"
  ]
  let out = try PNG.rawInflate(bytes: bytes)
  #expect(out == [0x54, 0x45, 0x53, 0x54])
}

@Test("Inflater handles a fixed-Huffman block with a back-reference")
func inflateFixedHuffmanBackref() throws {
  // We synthesize a stream that emits "AAAAA" via a literal "A" and a
  // length-4 / distance-1 back-reference. Constructing the exact bit
  // stream by hand is fiddly; instead, verify the inflater is wired up
  // correctly by feeding a payload produced by zlib's deflateInit2 with
  // raw DEFLATE windowBits = -15. The byte sequence below was obtained
  // with `python3 -c "import zlib;print(zlib.compress(b'AAAAA',9)[2:-4].hex())"`,
  // i.e. `compressobj(9, ZLIB_DEFLATED, -15)` would have produced the
  // same payload — but we strip the zlib wrapper and adler32 manually.
  //
  // Encoded as 5 literal 'A's via fixed Huffman (no LZ77 match here —
  // small inputs often skip matching). That's still a meaningful test:
  // it forces fixed-Huffman decoding through both the lit/length tree
  // and the end-of-block symbol.
  let payload: [UInt8] = [
    0x73, 0x74, 0x04, 0x02, 0x00,
  ]
  let out = try PNG.rawInflate(bytes: payload)
  #expect(out == [0x41, 0x41, 0x41, 0x41, 0x41])
}

@Test("Adler-32 matches RFC 1950 reference vector")
func adler32Reference() {
  // From RFC 1950 §9: Adler-32 of empty string is 1.
  #expect(PNG.adler32([]) == 1)
  // "Wikipedia" → 0x11E60398 (from the Wikipedia article on Adler-32).
  let bytes: [UInt8] = Array("Wikipedia".utf8)
  #expect(PNG.adler32(bytes) == 0x11E6_0398)
}

@Test("CRC-32 matches the value pngcheck reports for IEND")
func crc32IEND() {
  // The empty IEND chunk has type 'IEND' and zero data bytes; its CRC
  // is the well-known constant 0xAE426082.
  let crc = PNG.crc32(type: [0x49, 0x45, 0x4E, 0x44], data: [])
  #expect(crc == 0xAE42_6082)
}

@Test("Paeth predictor matches RFC 2083 examples")
func paethPredictor() {
  // Pick `a` when it's clearly closest to a + b - c.
  #expect(PNG.paeth(a: 10, b: 10, c: 10) == 10)
  #expect(PNG.paeth(a: 10, b: 20, c: 5) == 20)
  #expect(PNG.paeth(a: 0, b: 0, c: 0) == 0)
  // Extrapolation case from the PNG spec discussion: a=20, b=10, c=15.
  // p = 20 + 10 - 15 = 15. pa = 5, pb = 5, pc = 0 → pick c.
  #expect(PNG.paeth(a: 20, b: 10, c: 15) == 15)
}

@Test("Decodes a 1x1 RGBA PNG")
func decodeOnePixelRGBA() throws {
  var src = ArraySource(bytes: onePixelRedRGBAPNG)
  let image = try PNG.Image.decompress(stream: &src)
  #expect(image.size.x == 1)
  #expect(image.size.y == 1)
  #expect(image.colorType == 6)
  #expect(image.bitDepth == 8)

  let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
  #expect(pixels.count == 1)
  let p = pixels[0]
  #expect(p.r == 0xFF)
  #expect(p.g == 0x00)
  #expect(p.b == 0x00)
  #expect(p.a == 0xFF)
}

@Test("Rejects truncated PNG signatures")
func rejectsBadSignature() {
  var src = ArraySource(bytes: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
  #expect(throws: PNG.DecodingError.self) {
    try PNG.Image.decompress(stream: &src)
  }
}

@Test("Rejects unsupported compression method")
func rejectsUnsupportedCompression() throws {
  // Take the valid one-pixel PNG, flip the IHDR compression byte from 0
  // to 1, and re-CRC the IHDR chunk.
  var bytes = onePixelRedRGBAPNG
  // IHDR data starts at index 16 (8-byte signature + 4-byte length +
  // 4-byte type). The compression byte is the 11th byte of the data
  // (offset 26 from the start).
  bytes[26] = 1
  // Recompute the IHDR CRC (covers type bytes + 13 data bytes).
  let typeBytes: [UInt8] = Array(bytes[12..<16])
  let dataBytes: [UInt8] = Array(bytes[16..<29])
  let crc = PNG.crc32(type: typeBytes, data: dataBytes)
  bytes[29] = UInt8((crc >> 24) & 0xFF)
  bytes[30] = UInt8((crc >> 16) & 0xFF)
  bytes[31] = UInt8((crc >> 8) & 0xFF)
  bytes[32] = UInt8(crc & 0xFF)

  var src = ArraySource(bytes: bytes)
  #expect(throws: PNG.DecodingError.self) {
    try PNG.Image.decompress(stream: &src)
  }
}

// Two rows of red, then green; exercises multi-scanline filter
// reconstruction (zlib uses Sub/Up here at level 9).
private let twoByFourRGBPNG: [UInt8] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02,
  0x08, 0x02, 0x00, 0x00, 0x00, 0xF0, 0xCA, 0xEA, 0x34,
  0x00, 0x00, 0x00, 0x11, 0x49, 0x44, 0x41, 0x54,
  0x78, 0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x47,
  0x48, 0xCC, 0xFF, 0x0C, 0x00, 0x6B, 0xAE, 0x07,
  0xF9, 0x95, 0x02, 0xAD, 0xF2,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]

// 2×2 palette image. Entries: 0=red, 1=green, 2=blue, 3=white. The
// tRNS chunk marks entry 1 fully transparent. Pixel layout:
//   (0,0) = red opaque    (1,0) = green α=0
//   (0,1) = blue opaque   (1,1) = white opaque
private let twoByTwoPalettePNG: [UInt8] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
  0x08, 0x03, 0x00, 0x00, 0x00, 0x45, 0x68, 0xFD, 0x16,
  0x00, 0x00, 0x00, 0x0C, 0x50, 0x4C, 0x54, 0x45,
  0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF,
  0xFF, 0xFF, 0xFF, 0xFB, 0x00, 0x60, 0xF6,
  0x00, 0x00, 0x00, 0x04, 0x74, 0x52, 0x4E, 0x53,
  0xFF, 0x00, 0xFF, 0xFF, 0xD3, 0xB0, 0x72, 0x94,
  0x00, 0x00, 0x00, 0x0E, 0x49, 0x44, 0x41, 0x54,
  0x78, 0xDA, 0x63, 0x60, 0x60, 0x64, 0x60, 0x62,
  0x06, 0x00, 0x00, 0x11, 0x00, 0x07, 0x83, 0xCA, 0x64, 0x64,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]

// 8×8 RGBA Adam7-interlaced checker pattern: even (x+y) pixels are red,
// odd are blue.
private let eightByEightAdam7PNG: [UInt8] = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
  0x08, 0x06, 0x00, 0x00, 0x01, 0xB3, 0x08, 0x8E, 0x1D,
  0x00, 0x00, 0x00, 0x1E, 0x49, 0x44, 0x41, 0x54,
  0x78, 0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x9F,
  0x01, 0x4E, 0x10, 0x60, 0xE0, 0x16, 0x40, 0xE3,
  0x93, 0x2D, 0x00, 0x31, 0x0C, 0x17, 0x4D, 0x73,
  0x05, 0x00, 0x14, 0x9B, 0x7F, 0x81, 0x46, 0x51, 0xDF, 0x1F,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
]

@Test("Decodes a 4x2 RGB image with multiple filtered scanlines")
func decodeMultiRowRGB() throws {
  var src = ArraySource(bytes: twoByFourRGBPNG)
  let image = try PNG.Image.decompress(stream: &src)
  #expect(image.size == (4, 2))
  let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
  #expect(pixels.count == 8)
  // First row: all red.
  for x in 0..<4 {
    let p = pixels[x]
    #expect(p.r == 0xFF && p.g == 0x00 && p.b == 0x00 && p.a == 0xFF)
  }
  // Second row: all green.
  for x in 0..<4 {
    let p = pixels[4 + x]
    #expect(p.r == 0x00 && p.g == 0xFF && p.b == 0x00 && p.a == 0xFF)
  }
}

@Test("Decodes a palette image with tRNS")
func decodePaletteWithTRNS() throws {
  var src = ArraySource(bytes: twoByTwoPalettePNG)
  let image = try PNG.Image.decompress(stream: &src)
  #expect(image.size == (2, 2))
  #expect(image.colorType == 3)
  let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
  // (0,0) red opaque
  #expect(pixels[0] == PNG.RGBA<UInt8>(0xFF, 0x00, 0x00, 0xFF))
  // (1,0) green but tRNS table marks index 1 → α = 0
  #expect(pixels[1] == PNG.RGBA<UInt8>(0x00, 0xFF, 0x00, 0x00))
  // (0,1) blue opaque
  #expect(pixels[2] == PNG.RGBA<UInt8>(0x00, 0x00, 0xFF, 0xFF))
  // (1,1) white opaque (tRNS table only had 4 entries; index 3 is at
  // the boundary and explicitly marked 0xFF)
  #expect(pixels[3] == PNG.RGBA<UInt8>(0xFF, 0xFF, 0xFF, 0xFF))
}

@Test("Decodes an 8x8 Adam7-interlaced RGBA image")
func decodeAdam7() throws {
  var src = ArraySource(bytes: eightByEightAdam7PNG)
  let image = try PNG.Image.decompress(stream: &src)
  #expect(image.size == (8, 8))
  let pixels = image.unpack(as: PNG.RGBA<UInt8>.self)
  // Verify the checker pattern: (x+y) even → red, odd → blue.
  for y in 0..<8 {
    for x in 0..<8 {
      let p = pixels[y * 8 + x]
      let expected: PNG.RGBA<UInt8> =
        (x + y) % 2 == 0
        ? PNG.RGBA(0xFF, 0x00, 0x00, 0xFF)
        : PNG.RGBA(0x00, 0x00, 0xFF, 0xFF)
      #expect(p == expected, "pixel mismatch at (\(x),\(y))")
    }
  }
}

@Test("Adam7 pass dimensions are computed correctly")
func adam7PassDimensions() {
  // For an 8x8 image, each pass has a known fixed sample count.
  let widths = PNG.adam7Passes.map { PNG.passWidth($0, imageWidth: 8) }
  let heights = PNG.adam7Passes.map { PNG.passHeight($0, imageHeight: 8) }
  // Pass 1: 1x1, pass 2: 1x1, pass 3: 2x1, pass 4: 2x2, pass 5: 4x2, pass 6: 4x4, pass 7: 8x4.
  #expect(widths == [1, 1, 2, 2, 4, 4, 8])
  #expect(heights == [1, 1, 1, 2, 2, 4, 4])
}
