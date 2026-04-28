import CanvasDemoViews
import TerminalUI
import Testing

@MainActor
@Suite("Canvas demo")
struct CanvasDemoViewTests {
  @Test("sketch document draw erase and clear mutate the backing dots")
  func sketchDocumentMutations() {
    var document = CanvasSketchDocument(
      cellSize: Size(width: 4, height: 2),
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
      cellSize: Size(width: 3, height: 2),
      cursor: CanvasSketchPoint(x: 2, y: 4)
    )

    document.moveCursor(dx: -100, dy: -100)
    #expect(document.cursor == CanvasSketchPoint(x: 0, y: 0))

    document.moveCursor(dx: 100, dy: 100)
    #expect(document.cursor == CanvasSketchPoint(x: 5, y: 7))
  }

  @Test("surface renders drawn pixels through Canvas with a cursor overlay")
  func surfaceRendersCanvasAndCursor() {
    var document = CanvasSketchDocument(
      cellSize: Size(width: 6, height: 3),
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

  @Test("pixel preview renders half-block Canvas pixels")
  func pixelPreviewRendersHalfBlocks() {
    let raster = render(
      CanvasDemoPixelPreview(mode: .verticalHalfBlock),
      width: 24,
      height: 8
    ).rasterSurface

    #expect(raster.lines.joined(separator: "\n").contains("half-block"))
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
          cellSize: Size(width: 4, height: 2),
          cursor: CanvasSketchPoint(x: 1, y: 2)
        ),
        pixelMode: .verticalHalfBlock
      ),
      width: 80,
      height: 18
    ).rasterSurface
    let lines = raster.lines.joined(separator: "\n")

    #expect(lines.contains("canvas-demo"))
    #expect(lines.contains("cursor 1,2"))
    #expect(lines.contains("pixel grid half-block"))
    #expect(lines.contains("Shift+Space draw"))
    #expect(lines.contains("Ctrl+M mode"))
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
  env.terminalSize = Size(width: width, height: height)
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
