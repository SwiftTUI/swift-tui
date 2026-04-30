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

  @Test("Line with thickness 3 paints a centered 3×3 stamp at every step")
  func lineWithThickness3StampsAcrossDiagonal() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 7))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 3, y: 3),
      to: PixelPoint(x: 3, y: 3),
      color: 5,
      thickness: 3
    )
    // 3×3 stamp centered on (3,3) covers (2..4, 2..4).
    for y in 2...4 {
      for x in 2...4 {
        #expect(result[PixelPoint(x: x, y: y)] == 5)
      }
    }
    // Corners outside the stamp must remain blank.
    #expect(result[PixelPoint(x: 0, y: 0)] == nil)
    #expect(result[PixelPoint(x: 5, y: 3)] == nil)
  }

  @Test("Even thickness 2 stamp biases one cell down/right of the center")
  func lineWithThickness2BiasesDownAndRight() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 2, y: 2),
      to: PixelPoint(x: 2, y: 2),
      color: 4,
      thickness: 2
    )
    // 2×2 stamp at (2,2) covers (2,2),(3,2),(2,3),(3,3) — biased +x/+y.
    #expect(result[PixelPoint(x: 2, y: 2)] == 4)
    #expect(result[PixelPoint(x: 3, y: 2)] == 4)
    #expect(result[PixelPoint(x: 2, y: 3)] == 4)
    #expect(result[PixelPoint(x: 3, y: 3)] == 4)
    #expect(result[PixelPoint(x: 1, y: 2)] == nil)
    #expect(result[PixelPoint(x: 2, y: 1)] == nil)
  }

  @Test("Thick eraser strokes (color: nil) clear every cell under the brush")
  func thickEraserStrokeClearsUnderBrush() {
    let buffer = PixelBuffer(size: PixelSize(width: 7, height: 7), fill: 8)
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 1, y: 3),
      to: PixelPoint(x: 5, y: 3),
      color: nil,
      thickness: 3
    )
    // The 3-wide horizontal stroke at y=3 erases rows y=2..4 across x=1..5
    // (each step's 3×3 stamp covers ±1 around the center).
    for y in 2...4 {
      for x in 0...5 {
        #expect(result[PixelPoint(x: x, y: y)] == nil)
      }
    }
    // Cells outside the stamp band stay filled.
    #expect(result[PixelPoint(x: 0, y: 0)] == 8)
    #expect(result[PixelPoint(x: 0, y: 6)] == 8)
  }

  @Test("Thick line clipped to selection does not paint outside the rect")
  func thickLineRespectsSelection() {
    let buffer = PixelBuffer(size: PixelSize(width: 8, height: 8))
    let selection = Selection(rect: PixelRect(x: 2, y: 2, width: 4, height: 4))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 4, y: 4),
      to: PixelPoint(x: 4, y: 4),
      color: 7,
      thickness: 5,
      selection: selection
    )
    // The 5×5 stamp centered on (4,4) would cover (2..6, 2..6); clipping
    // to the 4×4 selection at (2,2) trims the right and bottom cells.
    for y in 2..<6 {
      for x in 2..<6 {
        #expect(result[PixelPoint(x: x, y: y)] == 7)
      }
    }
    // Outside the selection — must remain blank even though the brush
    // intersected those cells.
    #expect(result[PixelPoint(x: 6, y: 4)] == nil)
    #expect(result[PixelPoint(x: 4, y: 6)] == nil)
    #expect(result[PixelPoint(x: 1, y: 4)] == nil)
  }

  @Test("Default thickness 1 keeps single-pixel behavior")
  func defaultThicknessIsOnePixel() {
    let buffer = PixelBuffer(size: PixelSize(width: 5, height: 5))
    let result = ToolOps.line(
      on: buffer,
      from: PixelPoint(x: 2, y: 2),
      to: PixelPoint(x: 2, y: 2),
      color: 1
    )
    #expect(result[PixelPoint(x: 2, y: 2)] == 1)
    // No stamping into neighbors.
    #expect(result[PixelPoint(x: 1, y: 2)] == nil)
    #expect(result[PixelPoint(x: 3, y: 2)] == nil)
    #expect(result[PixelPoint(x: 2, y: 1)] == nil)
    #expect(result[PixelPoint(x: 2, y: 3)] == nil)
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

    let blank = PixelBuffer(size: PixelSize(width: 4, height: 2))
    let pasted = ToolOps.paste(
      onto: blank,
      clipboard: clipboard,
      at: PixelPoint(x: 2, y: 1)
    )
    #expect(pasted[PixelPoint(x: 2, y: 1)] == 1)
    #expect(pasted[PixelPoint(x: 3, y: 1)] == 2)
    // Untouched cells stay nil.
    #expect(pasted[PixelPoint(x: 0, y: 0)] == nil)
  }
}
