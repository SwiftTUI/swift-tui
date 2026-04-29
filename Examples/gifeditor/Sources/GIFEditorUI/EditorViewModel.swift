import Foundation
import GIFEditorCore
import TerminalUI

/// Reference-type owner of the editor's mutable state. The view tree
/// reads `document` as a value type via @State, but mutating ops live
/// here so individual views don't need to thread the document around.
///
/// Kept @MainActor — the editor is single-window, single-threaded, and
/// every mutation is driven from a UI event.
@MainActor
public final class EditorViewModel {
  // MARK: - Document

  public private(set) var document: GIFDocument

  public var canUndo: Bool {
    !undoStack.isEmpty
  }

  public var canRedo: Bool {
    !redoStack.isEmpty
  }

  public var isDirty: Bool {
    currentHistoryGeneration != cleanHistoryGeneration
  }

  private struct EditorSnapshot: Equatable {
    var document: GIFDocument
    var currentFrameIndex: Int
    var currentLayerIndex: Int
    var cursor: GIFEditorCore.PixelPoint
    var selection: Selection?
    var historyGeneration: Int
  }

  private struct HistoryEntry {
    var snapshot: EditorSnapshot
    var label: String
  }

  private struct ActiveUndoGroup {
    var snapshot: EditorSnapshot
    var label: String
  }

  private var undoStack: [HistoryEntry] = []
  private var redoStack: [HistoryEntry] = []
  private var activeUndoGroup: ActiveUndoGroup?
  private var currentHistoryGeneration: Int = 0
  private var cleanHistoryGeneration: Int = 0
  private var nextHistoryGeneration: Int = 1
  private let historyLimit: Int = 100

  // MARK: - Selection state

  public var currentFrameIndex: Int = 0 {
    didSet {
      currentFrameIndex = currentFrameIndex.clamped(to: 0...max(0, document.frames.count - 1))
    }
  }

  public var currentLayerIndex: Int = 0 {
    didSet {
      currentLayerIndex = currentLayerIndex.clamped(
        to: 0...max(0, document.frames[currentFrameIndex].layers.count - 1)
      )
    }
  }

  // MARK: - Tool state

  public var tool: EditorTool = .pen
  public var primaryColorIndex: PaletteIndex = 1
  public var secondaryColorIndex: PaletteIndex = 2
  public var cursor: GIFEditorCore.PixelPoint = .zero {
    didSet {
      cursor.x = cursor.x.clamped(to: 0...max(0, document.size.width - 1))
      cursor.y = cursor.y.clamped(to: 0...max(0, document.size.height - 1))
    }
  }
  public var selection: Selection? = nil
  public var clipboard: PixelBuffer? = nil

  // MARK: - Pending interactions

  /// Marquee tool's first corner, captured on `Space` or `Enter` and
  /// committed into a `selection` by pressing either key again.
  public var pendingMarqueeAnchor: GIFEditorCore.PixelPoint? = nil
  /// Gradient tool's first endpoint.
  public var pendingGradientAnchor: GIFEditorCore.PixelPoint? = nil

  // MARK: - Status / feedback

  public var statusMessage: String = ""

  public init(document: GIFDocument) {
    self.document = document
  }

  // MARK: - History

  public func undo() {
    guard let entry = undoStack.popLast() else {
      announce("Nothing to undo")
      return
    }

    activeUndoGroup = nil
    redoStack.append(HistoryEntry(snapshot: snapshotState(), label: entry.label))
    restore(entry.snapshot)
    announce("Undid \(entry.label)")
  }

  public func redo() {
    guard let entry = redoStack.popLast() else {
      announce("Nothing to redo")
      return
    }

    activeUndoGroup = nil
    undoStack.append(HistoryEntry(snapshot: snapshotState(), label: entry.label))
    restore(entry.snapshot)
    announce("Redid \(entry.label)")
  }

  // MARK: - Frame & layer accessors

  public var currentFrame: EditorFrame {
    document.frames[currentFrameIndex]
  }

  public var currentLayer: EditorLayer {
    currentFrame.layers[currentLayerIndex]
  }

  // MARK: - Tool dispatch

  /// Applies the active tool at the cursor. Pen-style tools paint
  /// directly; multi-stage tools (marquee, gradient) advance through
  /// their internal state machines.
  public func applyToolAtCursor() {
    switch tool {
    case .pen:
      recordUndoableEdit("Paint pixel") {
        mutateCurrentLayer { buffer in
          ToolOps.pen(on: buffer, at: cursor, color: primaryColorIndex)
        }
      }
      announce("Painted at \(cursor.x),\(cursor.y)")
    case .eraser:
      recordUndoableEdit("Erase pixel") {
        mutateCurrentLayer { buffer in
          ToolOps.erase(on: buffer, at: cursor)
        }
      }
      announce("Erased \(cursor.x),\(cursor.y)")
    case .fill:
      recordUndoableEdit("Fill region") {
        mutateCurrentLayer { buffer in
          ToolOps.fill(
            on: buffer,
            at: cursor,
            color: primaryColorIndex,
            selection: selection
          )
        }
      }
      announce("Filled region")
    case .gradient:
      if let anchor = pendingGradientAnchor {
        recordUndoableEdit("Apply gradient") {
          mutateCurrentLayer { buffer in
            ToolOps.gradient(
              on: buffer,
              from: anchor,
              to: cursor,
              startColor: document.palette[primaryColorIndex],
              endColor: document.palette[secondaryColorIndex],
              palette: document.palette,
              selection: selection
            )
          }
        }
        pendingGradientAnchor = nil
        announce("Gradient committed")
      } else {
        pendingGradientAnchor = cursor
        announce("Gradient: anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .marquee:
      if let anchor = pendingMarqueeAnchor {
        selection = Selection(rect: PixelRect.bounding(anchor, cursor))
        pendingMarqueeAnchor = nil
        announce("Selection committed")
      } else {
        pendingMarqueeAnchor = cursor
        announce("Marquee: anchor at \(cursor.x),\(cursor.y), move and press Space again")
      }
    case .eyedropper:
      // Walk top-to-bottom and pick the first opaque pixel on any
      // visible layer at the cursor.
      for layer in currentFrame.layers.reversed() where layer.isVisible {
        if let idx = layer.pixels[cursor], let actualIdx = idx as PaletteIndex? {
          primaryColorIndex = actualIdx
          announce("Picked color slot \(Int(actualIdx))")
          return
        }
      }
      announce("Nothing to pick at \(cursor.x),\(cursor.y)")
    }
  }

  public func selectTool(_ newTool: EditorTool) {
    tool = newTool
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    announce("Tool: \(newTool.label)")
  }

  public func clearSelection() {
    selection = nil
    pendingMarqueeAnchor = nil
    announce("Selection cleared")
  }

  public func swapPrimaryAndSecondary() {
    let tmp = primaryColorIndex
    primaryColorIndex = secondaryColorIndex
    secondaryColorIndex = tmp
  }

  public func setPrimaryColor(_ index: PaletteIndex) {
    primaryColorIndex = index
    announce("Primary: slot \(Int(index))")
  }

  public func setSecondaryColor(_ index: PaletteIndex) {
    secondaryColorIndex = index
    announce("Secondary: slot \(Int(index))")
  }

  // MARK: - Cursor

  public func moveCursor(dx: Int, dy: Int) {
    cursor = GIFEditorCore.PixelPoint(x: cursor.x + dx, y: cursor.y + dy)
  }

  public func beginCanvasDrag(at point: GIFEditorCore.PixelPoint) {
    cursor = point
    switch tool {
    case .pen:
      beginUndoGroup("Paint stroke")
      strokeCurrentLayer(from: point, to: point, color: primaryColorIndex)
      announce("Painting \(point.x),\(point.y)")
    case .eraser:
      beginUndoGroup("Erase stroke")
      strokeCurrentLayer(from: point, to: point, color: nil)
      announce("Erasing \(point.x),\(point.y)")
    case .fill, .eyedropper:
      announce("Target \(point.x),\(point.y)")
    case .gradient:
      beginUndoGroup("Apply gradient")
      pendingGradientAnchor = point
      announce("Gradient anchor \(point.x),\(point.y)")
    case .marquee:
      pendingMarqueeAnchor = point
      selection = Selection(rect: PixelRect.bounding(point, point))
      announce("Selecting from \(point.x),\(point.y)")
    }
  }

  public func updateCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    cursor = point
    switch tool {
    case .pen:
      strokeCurrentLayer(from: previous ?? anchor, to: point, color: primaryColorIndex)
      announce("Painting \(point.x),\(point.y)")
    case .eraser:
      strokeCurrentLayer(from: previous ?? anchor, to: point, color: nil)
      announce("Erasing \(point.x),\(point.y)")
    case .fill, .eyedropper:
      announce("Target \(point.x),\(point.y)")
    case .gradient:
      pendingGradientAnchor = anchor
      announce("Gradient \(anchor.x),\(anchor.y) -> \(point.x),\(point.y)")
    case .marquee:
      pendingMarqueeAnchor = anchor
      selection = Selection(rect: PixelRect.bounding(anchor, point))
      announce("Selection \(anchor.x),\(anchor.y) -> \(point.x),\(point.y)")
    }
  }

  public func endCanvasDrag(
    startingAt anchor: GIFEditorCore.PixelPoint,
    from previous: GIFEditorCore.PixelPoint?,
    to point: GIFEditorCore.PixelPoint
  ) {
    if previous == nil {
      beginCanvasDrag(at: anchor)
    }

    cursor = point
    switch tool {
    case .pen:
      if let previous, previous != point {
        strokeCurrentLayer(from: previous, to: point, color: primaryColorIndex)
      }
      finishUndoGroup()
      announce("Painted to \(point.x),\(point.y)")
    case .eraser:
      if let previous, previous != point {
        strokeCurrentLayer(from: previous, to: point, color: nil)
      }
      finishUndoGroup()
      announce("Erased to \(point.x),\(point.y)")
    case .fill, .eyedropper:
      applyToolAtCursor()
    case .gradient:
      pendingGradientAnchor = anchor
      applyToolAtCursor()
      finishUndoGroup()
    case .marquee:
      pendingMarqueeAnchor = anchor
      applyToolAtCursor()
    }
  }

  // MARK: - Frames

  public func nextFrame() {
    if document.frames.count > 1 {
      currentFrameIndex = (currentFrameIndex + 1) % document.frames.count
      announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
    }
  }

  public func previousFrame() {
    if document.frames.count > 1 {
      currentFrameIndex =
        (currentFrameIndex - 1 + document.frames.count) % document.frames.count
      announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
    }
  }

  public func insertBlankFrameAfterCurrent() {
    recordUndoableEdit("Insert blank frame") {
      let layer = EditorLayer(name: "Layer 1", pixels: PixelBuffer(size: document.size))
      let frame = EditorFrame(
        layers: [layer],
        delayCentiseconds: currentFrame.delayCentiseconds
      )
      document.frames.insert(frame, at: currentFrameIndex + 1)
      currentFrameIndex += 1
    }
    announce("Inserted blank frame")
  }

  public func duplicateCurrentFrame() {
    recordUndoableEdit("Duplicate frame") {
      let copy = currentFrame
      let dup = EditorFrame(
        layers: copy.layers.map {
          EditorLayer(name: $0.name, isVisible: $0.isVisible, pixels: $0.pixels)
        },
        delayCentiseconds: copy.delayCentiseconds,
        disposal: copy.disposal
      )
      document.frames.insert(dup, at: currentFrameIndex + 1)
      currentFrameIndex += 1
    }
    announce("Duplicated frame")
  }

  public func deleteCurrentFrame() {
    guard document.frames.count > 1 else {
      announce("Can't delete the last frame")
      return
    }
    recordUndoableEdit("Delete frame") {
      document.frames.remove(at: currentFrameIndex)
      if currentFrameIndex >= document.frames.count {
        currentFrameIndex = document.frames.count - 1
      }
    }
    announce("Deleted frame")
  }

  public func adjustCurrentFrameDelay(by delta: Int) {
    var updatedDelay = currentFrame.delayCentiseconds
    recordUndoableEdit("Adjust frame delay") {
      var frame = currentFrame
      frame.delayCentiseconds = max(1, frame.delayCentiseconds + delta)
      updatedDelay = frame.delayCentiseconds
      document.frames[currentFrameIndex] = frame
    }
    announce("Frame delay: \(updatedDelay)cs")
  }

  public func setAllFrameDelaysToCurrent() {
    let target = currentFrame.delayCentiseconds
    recordUndoableEdit("Equalize frame delays") {
      for i in document.frames.indices {
        document.frames[i].delayCentiseconds = target
      }
    }
    announce("All frame delays = \(target)cs")
  }

  // MARK: - Layers

  public func addLayer() {
    recordUndoableEdit("Add layer") {
      let layer = EditorLayer(
        name: "Layer \(currentFrame.layers.count + 1)",
        pixels: PixelBuffer(size: document.size)
      )
      document.frames[currentFrameIndex].layers.append(layer)
      currentLayerIndex = document.frames[currentFrameIndex].layers.count - 1
    }
    announce("New layer")
  }

  public func selectLayerBelow() {
    if currentLayerIndex > 0 {
      currentLayerIndex -= 1
      announce("Layer \(currentLayerIndex + 1)/\(currentFrame.layers.count)")
    }
  }

  public func selectLayerAbove() {
    if currentLayerIndex < currentFrame.layers.count - 1 {
      currentLayerIndex += 1
      announce("Layer \(currentLayerIndex + 1)/\(currentFrame.layers.count)")
    }
  }

  public func toggleCurrentLayerVisibility() {
    var isVisible = currentLayer.isVisible
    recordUndoableEdit("Toggle layer visibility") {
      var layer = currentLayer
      layer.isVisible.toggle()
      isVisible = layer.isVisible
      document.frames[currentFrameIndex].layers[currentLayerIndex] = layer
    }
    announce(isVisible ? "Layer shown" : "Layer hidden")
  }

  public func deleteCurrentLayer() {
    guard currentFrame.layers.count > 1 else {
      announce("Can't delete the last layer in a frame")
      return
    }
    recordUndoableEdit("Delete layer") {
      document.frames[currentFrameIndex].layers.remove(at: currentLayerIndex)
      if currentLayerIndex >= currentFrame.layers.count {
        currentLayerIndex = currentFrame.layers.count - 1
      }
    }
    announce("Deleted layer")
  }

  // MARK: - Clipboard

  public func copySelection() {
    let buffer = currentLayer.pixels
    if let selection {
      clipboard = ToolOps.copy(from: buffer, rect: selection.rect)
    } else {
      clipboard = buffer
    }
    announce(clipboard != nil ? "Copied" : "Nothing to copy")
  }

  public func paste() {
    guard let clipboard else {
      announce("Clipboard empty")
      return
    }
    recordUndoableEdit("Paste") {
      mutateCurrentLayer { buffer in
        ToolOps.paste(onto: buffer, clipboard: clipboard, at: cursor)
      }
    }
    announce("Pasted at \(cursor.x),\(cursor.y)")
  }

  // MARK: - Canvas resize

  public func resizeCanvas(to size: GIFEditorCore.PixelSize) {
    recordUndoableEdit("Resize canvas") {
      document.size = size
      for frameIndex in document.frames.indices {
        for layerIndex in document.frames[frameIndex].layers.indices {
          var layer = document.frames[frameIndex].layers[layerIndex]
          layer.pixels = layer.pixels.resized(to: size)
          document.frames[frameIndex].layers[layerIndex] = layer
        }
      }
      cursor = GIFEditorCore.PixelPoint(
        x: min(cursor.x, size.width - 1),
        y: min(cursor.y, size.height - 1)
      )
      selection = nil
    }
    announce("Canvas resized to \(size.width)×\(size.height)")
  }

  // MARK: - Save / load

  public func save() {
    let target =
      document.path
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("untitled.gif")
    do {
      let bytes = try GIFEncoder.encode(document: document)
      try Data(bytes).write(to: target, options: .atomic)
      document.path = target
      cleanHistoryGeneration = currentHistoryGeneration
      announce("Saved to \(target.path)")
    } catch {
      announce("Save failed: \(error)")
    }
  }

  public func saveAs() {
    let url =
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("untitled.gif")
    document.path = url
    save()
  }

  // MARK: - Helpers

  private func recordUndoableEdit(_ label: String, _ edit: () -> Void) {
    if activeUndoGroup != nil {
      edit()
      return
    }

    let before = snapshotState()
    edit()
    commitUndoStep(from: before, label: label)
  }

  private func beginUndoGroup(_ label: String) {
    guard activeUndoGroup == nil else { return }
    activeUndoGroup = ActiveUndoGroup(snapshot: snapshotState(), label: label)
  }

  private func finishUndoGroup(label: String? = nil) {
    guard let group = activeUndoGroup else { return }
    activeUndoGroup = nil
    commitUndoStep(from: group.snapshot, label: label ?? group.label)
  }

  private func commitUndoStep(from before: EditorSnapshot, label: String) {
    guard document != before.document else { return }

    undoStack.append(HistoryEntry(snapshot: before, label: label))
    if undoStack.count > historyLimit {
      undoStack.removeFirst(undoStack.count - historyLimit)
    }
    redoStack.removeAll()
    currentHistoryGeneration = nextHistoryGeneration
    nextHistoryGeneration += 1
  }

  private func snapshotState() -> EditorSnapshot {
    EditorSnapshot(
      document: document,
      currentFrameIndex: currentFrameIndex,
      currentLayerIndex: currentLayerIndex,
      cursor: cursor,
      selection: selection,
      historyGeneration: currentHistoryGeneration
    )
  }

  private func restore(_ snapshot: EditorSnapshot) {
    document = snapshot.document
    currentFrameIndex = snapshot.currentFrameIndex
    currentLayerIndex = snapshot.currentLayerIndex
    cursor = snapshot.cursor
    selection = snapshot.selection
    pendingMarqueeAnchor = nil
    pendingGradientAnchor = nil
    currentHistoryGeneration = snapshot.historyGeneration
  }

  /// Replaces the current layer's pixel buffer with the result of
  /// `transform`. Callers own history grouping.
  private func mutateCurrentLayer(_ transform: (PixelBuffer) -> PixelBuffer) {
    var layer = currentLayer
    layer.pixels = transform(layer.pixels)
    document.frames[currentFrameIndex].layers[currentLayerIndex] = layer
  }

  private func strokeCurrentLayer(
    from start: GIFEditorCore.PixelPoint,
    to end: GIFEditorCore.PixelPoint,
    color: PaletteIndex?
  ) {
    mutateCurrentLayer { buffer in
      ToolOps.line(on: buffer, from: start, to: end, color: color)
    }
  }

  private func announce(_ message: String) {
    statusMessage = message
  }
}

// Local clamp helper since `Comparable.clamped(to:)` isn't in stdlib.
extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
