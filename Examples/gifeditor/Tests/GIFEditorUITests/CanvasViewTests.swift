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
        pendingGradientAnchor: nil
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
