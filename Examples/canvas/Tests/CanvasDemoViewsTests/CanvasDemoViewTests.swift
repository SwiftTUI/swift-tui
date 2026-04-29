import CanvasDemoViews
import TerminalUI
import Testing

@MainActor
@Suite("Canvas demo")
struct CanvasDemoViewTests {
  @Test("sketch document draw erase and clear mutate the backing dots")
  func sketchDocumentMutations() {
    var document = CanvasSketchDocument(
      cellSize: CellSize(width: 4, height: 2),
      cursor: CanvasSketchPoint(x: 2, y: 3)
    )

    #expect(document.litPixelCount == 0)
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 2, y: 3)))

    document.drawAtCursor()
    #expect(document.litPixelCount == 1)
    #expect(document.isPixelSet(CanvasSketchPoint(x: 2, y: 3)))

    document.eraseAtCursor()
    #expect(document.litPixelCount == 0)
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 2, y: 3)))

    document.setPixel(CanvasSketchPoint(x: 0, y: 0))
    document.setPixel(CanvasSketchPoint(x: 7, y: 7))
    #expect(document.litPixelCount == 2)

    document.clear()
    #expect(document.litPixelCount == 0)
  }

  @Test("cursor movement clamps to the drawable subpixel bounds")
  func cursorMovementClampsToBounds() {
    var document = CanvasSketchDocument(
      cellSize: CellSize(width: 3, height: 2),
      cursor: CanvasSketchPoint(x: 2, y: 4)
    )

    document.moveCursor(dx: -100, dy: -100)
    #expect(document.cursor == CanvasSketchPoint(x: 0, y: 0))

    document.moveCursor(dx: 100, dy: 100)
    #expect(document.cursor == CanvasSketchPoint(x: 5, y: 7))
    #expect(document.maxSubpixelX == 5)
    #expect(document.maxSubpixelY == 7)
  }

  @Test("pixel document draw erase and clear mutate logical pixels")
  func pixelDocumentMutations() {
    var document = CanvasPixelSketchDocument(
      size: CellSize(width: 4, height: 3),
      cursor: CanvasSketchPoint(x: 1, y: 1)
    )

    #expect(document.litPixelCount == 0)
    #expect(document.maxPixelX == 3)
    #expect(document.maxPixelY == 2)
    document.apply(.draw, at: document.cursor)
    #expect(document.isPixelSet(CanvasSketchPoint(x: 1, y: 1)))

    document.apply(.erase, at: CanvasSketchPoint(x: 1, y: 1))
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 1, y: 1)))

    document.apply(.draw, from: CanvasSketchPoint(x: 0, y: 0), to: CanvasSketchPoint(x: 3, y: 2))
    #expect(document.litPixelCount > 1)
    document.clear()
    #expect(document.litPixelCount == 0)
  }

  @Test("pointer cells map into the center of Braille subcells")
  func pointerCellsMapToSubpixels() {
    let point = CanvasSketchDocument.subpixelPoint(
      forLocalCell: Point(x: 2, y: 1),
      in: CellSize(width: 4, height: 3)
    )

    #expect(point == CanvasSketchPoint(x: 5, y: 6))
  }

  @Test("pointer cells map into full-cell and half-block pixels")
  func pointerCellsMapToPixelGridPoints() {
    let size = CellSize(width: 5, height: 6)

    #expect(
      CanvasPixelSketchDocument.pixelPoint(
        forLocalCell: Point(x: 2, y: 1),
        mode: .fullCell,
        in: size
      ) == CanvasSketchPoint(x: 2, y: 1)
    )
    #expect(
      CanvasPixelSketchDocument.pixelPoint(
        forLocalCell: Point(x: 2, y: 1),
        mode: .verticalHalfBlock,
        in: size
      ) == CanvasSketchPoint(x: 2, y: 2)
    )
  }

  @Test("drawing from pointer samples fills a subpixel line")
  func pointerLineDrawingFillsSubpixelLine() {
    var document = CanvasSketchDocument(cellSize: CellSize(width: 4, height: 3))

    document.apply(
      .draw,
      from: CanvasSketchPoint(x: 1, y: 2),
      to: CanvasSketchPoint(x: 5, y: 6)
    )

    #expect(document.isPixelSet(CanvasSketchPoint(x: 1, y: 2)))
    #expect(document.isPixelSet(CanvasSketchPoint(x: 3, y: 4)))
    #expect(document.isPixelSet(CanvasSketchPoint(x: 5, y: 6)))
    #expect(document.cursor == CanvasSketchPoint(x: 5, y: 6))

    document.apply(.erase, from: CanvasSketchPoint(x: 1, y: 2), to: CanvasSketchPoint(x: 5, y: 6))
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 1, y: 2)))
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 3, y: 4)))
    #expect(!document.isPixelSet(CanvasSketchPoint(x: 5, y: 6)))
  }

  @Test("pixel surfaces render editable full-cell and half-block drawings")
  func pixelSurfacesRenderEditableDrawings() {
    var fullCell = CanvasPixelSketchDocument(
      size: CellSize(width: 4, height: 3),
      cursor: CanvasSketchPoint(x: 2, y: 1)
    )
    fullCell.setPixel(CanvasSketchPoint(x: 1, y: 1))
    let fullCellRaster = render(
      CanvasDemoPixelSurface(document: fullCell, mode: .fullCell),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(
      fullCellRaster.cells.contains { row in
        row.contains { cell in
          cell.style?.backgroundColor == Color.cyan
        }
      }
    )
    #expect(
      fullCellRaster.cells.contains { row in
        row.contains { cell in
          cell.style?.foregroundColor == Color.yellow
        }
      }
    )

    var halfBlock = CanvasPixelSketchDocument(
      size: CellSize(width: 4, height: 6),
      cursor: CanvasSketchPoint(x: 2, y: 3)
    )
    halfBlock.setPixel(CanvasSketchPoint(x: 1, y: 0))
    let halfBlockRaster = render(
      CanvasDemoPixelSurface(document: halfBlock, mode: .verticalHalfBlock),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(
      halfBlockRaster.cells.contains { row in
        row.contains { cell in
          (cell.character == "▀" || cell.character == "▄")
            && cell.style?.foregroundColor == Color.cyan
        }
      }
    )
  }

  @Test("surface renders drawn pixels through Canvas with a cursor overlay")
  func surfaceRendersCanvasAndCursor() {
    var document = CanvasSketchDocument(
      cellSize: CellSize(width: 6, height: 3),
      cursor: CanvasSketchPoint(x: 10, y: 10)
    )
    document.setPixel(CanvasSketchPoint(x: 0, y: 0))
    document.setPixel(CanvasSketchPoint(x: 1, y: 0))
    document.setPixel(CanvasSketchPoint(x: 2, y: 0))

    let raster = render(
      CanvasDemoSurface(document: document),
      width: 12,
      height: 8
    ).rasterSurface

    #expect(
      raster.cells.contains { row in
        row.contains { cell in
          cell.style?.foregroundColor == Color.cyan
            && isBrailleGlyph(cell.character)
        }
      }
    )
    #expect(
      raster.cells.contains { row in
        row.contains { cell in
          cell.style?.foregroundColor == Color.yellow
            && isBrailleGlyph(cell.character)
        }
      }
    )
  }

  @Test("surface exposes a focusable pointer drawing region")
  func surfaceExposesFocusablePointerRegion() {
    let artifacts = render(
      CanvasDemoSurface(
        document: CanvasSketchDocument(
          cellSize: CellSize(width: 6, height: 3)
        )
      ),
      width: 12,
      height: 8
    )

    #expect(!artifacts.semanticSnapshot.focusRegions.isEmpty)
    #expect(!artifacts.semanticSnapshot.interactionRegions.isEmpty)
  }

  @Test("pixel surface renders half-block Canvas pixels")
  func pixelSurfaceRendersHalfBlocks() {
    var document = CanvasPixelSketchDocument(
      size: CellSize(width: 8, height: 6),
      cursor: CanvasSketchPoint(x: 3, y: 2)
    )
    document.setPixel(CanvasSketchPoint(x: 1, y: 0))

    let raster = render(
      CanvasDemoPixelSurface(document: document, mode: .verticalHalfBlock),
      width: 32,
      height: 10
    ).rasterSurface

    #expect(
      raster.cells.contains { row in
        row.contains { cell in
          (cell.character == "▀" || cell.character == "▄")
            && (cell.style?.foregroundColor != nil || cell.style?.backgroundColor != nil)
        }
      }
    )
  }

  @Test("root view exposes status and key help")
  func rootViewRendersStatusChrome() {
    let raster = render(
      CanvasDemoView(
        document: CanvasSketchDocument(
          cellSize: CellSize(width: 4, height: 2),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        halfBlockDocument: CanvasPixelSketchDocument(
          size: CellSize(width: 8, height: 6),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        selectedCanvas: .halfBlock
      ),
      width: 80,
      height: 20
    ).rasterSurface
    let lines = raster.lines.joined(separator: "\n")

    #expect(lines.contains("canvas-demo"))
    #expect(lines.contains("Subcell"))
    #expect(lines.contains("Full Cell"))
    #expect(lines.contains("Half Block"))
    #expect(lines.contains("half-block pixel grid max 7,5"))
    #expect(lines.contains("cursor 1,2 of max 7,5 pixels"))
    #expect(lines.contains("space paint"))
    #expect(lines.contains("drag paints"))
  }

  @Test("root view reports max indices for each canvas type")
  func rootViewReportsMaxIndices() {
    let subcellLines = render(
      CanvasDemoView(
        document: CanvasSketchDocument(
          cellSize: CellSize(width: 4, height: 2),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        selectedCanvas: .subcell
      ),
      width: 80,
      height: 20
    ).rasterSurface.lines.joined(separator: "\n")
    #expect(subcellLines.contains("Braille subpixels max 7,7"))
    #expect(subcellLines.contains("cursor 1,2 of max 7,7 Braille subpixels"))

    let fullCellLines = render(
      CanvasDemoView(
        fullCellDocument: CanvasPixelSketchDocument(
          size: CellSize(width: 8, height: 6),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        selectedCanvas: .fullCell
      ),
      width: 80,
      height: 20
    ).rasterSurface.lines.joined(separator: "\n")
    #expect(fullCellLines.contains("full-cell pixel grid max 7,5"))
    #expect(fullCellLines.contains("cursor 1,2 of max 7,5 pixels"))

    let halfBlockLines = render(
      CanvasDemoView(
        halfBlockDocument: CanvasPixelSketchDocument(
          size: CellSize(width: 8, height: 6),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        selectedCanvas: .halfBlock
      ),
      width: 80,
      height: 20
    ).rasterSurface.lines.joined(separator: "\n")
    #expect(halfBlockLines.contains("half-block pixel grid max 7,5"))
    #expect(halfBlockLines.contains("cursor 1,2 of max 7,5 pixels"))
  }
}

@MainActor
private func render(
  _ view: some View,
  width: Int,
  height: Int,
  id: String = "\(#fileID).\(#function)"
) -> FrameArtifacts {
  var env = EnvironmentValues()
  env.terminalSize = CellSize(width: width, height: height)
  return DefaultRenderer().render(
    view,
    context: ResolveContext(
      identity: Identity(components: ["canvas-demo.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}

private func isBrailleGlyph(_ character: Character) -> Bool {
  guard let scalar = character.unicodeScalars.first?.value else {
    return false
  }
  return scalar >= 0x2800 && scalar <= 0x28FF
}
