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

  /// Marquee tool's first corner, captured on `Shift+Space` and
  /// committed into a `selection` on `Shift+Enter`.
  public var pendingMarqueeAnchor: GIFEditorCore.PixelPoint? = nil
  /// Gradient tool's first endpoint.
  public var pendingGradientAnchor: GIFEditorCore.PixelPoint? = nil

  // MARK: - Status / feedback

  public var statusMessage: String = ""
  public var isDirty: Bool = false

  public init(document: GIFDocument) {
    self.document = document
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
      mutateCurrentLayer { buffer in
        ToolOps.pen(on: buffer, at: cursor, color: primaryColorIndex)
      }
      announce("Painted at \(cursor.x),\(cursor.y)")
    case .eraser:
      mutateCurrentLayer { buffer in
        ToolOps.erase(on: buffer, at: cursor)
      }
      announce("Erased \(cursor.x),\(cursor.y)")
    case .fill:
      mutateCurrentLayer { buffer in
        ToolOps.fill(
          on: buffer,
          at: cursor,
          color: primaryColorIndex,
          selection: selection
        )
      }
      announce("Filled region")
    case .gradient:
      if let anchor = pendingGradientAnchor {
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
        pendingGradientAnchor = nil
        announce("Gradient committed")
      } else {
        pendingGradientAnchor = cursor
        announce("Gradient: anchor at \(cursor.x),\(cursor.y), move and press Shift+Space again")
      }
    case .marquee:
      if let anchor = pendingMarqueeAnchor {
        selection = Selection(rect: PixelRect.bounding(anchor, cursor))
        pendingMarqueeAnchor = nil
        announce("Selection committed")
      } else {
        pendingMarqueeAnchor = cursor
        announce("Marquee: anchor at \(cursor.x),\(cursor.y), move and press Shift+Space again")
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
    let layer = EditorLayer(name: "Layer 1", pixels: PixelBuffer(size: document.size))
    let frame = EditorFrame(
      layers: [layer],
      delayCentiseconds: currentFrame.delayCentiseconds
    )
    document.frames.insert(frame, at: currentFrameIndex + 1)
    currentFrameIndex += 1
    markDirty("Inserted blank frame")
  }

  public func duplicateCurrentFrame() {
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
    markDirty("Duplicated frame")
  }

  public func deleteCurrentFrame() {
    guard document.frames.count > 1 else {
      announce("Can't delete the last frame")
      return
    }
    document.frames.remove(at: currentFrameIndex)
    if currentFrameIndex >= document.frames.count {
      currentFrameIndex = document.frames.count - 1
    }
    markDirty("Deleted frame")
  }

  public func adjustCurrentFrameDelay(by delta: Int) {
    var frame = currentFrame
    frame.delayCentiseconds = max(1, frame.delayCentiseconds + delta)
    document.frames[currentFrameIndex] = frame
    markDirty("Frame delay: \(frame.delayCentiseconds)cs")
  }

  public func setAllFrameDelaysToCurrent() {
    let target = currentFrame.delayCentiseconds
    for i in document.frames.indices {
      document.frames[i].delayCentiseconds = target
    }
    markDirty("All frame delays = \(target)cs")
  }

  // MARK: - Layers

  public func addLayer() {
    let layer = EditorLayer(
      name: "Layer \(currentFrame.layers.count + 1)",
      pixels: PixelBuffer(size: document.size)
    )
    document.frames[currentFrameIndex].layers.append(layer)
    currentLayerIndex = document.frames[currentFrameIndex].layers.count - 1
    markDirty("New layer")
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
    var layer = currentLayer
    layer.isVisible.toggle()
    document.frames[currentFrameIndex].layers[currentLayerIndex] = layer
    markDirty(layer.isVisible ? "Layer shown" : "Layer hidden")
  }

  public func deleteCurrentLayer() {
    guard currentFrame.layers.count > 1 else {
      announce("Can't delete the last layer in a frame")
      return
    }
    document.frames[currentFrameIndex].layers.remove(at: currentLayerIndex)
    if currentLayerIndex >= currentFrame.layers.count {
      currentLayerIndex = currentFrame.layers.count - 1
    }
    markDirty("Deleted layer")
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
    mutateCurrentLayer { buffer in
      ToolOps.paste(onto: buffer, clipboard: clipboard, at: cursor)
    }
    announce("Pasted at \(cursor.x),\(cursor.y)")
  }

  // MARK: - Canvas resize

  public func resizeCanvas(to size: GIFEditorCore.PixelSize) {
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
    markDirty("Canvas resized to \(size.width)×\(size.height)")
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
      isDirty = false
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

  /// Replaces the current layer's pixel buffer with the result of
  /// `transform`. Marks the document dirty.
  private func mutateCurrentLayer(_ transform: (PixelBuffer) -> PixelBuffer) {
    var layer = currentLayer
    layer.pixels = transform(layer.pixels)
    document.frames[currentFrameIndex].layers[currentLayerIndex] = layer
    isDirty = true
  }

  private func markDirty(_ message: String) {
    isDirty = true
    statusMessage = message
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
