import Foundation
import GIF
import Testing

@testable import GIFEditorCore

@Suite("GIFLoader")
struct GIFLoaderTests {

  @Test("Loading nyan.gif produces a multi-frame document with one layer per frame")
  func nyanLoads() throws {
    let url = nyanURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      // The fixture lives in the repo root; if a downstream consumer
      // copies the package without it the test self-skips rather than
      // failing the suite.
      return
    }
    let document = try GIFLoader.load(contentsOf: url)
    #expect(document.size.width == 70)
    #expect(document.size.height == 70)
    #expect(document.frames.count >= 6)
    for frame in document.frames {
      #expect(frame.layers.count == 1)
      #expect(frame.layers[0].pixels.size == document.size)
    }
  }

  @Test("Re-encoding a loaded document round-trips composited pixels")
  func reEncodingRoundTrip() throws {
    let url = nyanURL
    guard FileManager.default.fileExists(atPath: url.path) else { return }

    let document = try GIFLoader.load(contentsOf: url)
    let bytes = try GIFEncoder.encode(document: document)

    var source = ArraySource(bytes: bytes)
    let reDecoded = try GIF.Image.decompress(stream: &source)

    #expect(reDecoded.size.x == document.size.width)
    #expect(reDecoded.size.y == document.size.height)
    #expect(reDecoded.frames.count == document.frames.count)

    // Pick three sample cells per frame; if the encoder corrupted the
    // bitstream they would be wildly off, but the loader's nearest-color
    // mapping can introduce small perceptual differences for GIFs that
    // had >256 distinct colors. We assert the cells are at least
    // perceptually close (squared distance well under saturation).
    let toleranceSquared = 60 * 60 * 3
    for frameIndex in 0..<min(3, document.frames.count) {
      let originalFlat = document.flattenedColors(frameIndex: frameIndex)
      let reFlat = reDecoded.composited(frameIndex: frameIndex, as: GIF.RGBA<UInt8>.self)
      let samples = [0, originalFlat.count / 2, originalFlat.count - 1]
      for sample in samples {
        let original = originalFlat[sample]
        let actual = reFlat[sample]
        if let original, actual.a > 0 {
          let dr = Int(original.red) - Int(actual.r)
          let dg = Int(original.green) - Int(actual.g)
          let db = Int(original.blue) - Int(actual.b)
          let dist = dr * dr + dg * dg + db * db
          #expect(dist <= toleranceSquared)
        }
      }
    }
  }

  /// Locate `nyan.gif` in the repo root, walking up from this source
  /// file. Avoids hard-coded absolute paths and works whether the tests
  /// run from the example package or from the repo root.
  private var nyanURL: URL {
    let here = URL(fileURLWithPath: #filePath)
    let repoRoot =
      here
      .deletingLastPathComponent()  // GIFEditorCoreTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // gifeditor/
      .deletingLastPathComponent()  // Examples/
      .deletingLastPathComponent()  // swift-tui/
    return repoRoot.appendingPathComponent("nyan.gif")
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
