import Foundation
import GIFEditorCore
import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor view model pointer canvas editing")
struct EditorViewModelTests {
  @Test("Pen drag paints a connected line on the current layer")
  func penDragPaintsConnectedLine() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 5, height: 5))
    )
    model.primaryColorIndex = 3
    let start = GIFEditorCore.PixelPoint(x: 0, y: 0)
    let end = GIFEditorCore.PixelPoint(x: 4, y: 4)

    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let pixels = model.currentLayer.pixels
    for offset in 0...4 {
      #expect(pixels[GIFEditorCore.PixelPoint(x: offset, y: offset)] == 3)
    }
    #expect(model.cursor == end)
    #expect(model.isDirty)
  }

  @Test("Pen drag undo and redo treats a stroke as one history entry")
  func penDragUndoRedoIsOneHistoryEntry() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 5, height: 5))
    )
    model.primaryColorIndex = 3
    let initial = model.currentLayer.pixels
    let start = GIFEditorCore.PixelPoint(x: 0, y: 0)
    let mid = GIFEditorCore.PixelPoint(x: 2, y: 2)
    let end = GIFEditorCore.PixelPoint(x: 4, y: 4)

    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: mid)
    model.updateCanvasDrag(startingAt: start, from: mid, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let painted = model.currentLayer.pixels
    #expect(model.canUndo)
    #expect(!model.canRedo)
    #expect(model.isDirty)

    model.undo()

    #expect(model.currentLayer.pixels == initial)
    #expect(!model.canUndo)
    #expect(model.canRedo)
    #expect(!model.isDirty)

    model.redo()

    #expect(model.currentLayer.pixels == painted)
    #expect(model.canUndo)
    #expect(!model.canRedo)
    #expect(model.isDirty)
  }

  @Test("Eraser drag clears along the connected line")
  func eraserDragClearsConnectedLine() {
    var layer = PixelBuffer(size: GIFEditorCore.PixelSize(width: 5, height: 5), fill: 4)
    layer[GIFEditorCore.PixelPoint(x: 4, y: 0)] = nil
    let frame = EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])
    let document = GIFDocument(size: layer.size, frames: [frame])
    let model = EditorViewModel(document: document)
    model.selectTool(.eraser)
    let start = GIFEditorCore.PixelPoint(x: 0, y: 0)
    let end = GIFEditorCore.PixelPoint(x: 4, y: 4)

    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let pixels = model.currentLayer.pixels
    for offset in 0...4 {
      #expect(pixels[GIFEditorCore.PixelPoint(x: offset, y: offset)] == nil)
    }
    #expect(pixels[GIFEditorCore.PixelPoint(x: 4, y: 0)] == nil)
  }

  @Test("Marquee drag previews and commits the selected rectangle")
  func marqueeDragCommitsSelection() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 6, height: 6))
    )
    model.selectTool(.marquee)
    let start = GIFEditorCore.PixelPoint(x: 1, y: 1)
    let end = GIFEditorCore.PixelPoint(x: 4, y: 3)

    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    #expect(model.pendingMarqueeAnchor == start)
    #expect(model.selection?.rect == PixelRect.bounding(start, end))

    model.endCanvasDrag(startingAt: start, from: end, to: end)

    #expect(model.pendingMarqueeAnchor == nil)
    #expect(model.selection?.rect == PixelRect.bounding(start, end))
    #expect(model.cursor == end)
  }

  @Test("New document edit after undo clears redo")
  func newEditAfterUndoClearsRedo() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 3, height: 3))
    )
    model.primaryColorIndex = 4
    model.cursor = GIFEditorCore.PixelPoint(x: 0, y: 0)
    model.applyToolAtCursor()

    model.undo()
    #expect(model.canRedo)

    model.cursor = GIFEditorCore.PixelPoint(x: 1, y: 0)
    model.primaryColorIndex = 5
    model.applyToolAtCursor()

    #expect(!model.canRedo)
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] == nil)
    #expect(model.currentLayer.pixels[GIFEditorCore.PixelPoint(x: 1, y: 0)] == 5)
  }

  @Test("Undo after save marks the restored older state dirty")
  func undoAfterSaveMarksOlderStateDirty() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("gifeditor-history-\(UUID().uuidString).gif")
    defer {
      try? FileManager.default.removeItem(at: url)
    }

    var document = GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 2, height: 2))
    document.path = url
    let model = EditorViewModel(document: document)
    model.primaryColorIndex = 6
    model.applyToolAtCursor()
    #expect(model.isDirty)

    model.save()
    #expect(!model.isDirty)

    model.undo()
    #expect(model.isDirty)

    model.redo()
    #expect(!model.isDirty)
  }
}
