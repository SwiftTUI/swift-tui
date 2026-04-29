import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private struct DiagonalLine: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    let end = Point(
      x: max(0, Double(context.size.width) - 0.25),
      y: max(0, Double(context.size.height) - 0.125)
    )
    context.line(
      from: .zero,
      to: end
    )
  }
}

private struct FilledCircle: CanvasDrawing, Equatable {
  let radius: Double

  func draw(into context: inout CanvasContext) {
    context.fillCircle(
      center: Point(
        x: Double(context.size.width) / 2,
        y: Double(context.size.height) / 2
      ),
      radius: radius
    )
  }
}

private struct NoOpDrawing: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {}
}

private struct CornerPixel: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setPixel(
      at: Point(
        x: max(0, Double(context.size.width) - 0.25),
        y: max(0, Double(context.size.height) - 0.125)
      )
    )
  }
}

private struct UniformStyledPixel: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.foreground = .red
    context.background = .blue
    context.setPixel(at: .zero)
  }
}

private struct DirectCellGrid: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.fillCell(x: 0, y: 0, color: .red)
    context.fillCell(x: 1, y: 0, color: .blue)
    context.setCell(x: 0, y: 1, character: "x", foreground: .green)
    context.fillCell(x: 99, y: 99, color: .white)
  }
}

private struct BrailleCellsWithStyles: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setPixel(at: .zero, foreground: .red)
    context.setPixel(at: Point(x: 1, y: 0), foreground: .blue)
  }
}

private struct BrailleSameCellStyleConflict: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setPixel(at: .zero, foreground: .red)
    context.setPixel(at: Point(x: 0.5, y: 0), foreground: .blue)
  }
}

private struct DirectCellsUnderBraille: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.fillCell(x: 0, y: 0, color: .blue)
    context.setPixel(at: .zero, foreground: .red)
  }
}

private struct QuadrantCellSpaceMarks: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    context.setPixel(at: Point(x: 0.25, y: 0.25))
    context.setPixel(at: Point(x: 0.75, y: 0.75))
  }
}

private struct VerticalHalfCellSpaceMark: CanvasDrawing, Equatable {
  enum Half: Equatable, Sendable {
    case top
    case bottom
  }

  var half: Half

  func draw(into context: inout CanvasContext) {
    switch half {
    case .top:
      context.setPixel(at: Point(x: 0.5, y: 0.25))
    case .bottom:
      context.setPixel(at: Point(x: 0.5, y: 0.75))
    }
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
      Canvas(FilledCircle(radius: 2)).frame(width: 10, height: 5),
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

  @Test("Canvas keeps the uniform foreground/background fallback for unstyled Braille")
  func canvasUniformStyleFallback() {
    let artifacts = DefaultRenderer().render(
      Canvas(UniformStyledPixel()).frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasUniformStyle"))
    )
    let cell = artifacts.rasterSurface.cells[0][0]
    #expect(cell.style?.foregroundColor == Color.red)
    #expect(cell.style?.backgroundColor == Color.blue)
  }

  @Test("CanvasContext can write direct terminal cells with independent styles")
  func canvasDirectCellGrid() {
    let artifacts = DefaultRenderer().render(
      Canvas(DirectCellGrid()).frame(width: 2, height: 2),
      context: .init(identity: testIdentity("CanvasDirectCells"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].character == " ")
    #expect(cells[0][0].style?.backgroundColor == Color.red)
    #expect(cells[0][1].style?.backgroundColor == Color.blue)
    #expect(cells[1][0].character == "x")
    #expect(cells[1][0].style?.foregroundColor == Color.green)
    #expect(cells[1][1] == RasterCell.empty)
  }

  @Test("Styled Braille writes can color separate terminal cells")
  func canvasStyledBrailleCells() {
    let artifacts = DefaultRenderer().render(
      Canvas(BrailleCellsWithStyles()).frame(width: 2, height: 1),
      context: .init(identity: testIdentity("CanvasStyledBraille"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].style?.foregroundColor == Color.red)
    #expect(cells[0][1].style?.foregroundColor == Color.blue)
  }

  @Test("Styled Braille uses last-writer-wins inside one terminal cell")
  func canvasStyledBrailleSameCellConflict() {
    let artifacts = DefaultRenderer().render(
      Canvas(BrailleSameCellStyleConflict()).frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasStyledBrailleConflict"))
    )
    let cell = artifacts.rasterSurface.cells[0][0]
    #expect(cell.style?.foregroundColor == Color.blue)
    let scalar = cell.character.unicodeScalars.first?.value ?? 0
    #expect((scalar - 0x2800) & 0x01 != 0)
    #expect((scalar - 0x2800) & 0x08 != 0)
  }

  @Test("Braille output composes over direct cell backgrounds")
  func canvasDirectCellsUnderBraille() {
    let artifacts = DefaultRenderer().render(
      Canvas(DirectCellsUnderBraille()).frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasLayerComposition"))
    )
    let cell = artifacts.rasterSurface.cells[0][0]
    #expect(cell.style?.foregroundColor == Color.red)
    #expect(cell.style?.backgroundColor == Color.blue)
  }

  @Test("Canvas grid maps fractional cell coordinates into quadrant blocks")
  func canvasQuadrantGridCellSpaceDrawing() {
    let artifacts = DefaultRenderer().render(
      Canvas(grid: .quadrant2x2, QuadrantCellSpaceMarks()).frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasQuadrantGrid"))
    )

    #expect(artifacts.rasterSurface.cells[0][0].character == "▚")
  }

  @Test("Canvas grid maps fractional cell coordinates into vertical half blocks")
  func canvasVerticalHalfBlockCellSpaceDrawing() {
    let top = DefaultRenderer().render(
      Canvas(grid: .verticalHalfBlock, VerticalHalfCellSpaceMark(half: .top))
        .frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasVerticalHalfTop"))
    )
    let bottom = DefaultRenderer().render(
      Canvas(grid: .verticalHalfBlock, VerticalHalfCellSpaceMark(half: .bottom))
        .frame(width: 1, height: 1),
      context: .init(identity: testIdentity("CanvasVerticalHalfBottom"))
    )

    #expect(top.rasterSurface.cells[0][0].character == "▀")
    #expect(bottom.rasterSurface.cells[0][0].character == "▄")
  }

  @Test("Full-cell pixel grids render one logical pixel per terminal cell")
  func canvasFullCellPixelGrid() {
    let pixels: [Color?] = [
      .red, nil,
      .blue, .green,
    ]
    let artifacts = DefaultRenderer().render(
      Canvas(pixelGridWidth: 2, height: 2, pixels: pixels, mode: .fullCell)
        .frame(width: 2, height: 2),
      context: .init(identity: testIdentity("CanvasFullCellPixelGrid"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].style?.backgroundColor == Color.red)
    #expect(cells[0][1] == RasterCell.empty)
    #expect(cells[1][0].style?.backgroundColor == Color.blue)
    #expect(cells[1][1].style?.backgroundColor == Color.green)
  }

  @Test("Vertical half-block pixel grids pack two logical rows into one terminal row")
  func canvasVerticalHalfBlockPixelGrid() {
    let pixels: [Color?] = [
      .red, .green,
      .blue, .green,
      .white, nil,
    ]
    let mode = CanvasPixelGridMode.verticalHalfBlock
    let artifacts = DefaultRenderer().render(
      Canvas(pixelGridWidth: 2, height: 3, pixels: pixels, mode: mode)
        .frame(width: 2, height: mode.cellHeight(for: 3)),
      context: .init(identity: testIdentity("CanvasHalfBlockPixelGrid"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells.count == 2)
    #expect(cells[0][0].character == "▀")
    #expect(cells[0][0].style?.foregroundColor == Color.red)
    #expect(cells[0][0].style?.backgroundColor == Color.blue)
    #expect(cells[0][1].character == " ")
    #expect(cells[0][1].style?.backgroundColor == Color.green)
    #expect(cells[1][0].character == "▀")
    #expect(cells[1][0].style?.foregroundColor == Color.white)
    #expect(cells[1][0].style?.backgroundColor == nil)
    #expect(cells[1][1] == RasterCell.empty)
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
    let d = CanvasPayload(drawing: FilledCircle(radius: 1.25))
    let e = CanvasPayload(drawing: FilledCircle(radius: 2))
    let f = CanvasPayload(drawing: DiagonalLine(), grid: .quadrant2x2)
    #expect(a == b)
    #expect(a != c)
    #expect(d != e)
    #expect(a != f)
  }
}
