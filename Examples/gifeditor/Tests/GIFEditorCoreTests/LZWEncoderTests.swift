import Foundation
import GIF
import Testing

@testable import GIFEditorCore

@Suite("LZWEncoder")
struct LZWEncoderTests {

  @Test("9-bit minCodeSize round-trip via a wrapped GIF89a")
  func ninebitRoundTripViaPublicDecoder() throws {
    // 256-color palette → minCodeSize = 8, codes start at 9 bits.
    // Round-tripping through the public decoder also exercises the
    // sub-block framing in the encoder.
    let count = 5000
    var indices = [UInt8]()
    indices.reserveCapacity(count)
    var seed: UInt32 = 1
    for _ in 0..<count {
      // Reproducible LCG so the input is seed-stable.
      seed = seed &* 1_664_525 &+ 1_013_904_223
      indices.append(UInt8((seed >> 16) & 0xFF))
    }

    let document = makeDocument(indices: indices, width: 100, height: 50)
    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)

    let palette = document.palette
    for (i, raw) in indices.enumerated() {
      let actual = composited[i]
      // makeDocument shifts 0 → 1 so the GIF transparent slot doesn't
      // swallow input bytes; mirror that here when computing expected.
      let expected = palette[max(1, raw)]
      #expect(actual.r == expected.red)
      #expect(actual.g == expected.green)
      #expect(actual.b == expected.blue)
    }
  }

  @Test("Long stream that forces every codeSize bump round-trips cleanly")
  func longMonotonic() throws {
    // 80 copies of every byte 0..255 — runs are long, but every byte
    // value appears, so the dictionary keeps growing. Crosses
    // 9→10→11→12 bit boundaries and almost certainly emits at least
    // one mid-stream clear code.
    var indices = [UInt8]()
    indices.reserveCapacity(20480)
    for byte in 0..<256 {
      for _ in 0..<80 {
        indices.append(UInt8(byte))
      }
    }
    // 20480 = 160 × 128.
    let document = makeDocument(indices: indices, width: 160, height: 128)
    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)

    let palette = document.palette
    for (i, raw) in indices.enumerated() {
      let actual = composited[i]
      // makeDocument shifts 0 → 1 so the GIF transparent slot doesn't
      // swallow input bytes; mirror that here when computing expected.
      let expected = palette[max(1, raw)]
      #expect(actual.r == expected.red)
      #expect(actual.g == expected.green)
      #expect(actual.b == expected.blue)
    }
  }

  // MARK: - Helpers

  /// Builds a 256-color document of `width × height` whose pixel buffer
  /// is exactly the given indices. Slot 0 is transparent so opaque
  /// indices are 1..255 — and the input is shifted to fall in 1...255
  /// to dodge the GIF transparent slot.
  private func makeDocument(
    indices: [UInt8],
    width: Int,
    height: Int
  ) -> GIFDocument {
    precondition(indices.count == width * height)
    var entries: [EditorColor] = [.transparent]
    for i in 1..<256 {
      entries.append(EditorColor(rgbHex: UInt32(i * 65793)))  // distinct grays
    }
    let palette = ColorPalette(colors: entries)

    var pixels = [PaletteIndex?](repeating: nil, count: indices.count)
    for (i, raw) in indices.enumerated() {
      // Shift 0..255 → 1..255 → keep transparency reserved at slot 0.
      pixels[i] = max(1, raw)
    }
    let buffer = PixelBuffer(
      size: PixelSize(width: width, height: height), pixels: pixels
    )
    return GIFDocument(
      size: PixelSize(width: width, height: height),
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "L", pixels: buffer)])]
    )
  }
}

private struct ArraySource: GIF.BytestreamSource {
  var bytes: [UInt8]
  var offset = 0

  mutating func read(count: Int) -> [UInt8]? {
    guard offset < bytes.count else { return nil }
    let end = min(offset + count, bytes.count)
    let chunk = Array(bytes[offset..<end])
    offset = end
    return chunk
  }
}
