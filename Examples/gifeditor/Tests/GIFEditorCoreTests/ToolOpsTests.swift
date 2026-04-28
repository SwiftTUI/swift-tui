import Foundation
import Testing

@testable import GIFEditorCore

@Suite("ToolOps")
struct ToolOpsTests {

  @Test("Pen writes the requested index and leaves other pixels untouched")
  func penWritesOneCell() {
    var buffer = PixelBuffer(size: PixelSize(width: 3, height: 3))
    buffer[PixelPoint(x: 0, y: 0)] = 7
    let result = ToolOps.pen(on: buffer, at: PixelPoint(x: 1, y: 1), color: 4)
    #expect(result[PixelPoint(x: 1, y: 1)] == 4)
    #expect(result[PixelPoint(x: 0, y: 0)] == 7)
    #expect(result[PixelPoint(x: 2, y: 2)] == nil)
  }

  @Test("Eraser clears to nil")
  func eraserClears() {
    var buffer = PixelBuffer(size: PixelSize(width: 2, height: 1))
    buffer[PixelPoint(x: 0, y: 0)] = 9
    let result = ToolOps.erase(on: buffer, at: PixelPoint(x: 0, y: 0))
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
  }

  @Test("Flood fill recolors a 4-connected region but stops at boundaries")
  func floodFillStopsAtBoundary() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 3), fill: 0)
    // Vertical wall at x=2 splits the buffer into two regions.
    for y in 0..<3 {
      buffer[PixelPoint(x: 2, y: y)] = 1
    }
    let result = ToolOps.fill(
      on: buffer,
      at: PixelPoint(x: 0, y: 0),
      color: 5
    )
    // Left half recolored to 5.
    #expect(result[PixelPoint(x: 0, y: 0)] == 5)
    #expect(result[PixelPoint(x: 1, y: 2)] == 5)
    // Wall preserved.
    #expect(result[PixelPoint(x: 2, y: 0)] == 1)
    // Right half untouched.
    #expect(result[PixelPoint(x: 3, y: 0)] == 0)
  }

  @Test("Gradient interpolates between endpoints in palette space")
  func gradientPaintsInterpolatedColors() {
    let palette = ColorPalette(
      colors: [
        .transparent,
        EditorColor(rgbHex: 0xFF0000),  // red @ slot 1
        EditorColor(rgbHex: 0x000000),  // black @ slot 2
      ]
    )
    let buffer = PixelBuffer(size: PixelSize(width: 4, height: 1))
    let result = ToolOps.gradient(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 3, y: 0),
      startColor: EditorColor(rgbHex: 0xFF0000),
      endColor: EditorColor(rgbHex: 0x000000),
      palette: palette
    )
    // Endpoints land exactly on their respective palette slots; the
    // mid-row should bias toward whichever palette entry is closer to
    // the interpolated RGB.
    #expect(result[PixelPoint(x: 0, y: 0)] == 1)  // red
    #expect(result[PixelPoint(x: 3, y: 0)] == 2)  // black
  }

  @Test("Bresenham line connects two points without gaps")
  func lineConnectsDiagonal() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 0, y: 0),
      to: PixelPoint(x: 4, y: 4),
      color: 3
    )
    // Diagonal from (0,0) → (4,4) should land on the major diagonal.
    for i in 0...4 {
      #expect(result[PixelPoint(x: i, y: i)] == 3)
    }
  }

  @Test("Copy/paste round-trips a region's pixel values")
  func copyPasteRoundTrip() {
    var buffer = PixelBuffer(size: PixelSize(width: 4, height: 2))
    buffer[PixelPoint(x: 0, y: 0)] = 1
    buffer[PixelPoint(x: 1, y: 0)] = 2
    let clipboard = ToolOps.copy(
      from: buffer,
      rect: PixelRect(x: 0, y: 0, width: 2, height: 1)
    )!

    var blank = PixelBuffer(size: PixelSize(width: 4, height: 2))
    let pasted = ToolOps.paste(
      onto: blank,
      clipboard: clipboard,
      at: PixelPoint(x: 2, y: 1)
    )
    #expect(pasted[PixelPoint(x: 2, y: 1)] == 1)
    #expect(pasted[PixelPoint(x: 3, y: 1)] == 2)
    // Untouched cells stay nil.
    _ = blank
    #expect(pasted[PixelPoint(x: 0, y: 0)] == nil)
  }
}
