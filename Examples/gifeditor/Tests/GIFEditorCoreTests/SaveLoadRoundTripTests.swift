import Foundation
import GIF
import Testing

@testable import GIFEditorCore

@Suite("Save / load round-trip")
struct SaveLoadRoundTripTests {

  @Test("Editing a blank document, encoding it, then loading the bytes preserves pixel content")
  func authoringRoundTripsThroughDisk() throws {
    var doc = GIFDocument.blank(size: PixelSize(width: 16, height: 16))
    // Pen a small red diamond in the middle of frame 1.
    let red: PaletteIndex = 6  // matches default palette's red slot
    var layer = doc.frames[0].layers[0]
    var pixels = layer.pixels
    let center = PixelPoint(x: 7, y: 7)
    for d in -3...3 {
      pixels[PixelPoint(x: center.x + d, y: center.y)] = red
      pixels[PixelPoint(x: center.x, y: center.y + d)] = red
    }
    layer.pixels = pixels
    doc.frames[0].layers[0] = layer

    // Add a second frame so we exercise multi-frame writing.
    let second = EditorFrame(
      layers: [EditorLayer(name: "L", pixels: PixelBuffer(size: doc.size, fill: 1))]
    )
    doc.frames.append(second)

    let bytes = try GIFEncoder.encode(document: doc)

    // Round-trip through the public decoder bridge.
    let tempDir = FileManager.default.temporaryDirectory
    let url = tempDir.appendingPathComponent("gifeditor-roundtrip-\(UUID().uuidString).gif")
    try Data(bytes).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let reloaded = try GIFLoader.load(contentsOf: url)
    #expect(reloaded.size == doc.size)
    #expect(reloaded.frames.count == doc.frames.count)

    // The diamond's center pixel should still be red.
    let originalRed = doc.palette[red]
    let reloadedFlat = reloaded.flattenedColors(frameIndex: 0)
    let reloadedCenter = reloadedFlat[reloaded.size.indexOf(center)]
    #expect(reloadedCenter != nil)
    if let reloadedCenter {
      #expect(reloadedCenter.red == originalRed.red)
      #expect(reloadedCenter.green == originalRed.green)
      #expect(reloadedCenter.blue == originalRed.blue)
    }
  }
}
