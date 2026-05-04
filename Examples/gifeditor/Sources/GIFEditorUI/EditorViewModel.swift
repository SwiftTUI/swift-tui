import Foundation
import GIFEditorCore
import SwiftTUI

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

  private struct ActiveSelectMove {
    var layerPixels: PixelBuffer
    var selection: Selection?
    var sourceRect: PixelRect
  }

  private var undoStack: [HistoryEntry] = []
  private var redoStack: [HistoryEntry] = []
  private var activeUndoGroup: ActiveUndoGroup?
  private var activeSelectMove: ActiveSelectMove?
  private var currentHistoryGeneration: Int = 0
  private var cleanHistoryGeneration: Int = 0
  private var nextHistoryGeneration: Int = 1
  private let historyLimit: Int = 100

  // MARK: - Selection state

  public var currentFrameIndex: Int = 0 {
    didSet {
      currentFrameIndex = currentFrameIndex.clamped(to: 0...max(0, document.frames.count - 1))
      // The new frame may have fewer layers than the previous one;
      // currentLayerIndex's own didSet doesn't fire when only the frame
      // changes, so re-clamp explicitly here.
      clampCurrentLayerIndex()
    }
  }

  public var currentLayerIndex: Int = 0 {
    didSet {
      clampCurrentLayerIndex()
    }
  }

  private func clampCurrentLayerIndex() {
    let upper = max(0, document.frames[currentFrameIndex].layers.count - 1)
    let clamped = currentLayerIndex.clamped(to: 0...upper)
    if currentLayerIndex != clamped {
      currentLayerIndex = clamped
    }
  }

  // MARK: - Tool state

  public var tool: EditorTool = .pen
  public var primaryColorIndex: PaletteIndex = 1
  public var secondaryColorIndex: PaletteIndex = 2
  /// Pencil-style square brush diameter applied to pen and eraser
  /// strokes. Clamped to 1...8 to keep stamps tractable on the small
  /// canvas sizes the editor supports.
  public var brushSize: Int = 1 {
    didSet {
      brushSize = brushSize.clamped(to: 1...8)
    }
  }
  /// When true (default), the bucket fill is clipped to the active
  /// marquee selection. Toggle off via the options bar when you want
  /// a fill to ignore the selection and flood the entire matching
  /// region.
  public var fillRespectsSelection: Bool = true
  /// Mirror of `fillRespectsSelection` for the gradient tool. Toggle
  /// off via the options bar when you want the gradient to span the
  /// whole canvas regardless of the active marquee.
  public var gradientRespectsSelection: Bool = true
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
        strokeCurrentLayer(from: cursor, to: cursor, color: primaryColorIndex)
      }
      announce("Painted at \(cursor.x),\(cursor.y)")
    case .eraser:
      recordUndoableEdit("Erase pixel") {
        strokeCurrentLayer(from: cursor, to: cursor, color: nil)
      }
      announce("Erased \(cursor.x),\(cursor.y)")
    case .fill:
      recordUndoableEdit("Fill region") {
        mutateCurrentLayer { buffer in
          ToolOps.fill(
            on: buffer,
            at: cursor,
            color: primaryColorIndex,
            selection: fillRespectsSelection ? selection : nil
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
              selection: gradientRespectsSelection ? selection : nil
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
    case .select:
      announce(
        selection == nil ? "Select: drag to move layer pixels" : "Select: drag to move selection")
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
    activeSelectMove = nil
    announce("Tool: \(newTool.label)")
  }

  public func clearSelection() {
    selection = nil
    pendingMarqueeAnchor = nil
    activeSelectMove = nil
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

  // MARK: - Brush

  public func increaseBrushSize() {
    let previous = brushSize
    brushSize = min(8, previous + 1)
    if brushSize == previous {
      announce("Brush at maximum (\(brushSize))")
    } else {
      announce("Brush size: \(brushSize)")
    }
  }

  public func decreaseBrushSize() {
    let previous = brushSize
    brushSize = max(1, previous - 1)
    if brushSize == previous {
      announce("Brush at minimum (\(brushSize))")
    } else {
      announce("Brush size: \(brushSize)")
    }
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
    case .select:
      beginUndoGroup("Move pixels")
      beginSelectMove()
      updateSelectMove(startingAt: point, to: point)
      announce(selectMoveStatus(to: point, from: point))
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
    case .select:
      if activeSelectMove == nil {
        beginUndoGroup("Move pixels")
        beginSelectMove()
      }
      updateSelectMove(startingAt: anchor, to: point)
      announce(selectMoveStatus(to: point, from: anchor))
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
    case .select:
      if activeSelectMove == nil {
        beginUndoGroup("Move pixels")
        beginSelectMove()
      }
      updateSelectMove(startingAt: anchor, to: point)
      let status = selectMoveStatus(to: point, from: anchor)
      activeSelectMove = nil
      finishUndoGroup()
      announce(status)
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

  /// Jumps to the first frame. Used by the timeline's `◀◀` button.
  public func goToFirstFrame() {
    guard document.frames.count > 1 else { return }
    currentFrameIndex = 0
    announce("Frame 1/\(document.frames.count)")
  }

  /// Jumps to the last frame. Used by the timeline's `▶▶` button.
  public func goToLastFrame() {
    guard document.frames.count > 1 else { return }
    currentFrameIndex = document.frames.count - 1
    announce("Frame \(currentFrameIndex + 1)/\(document.frames.count)")
  }

  /// Selects the frame at `index`, clamping to valid range. Used when
  /// the user clicks a specific timeline thumbnail.
  public func selectFrame(at index: Int) {
    guard document.frames.indices.contains(index) else { return }
    currentFrameIndex = index
    announce("Frame \(index + 1)/\(document.frames.count)")
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
      // Always assign so currentFrameIndex.didSet runs and re-clamps
      // currentLayerIndex against the new current frame, even when the
      // numeric value of currentFrameIndex doesn't shift.
      currentFrameIndex = min(currentFrameIndex, document.frames.count - 1)
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
    toggleLayerVisibility(at: currentLayerIndex)
  }

  public func deleteCurrentLayer() {
    deleteLayer(at: currentLayerIndex)
  }

  /// Selects the layer at `index`, clamping to valid range. Used by
  /// the layers panel row body click target.
  public func selectLayer(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    currentLayerIndex = index
    announce("Layer \(index + 1)/\(currentFrame.layers.count)")
  }

  /// Toggles the visibility of the layer at `index` independent of
  /// the current selection. Used by the per-row visibility button.
  public func toggleLayerVisibility(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    var isVisible = currentFrame.layers[index].isVisible
    recordUndoableEdit("Toggle layer visibility") {
      var layer = currentFrame.layers[index]
      layer.isVisible.toggle()
      isVisible = layer.isVisible
      document.frames[currentFrameIndex].layers[index] = layer
    }
    announce(isVisible ? "Layer shown" : "Layer hidden")
  }

  /// Deletes the layer at `index`. Refuses to delete the last layer
  /// in the frame (the editor invariant requires at least one).
  public func deleteLayer(at index: Int) {
    guard currentFrame.layers.indices.contains(index) else { return }
    guard currentFrame.layers.count > 1 else {
      announce("Can't delete the last layer in a frame")
      return
    }
    recordUndoableEdit("Delete layer") {
      document.frames[currentFrameIndex].layers.remove(at: index)
      if currentLayerIndex >= currentFrame.layers.count {
        currentLayerIndex = currentFrame.layers.count - 1
      } else if currentLayerIndex > index {
        currentLayerIndex -= 1
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

  /// Square-canvas presets cycled through by `cycleCanvasSize()`.
  public static let canvasSizeProgression: [Int] = [16, 24, 32, 48, 64]

  /// Advances the canvas through the standard size progression (each
  /// dimension `16 → 24 → 32 → 48 → 64 → 16 → …`). Used by both the
  /// `Ctrl+R` keybinding and the File → Resize Canvas menu item so
  /// they remain bit-identical.
  public func cycleCanvasSize() {
    let current = document.size.width
    let next =
      Self.canvasSizeProgression.first { $0 > current }
      ?? Self.canvasSizeProgression[0]
    resizeCanvas(to: GIFEditorCore.PixelSize(width: next, height: next))
  }

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
    activeSelectMove = nil
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
      ToolOps.line(
        on: buffer,
        from: start,
        to: end,
        color: color,
        thickness: brushSize
      )
    }
  }

  private func beginSelectMove() {
    let wholeLayer = PixelRect(
      x: 0,
      y: 0,
      width: document.size.width,
      height: document.size.height
    )
    activeSelectMove = ActiveSelectMove(
      layerPixels: currentLayer.pixels,
      selection: selection,
      sourceRect: selection?.rect ?? wholeLayer
    )
  }

  private func updateSelectMove(
    startingAt anchor: GIFEditorCore.PixelPoint,
    to point: GIFEditorCore.PixelPoint
  ) {
    guard let move = activeSelectMove else {
      return
    }

    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    mutateCurrentLayer { _ in
      ToolOps.move(
        on: move.layerPixels,
        rect: move.sourceRect,
        byX: dx,
        y: dy
      )
    }

    if let selection = move.selection {
      self.selection = Selection(rect: selection.rect.offsetBy(dx: dx, dy: dy))
    }
  }

  private func selectMoveStatus(
    to point: GIFEditorCore.PixelPoint,
    from anchor: GIFEditorCore.PixelPoint
  ) -> String {
    let dx = point.x - anchor.x
    let dy = point.y - anchor.y
    let target = activeSelectMove?.selection == nil ? "layer" : "selection"
    return "Move \(target) Δ\(dx),\(dy)"
  }

  private func announce(_ message: String) {
    statusMessage = message
  }
}

extension PixelRect {
  fileprivate func offsetBy(dx: Int, dy: Int) -> PixelRect {
    PixelRect(x: minX + dx, y: minY + dy, width: size.width, height: size.height)
  }
}

// Local clamp helper since `Comparable.clamped(to:)` isn't in stdlib.
extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
