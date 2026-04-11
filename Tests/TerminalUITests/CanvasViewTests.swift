import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private struct DiagonalLine: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.line(
      from: (x: 0, y: 0),
      to: (x: context.width - 1, y: context.height - 1)
    )
  }
}

private struct FilledCircle: CanvasDrawing, Equatable {
  let radius: Int

  func draw(into context: inout CanvasContext) {
    context.fillCircle(
      centerX: context.width / 2,
      centerY: context.height / 2,
      radius: radius
    )
  }
}

private struct NoOpDrawing: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {}
}

private struct CornerPixel: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setPixel(x: context.width - 1, y: context.height - 1)
  }
}

@MainActor
@Suite("Canvas view + CanvasDrawing protocol")
struct CanvasViewTests {

  @Test("Canvas renders a user-provided diagonal line")
  func canvasDiagonalLine() {
    let artifacts = DefaultRenderer().render(
      Canvas(DiagonalLine()).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CanvasDiagonal"))
    )
    // Top-left and bottom-right cells should contain Braille glyphs.
    // The line from (0,0) to (19,19) in subpixels lights up dots
    // along the main diagonal of the frame.
    let topLeft = artifacts.rasterSurface.cells[0][0]
    let bottomRight = artifacts.rasterSurface.cells[4][9]
    let tlScalar = topLeft.character.unicodeScalars.first?.value ?? 0
    let brScalar = bottomRight.character.unicodeScalars.first?.value ?? 0
    #expect(tlScalar >= 0x2800 && tlScalar <= 0x28FF)
    #expect(brScalar >= 0x2800 && brScalar <= 0x28FF)
    // Top-left dot (x=0,y=0 → bit 0x01) must be set in the (0,0) cell.
    #expect((tlScalar - 0x2800) & 0x01 != 0)
    // Bottom-right dot (x=1,y=3 → bit 0x80) must be set in (9,4).
    #expect((brScalar - 0x2800) & 0x80 != 0)
  }

  @Test("Canvas renders a filled circle in its frame")
  func canvasFilledCircle() {
    let artifacts = DefaultRenderer().render(
      Canvas(FilledCircle(radius: 8)).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CanvasCircle"))
    )
    // The center cell should be fully lit (⣿ = U+28FF).
    let center = artifacts.rasterSurface.cells[2][5]
    #expect(center.character == "\u{28FF}")
  }

  @Test("Canvas with a no-op drawing renders blank cells")
  func canvasNoOp() {
    let artifacts = DefaultRenderer().render(
      Canvas(NoOpDrawing()).frame(width: 5, height: 3),
      context: .init(identity: testIdentity("CanvasNoOp"))
    )
    // Every cell should be empty (space) or the blank Braille glyph
    // (U+2800).  The drawing doesn't light any dots, so the rasterizer
    // should not emit any non-blank glyphs.
    for row in artifacts.rasterSurface.cells {
      for cell in row {
        let scalar = cell.character.unicodeScalars.first?.value ?? 0
        #expect(scalar == 0x20 || scalar == 0x2800)
      }
    }
  }

  @Test("CanvasContext reports subpixel dimensions (2·cellW × 4·cellH)")
  func canvasContextDimensions() {
    // A 3x1 cell frame has a subpixel range of 6x4.  Lighting
    // (subW-1, subH-1) = (5, 3) should land in cell (2, 0), dot
    // (x=1, y=3), which sets bit 0x80 on that glyph.
    let artifacts = DefaultRenderer().render(
      Canvas(CornerPixel()).frame(width: 3, height: 1),
      context: .init(identity: testIdentity("CanvasDims"))
    )
    let cell = artifacts.rasterSurface.cells[0][2]
    let scalar = cell.character.unicodeScalars.first?.value ?? 0
    #expect(scalar >= 0x2800 && scalar <= 0x28FF)
    #expect((scalar - 0x2800) & 0x80 != 0)
  }

  @Test("Canvas Equatable identity dedups structurally equal drawings")
  func canvasEqualityDedup() {
    let artA = DefaultRenderer().render(
      Canvas(DiagonalLine()).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CanvasEqualA"))
    )
    let artB = DefaultRenderer().render(
      Canvas(DiagonalLine()).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CanvasEqualB"))
    )
    // Two canvases rendering the same drawing at the same size should
    // produce identical raster cells.
    for y in 0..<5 {
      for x in 0..<10 {
        #expect(
          artA.rasterSurface.cells[y][x].character
            == artB.rasterSurface.cells[y][x].character
        )
      }
    }
  }

  @Test("CanvasPayload equality distinguishes different drawings")
  func canvasPayloadEquality() {
    let a = CanvasPayload(drawing: DiagonalLine())
    let b = CanvasPayload(drawing: DiagonalLine())
    let c = CanvasPayload(drawing: NoOpDrawing())
    let d = CanvasPayload(drawing: FilledCircle(radius: 5))
    let e = CanvasPayload(drawing: FilledCircle(radius: 8))
    #expect(a == b)
    #expect(a != c)
    #expect(d != e)
  }
}
