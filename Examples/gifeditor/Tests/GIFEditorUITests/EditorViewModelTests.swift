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

  @Test("Select drag moves only the marquee pixels from the original layer snapshot")
  func selectDragMovesMarqueePixelsFromOriginalSnapshot() {
    var layer = PixelBuffer(size: GIFEditorCore.PixelSize(width: 6, height: 4))
    layer[GIFEditorCore.PixelPoint(x: 0, y: 0)] = 9
    layer[GIFEditorCore.PixelPoint(x: 1, y: 1)] = 1
    layer[GIFEditorCore.PixelPoint(x: 2, y: 1)] = 2
    layer[GIFEditorCore.PixelPoint(x: 4, y: 1)] = 8
    let frame = EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])
    let document = GIFDocument(size: layer.size, frames: [frame])
    let model = EditorViewModel(document: document)
    model.selection = Selection(rect: PixelRect(x: 1, y: 1, width: 2, height: 1))
    model.selectTool(.select)

    let start = GIFEditorCore.PixelPoint(x: 1, y: 1)
    let mid = GIFEditorCore.PixelPoint(x: 2, y: 1)
    let end = GIFEditorCore.PixelPoint(x: 3, y: 1)
    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: mid)
    model.updateCanvasDrag(startingAt: start, from: mid, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let moved = model.currentLayer.pixels
    #expect(moved[GIFEditorCore.PixelPoint(x: 0, y: 0)] == 9)
    #expect(moved[GIFEditorCore.PixelPoint(x: 1, y: 1)] == nil)
    #expect(moved[GIFEditorCore.PixelPoint(x: 2, y: 1)] == nil)
    #expect(moved[GIFEditorCore.PixelPoint(x: 3, y: 1)] == 1)
    #expect(moved[GIFEditorCore.PixelPoint(x: 4, y: 1)] == 2)
    #expect(model.selection?.rect == PixelRect(x: 3, y: 1, width: 2, height: 1))
    #expect(model.statusMessage == "Move selection Δ2,0")

    model.undo()

    #expect(model.currentLayer.pixels == layer)
    #expect(model.selection?.rect == PixelRect(x: 1, y: 1, width: 2, height: 1))
  }

  @Test("Select drag without a marquee moves the whole current layer")
  func selectDragWithoutMarqueeMovesWholeLayer() {
    var layer = PixelBuffer(size: GIFEditorCore.PixelSize(width: 4, height: 2))
    layer[GIFEditorCore.PixelPoint(x: 0, y: 0)] = 1
    layer[GIFEditorCore.PixelPoint(x: 3, y: 0)] = 2
    let frame = EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])
    let document = GIFDocument(size: layer.size, frames: [frame])
    let model = EditorViewModel(document: document)
    model.selectTool(.select)

    let start = GIFEditorCore.PixelPoint(x: 0, y: 0)
    let end = GIFEditorCore.PixelPoint(x: 1, y: 0)
    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let moved = model.currentLayer.pixels
    #expect(moved[GIFEditorCore.PixelPoint(x: 0, y: 0)] == nil)
    #expect(moved[GIFEditorCore.PixelPoint(x: 1, y: 0)] == 1)
    #expect(moved[GIFEditorCore.PixelPoint(x: 3, y: 0)] == nil)
    #expect(model.selection == nil)
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

  @Test("Brush size clamps to the supported range")
  func brushSizeClampsToSupportedRange() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 4, height: 4))
    )
    model.brushSize = 0
    #expect(model.brushSize == 1)

    model.brushSize = 12
    #expect(model.brushSize == 8)

    model.decreaseBrushSize()
    #expect(model.brushSize == 7)

    for _ in 0..<10 {
      model.decreaseBrushSize()
    }
    #expect(model.brushSize == 1)

    for _ in 0..<10 {
      model.increaseBrushSize()
    }
    #expect(model.brushSize == 8)
  }

  @Test("Thick pen click stamps a centered square")
  func thickPenClickStampsCenteredSquare() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 7, height: 7))
    )
    model.primaryColorIndex = 4
    model.brushSize = 3
    model.cursor = GIFEditorCore.PixelPoint(x: 3, y: 3)
    model.applyToolAtCursor()

    let pixels = model.currentLayer.pixels
    for y in 2...4 {
      for x in 2...4 {
        #expect(pixels[GIFEditorCore.PixelPoint(x: x, y: y)] == 4)
      }
    }
    #expect(pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] == nil)
  }

  @Test("Thick pen drag paints a thick connected stroke as one undo entry")
  func thickPenDragIsOneUndoEntry() {
    let model = EditorViewModel(
      document: GIFDocument.blank(size: GIFEditorCore.PixelSize(width: 9, height: 9))
    )
    model.primaryColorIndex = 6
    model.brushSize = 3
    let initial = model.currentLayer.pixels

    let start = GIFEditorCore.PixelPoint(x: 1, y: 4)
    let mid = GIFEditorCore.PixelPoint(x: 4, y: 4)
    let end = GIFEditorCore.PixelPoint(x: 7, y: 4)
    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: mid)
    model.updateCanvasDrag(startingAt: start, from: mid, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let painted = model.currentLayer.pixels
    // Stroke center y=4 with brush 3 covers y=3..5 across x=0..8 (each
    // step's stamp extends ±1 from the center, so the line from (1,4) to
    // (7,4) reaches x=0 and x=8 at the start and end stamps).
    for y in 3...5 {
      for x in 0...8 {
        #expect(painted[GIFEditorCore.PixelPoint(x: x, y: y)] == 6)
      }
    }
    // Outside the stamp band stays blank.
    #expect(painted[GIFEditorCore.PixelPoint(x: 4, y: 0)] == nil)
    #expect(painted[GIFEditorCore.PixelPoint(x: 4, y: 8)] == nil)
    #expect(painted[GIFEditorCore.PixelPoint(x: 4, y: 2)] == nil)

    // The whole drag is one history entry — single undo restores the
    // initial pre-stroke state.
    #expect(model.canUndo)
    #expect(!model.canRedo)
    model.undo()
    #expect(model.currentLayer.pixels == initial)
    #expect(!model.canUndo)
    #expect(model.canRedo)
  }

  @Test("Thick eraser drag clears the stamp band and is one undo entry")
  func thickEraserDragClearsBandAsSingleEntry() {
    var layer = PixelBuffer(size: GIFEditorCore.PixelSize(width: 9, height: 9), fill: 2)
    let frame = EditorFrame(layers: [EditorLayer(name: "Layer 1", pixels: layer)])
    let document = GIFDocument(size: layer.size, frames: [frame])
    let model = EditorViewModel(document: document)
    model.selectTool(.eraser)
    model.brushSize = 3
    layer = model.currentLayer.pixels  // initial fully-filled state

    let start = GIFEditorCore.PixelPoint(x: 1, y: 4)
    let end = GIFEditorCore.PixelPoint(x: 7, y: 4)
    model.beginCanvasDrag(at: start)
    model.updateCanvasDrag(startingAt: start, from: start, to: end)
    model.endCanvasDrag(startingAt: start, from: end, to: end)

    let pixels = model.currentLayer.pixels
    for y in 3...5 {
      for x in 1...7 {
        #expect(pixels[GIFEditorCore.PixelPoint(x: x, y: y)] == nil)
      }
    }
    #expect(pixels[GIFEditorCore.PixelPoint(x: 0, y: 0)] == 2)

    model.undo()
    #expect(model.currentLayer.pixels == layer)
  }

  @Test("Switching to a frame with fewer layers clamps the layer index")
  func selectFrameClampsLayerIndex() {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let multiLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "L1", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L2", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L3", pixels: PixelBuffer(size: size)),
    ])
    let singleLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "Only", pixels: PixelBuffer(size: size))
    ])
    let document = GIFDocument(size: size, frames: [multiLayerFrame, singleLayerFrame])
    let model = EditorViewModel(document: document)
    model.currentLayerIndex = 2

    model.selectFrame(at: 1)

    #expect(model.currentFrameIndex == 1)
    #expect(model.currentLayerIndex == 0)
    #expect(model.currentLayer.name == "Only")
  }

  @Test("Select drag after switching to a frame with fewer layers does not crash")
  func selectDragAfterFrameSwitchDoesNotCrash() {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let multiLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "L1", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L2", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L3", pixels: PixelBuffer(size: size)),
    ])
    let singleLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "Only", pixels: PixelBuffer(size: size))
    ])
    let document = GIFDocument(size: size, frames: [multiLayerFrame, singleLayerFrame])
    let model = EditorViewModel(document: document)
    model.currentLayerIndex = 2
    model.selectFrame(at: 1)
    model.selectTool(.select)

    // Reproduces the original crash: with a stale currentLayerIndex,
    // beginCanvasDrag → beginSelectMove read currentLayer, which subscripted
    // the new frame's single-layer array out of bounds.
    model.beginCanvasDrag(at: GIFEditorCore.PixelPoint(x: 0, y: 0))

    #expect(model.currentLayerIndex == 0)
  }

  @Test("Deleting a non-trailing frame clamps the layer index for the new current frame")
  func deleteFrameClampsLayerIndex() {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let multiLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "L1", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L2", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L3", pixels: PixelBuffer(size: size)),
    ])
    let singleLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "Only", pixels: PixelBuffer(size: size))
    ])
    let document = GIFDocument(size: size, frames: [multiLayerFrame, singleLayerFrame])
    let model = EditorViewModel(document: document)
    model.currentLayerIndex = 2
    // currentFrameIndex stays at 0 after the delete because there's still a
    // frame at that index — but it now points to the formerly-1-layer frame.
    model.deleteCurrentFrame()

    #expect(model.currentFrameIndex == 0)
    #expect(model.currentLayerIndex == 0)
    #expect(model.currentLayer.name == "Only")
  }

  @Test("Inserting a blank frame clamps the layer index for the new frame")
  func insertBlankFrameClampsLayerIndex() {
    let size = GIFEditorCore.PixelSize(width: 4, height: 4)
    let multiLayerFrame = EditorFrame(layers: [
      EditorLayer(name: "L1", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L2", pixels: PixelBuffer(size: size)),
      EditorLayer(name: "L3", pixels: PixelBuffer(size: size)),
    ])
    let document = GIFDocument(size: size, frames: [multiLayerFrame])
    let model = EditorViewModel(document: document)
    model.currentLayerIndex = 2

    model.insertBlankFrameAfterCurrent()

    #expect(model.currentFrameIndex == 1)
    #expect(model.currentLayerIndex == 0)
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
