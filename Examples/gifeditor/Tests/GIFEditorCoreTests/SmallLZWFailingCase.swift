import Foundation
import GIF
import Testing

@testable import GIFEditorCore

/// Tiny minCodeSize=2 case that crosses the 3→4 bit boundary, useful
/// for narrowing down the bump-condition off-by-one.
@Suite("LZWEncoderBoundaryProbe")
struct SmallLZWFailingCase {
  @Test
  func threeToFourBitBoundary() throws {
    // 4-color palette → minCodeSize = 2, codes start at 3 bits.
    // Codes 0..3 are literals, 4 is clearCode, 5 is eoiCode, 6+ dynamic.
    // First codeSize bump to 4 happens when dynamic code count reaches
    // 1<<3 = 8. Need ~4 misses in a row to reach that.
    let palette = ColorPalette(
      colors: [
        .transparent,
        EditorColor(rgbHex: 0x000000),
        EditorColor(rgbHex: 0xFF0000),
        EditorColor(rgbHex: 0x00FF00),
      ]
    )
    // Indices designed to add 8+ unique pairs (1,2), (2,3), (3,1),
    // (1,3), (3,2), (2,1), then repeat to keep adding.
    let pattern: [PaletteIndex] = [1, 2, 3, 1, 3, 2, 1, 2, 3, 1, 2, 3, 2, 1, 3, 2]
    let indices = Array(repeating: pattern, count: 8).flatMap { $0 }

    let pixels = indices.map { Optional($0) }
    let buffer = PixelBuffer(
      size: PixelSize(width: 8, height: indices.count / 8),
      pixels: pixels
    )
    let document = GIFDocument(
      size: buffer.size,
      palette: palette,
      frames: [EditorFrame(layers: [EditorLayer(name: "L", pixels: buffer)])]
    )

    let bytes = try GIFEncoder.encode(document: document)
    var source = ArraySource(bytes: bytes)
    let decoded = try GIF.Image.decompress(stream: &source)
    let composited = decoded.composited(frameIndex: 0, as: GIF.RGBA<UInt8>.self)
    for (i, idx) in indices.enumerated() {
      let actual = composited[i]
      let expected = palette[idx]
      #expect(actual.r == expected.red)
      #expect(actual.g == expected.green)
      #expect(actual.b == expected.blue)
    }
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
