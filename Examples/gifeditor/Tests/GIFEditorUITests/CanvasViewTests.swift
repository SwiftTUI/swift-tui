import GIFEditorCore
import TerminalUI
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor Canvas view")
struct CanvasViewTests {
  @Test("CanvasView renders pixel colors and sparse overlays through Canvas")
  func canvasViewRendersPixelGridAndOverlay() {
    let red = EditorColor(rgbHex: 0xE05757)
    let blue = EditorColor(rgbHex: 0x5BA3FF)
    let size = GIFEditorCore.PixelSize(width: 2, height: 2)
    let raster = render(
      CanvasView(
        size: size,
        cells: [
          red, nil,
          blue, .white,
        ],
        cursor: GIFEditorCore.PixelPoint(x: 0, y: 0),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .fullCell
      ),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(raster.cells[1][1].character == "◆")
    #expect(raster.cells[1][1].style?.foregroundColor == Color.cyan)
    #expect(raster.cells[1][1].style?.backgroundColor == red.toTerminalColor())
    #expect(raster.cells[2][1].style?.backgroundColor == blue.toTerminalColor())
  }

  @Test("CanvasView can render the document grid in half-block mode")
  func canvasViewRendersHalfBlockMode() {
    let red = EditorColor(rgbHex: 0xE05757)
    let blue = EditorColor(rgbHex: 0x5BA3FF)
    let size = GIFEditorCore.PixelSize(width: 2, height: 3)
    let raster = render(
      CanvasView(
        size: size,
        cells: [
          red, .white,
          blue, .white,
          red, nil,
        ],
        cursor: GIFEditorCore.PixelPoint(x: 1, y: 2),
        selection: nil,
        pendingMarqueeAnchor: nil,
        pendingGradientAnchor: nil,
        mode: .verticalHalfBlock
      ),
      width: 8,
      height: 6
    ).rasterSurface

    #expect(raster.cells[1][1].character == "▀")
    #expect(raster.cells[1][1].style?.foregroundColor == red.toTerminalColor())
    #expect(raster.cells[1][1].style?.backgroundColor == blue.toTerminalColor())
    #expect(raster.cells[2][1].character == "▀")
    #expect(raster.cells[2][1].style?.foregroundColor == red.toTerminalColor())
    #expect(raster.cells[2][2].character == "▀")
    #expect(raster.cells[2][2].style?.foregroundColor == Color.cyan)
    #expect(raster.cells[2][2].style?.backgroundColor == nil)
  }

  @Test("Interactive canvas pointer drawing region excludes the border")
  func interactiveCanvasPointerDrawingRegionExcludesBorder() throws {
    let size = GIFEditorCore.PixelSize(width: 8, height: 6)
    let model = EditorViewModel(document: GIFDocument.blank(size: size))
    let artifacts = render(
      InteractiveCanvasView(
        size: size,
        cells: Array(repeating: Optional<EditorColor>.none, count: size.area),
        model: model,
        refresh: {},
        mode: .verticalHalfBlock
      ),
      width: 16,
      height: 8
    )

    let drawingRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first {
        $0.rect.size == CellSize(width: 8, height: 3)
      }
    )
    #expect(
      drawingRegion.rect
        == CellRect(
          origin: CellPoint(x: 1, y: 1),
          size: CellSize(width: 8, height: 3)
        )
    )
  }

  @Test("Canvas pixel mapping preserves sub-cell half-block rows")
  func canvasPixelMappingUsesSubCellPrecision() {
    let metrics = CellPixelMetrics(width: 10, height: 20, source: .reported)
    let precision = PointerPrecision.subCell(source: .terminalPixels, metrics: metrics)
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)

    #expect(
      canvasPixelPoint(
        forLocalCell: Point(x: 1.25, y: 0.20),
        precision: precision,
        mode: .verticalHalfBlock,
        size: size
      ) == GIFEditorCore.PixelPoint(x: 1, y: 0)
    )
    #expect(
      canvasPixelPoint(
        forLocalCell: Point(x: 1.25, y: 0.75),
        precision: precision,
        mode: .verticalHalfBlock,
        size: size
      ) == GIFEditorCore.PixelPoint(x: 1, y: 1)
    )
    #expect(
      canvasPixelPoint(
        forLocalCell: Point(x: 1.25, y: 1.25),
        precision: precision,
        mode: .verticalHalfBlock,
        size: size
      ) == GIFEditorCore.PixelPoint(x: 1, y: 2)
    )
  }

  @Test("Canvas pixel mapping anchors cell-only input to a stable half-cell")
  func canvasPixelMappingCellFallbackUsesCellOrigin() {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)

    #expect(
      canvasPixelPoint(
        forLocalCell: Point(x: 1.5, y: 0.5),
        precision: .cell,
        mode: .verticalHalfBlock,
        size: size
      ) == GIFEditorCore.PixelPoint(x: 1, y: 0)
    )
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
      identity: Identity(components: ["gifeditor.ui.tests.\(id)"]),
      environmentValues: env
    ),
    proposal: ProposedSize(width: width, height: height)
  )
}
