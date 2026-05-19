/// Pixel-grid packing modes for ``CanvasPixelGridDrawing``.
public enum CanvasPixelGridMode: Equatable, Sendable {
  /// One logical pixel maps to one terminal cell background.
  case fullCell

  /// Two vertical logical pixels pack into one terminal cell with block
  /// glyphs. The top logical pixel maps to the foreground half and the
  /// bottom logical pixel maps to the background or lower-half glyph.
  case verticalHalfBlock

  /// The terminal-cell height needed to display `logicalHeight` pixels.
  public func cellHeight(for logicalHeight: Int) -> Int {
    switch self {
    case .fullCell:
      return max(0, logicalHeight)
    case .verticalHalfBlock:
      return max(0, (logicalHeight + 1) / 2)
    }
  }
}

/// A dense row-major pixel grid that renders through ``Canvas``.
///
/// The grid stores pre-resolved terminal colors. Callers with indexed
/// colors or transparency policies should resolve those choices before
/// constructing the drawing. `nil` pixels are transparent and leave the
/// destination cell/half-cell untouched.
public struct CanvasPixelGridDrawing: CanvasDrawing, Equatable {
  /// Logical pixel width.
  public var width: Int

  /// Logical pixel height.
  public var height: Int

  /// Row-major logical pixels. Missing entries are treated as transparent.
  public var pixels: [Color?]

  /// Rendering density mode.
  public var mode: CanvasPixelGridMode

  public init(
    width: Int,
    height: Int,
    pixels: [Color?],
    mode: CanvasPixelGridMode = .fullCell
  ) {
    self.width = max(0, width)
    self.height = max(0, height)
    self.pixels = pixels
    self.mode = mode
  }

  public func draw(into context: inout CanvasContext) {
    switch mode {
    case .fullCell:
      drawFullCells(into: &context)
    case .verticalHalfBlock:
      drawVerticalHalfBlocks(into: &context)
    }
  }

  private func drawFullCells(into context: inout CanvasContext) {
    guard width > 0, height > 0 else {
      return
    }

    for y in 0..<height {
      for x in 0..<width {
        guard let color = pixel(x: x, y: y) else {
          continue
        }
        context.fillCell(x: x, y: y, color: color)
      }
    }
  }

  private func drawVerticalHalfBlocks(into context: inout CanvasContext) {
    guard width > 0, height > 0 else {
      return
    }

    let cellHeight = mode.cellHeight(for: height)
    for cellY in 0..<cellHeight {
      let topY = cellY * 2
      let bottomY = topY + 1
      for x in 0..<width {
        let top = pixel(x: x, y: topY)
        let bottom = pixel(x: x, y: bottomY)

        switch (top, bottom) {
        case (nil, nil):
          continue
        case (let top?, let bottom?) where top == bottom:
          context.fillCell(x: x, y: cellY, color: top)
        case (let top?, let bottom?):
          context.setCell(
            x: x,
            y: cellY,
            character: "▀",
            foreground: top,
            background: bottom
          )
        case (let top?, nil):
          context.setCell(
            x: x,
            y: cellY,
            character: "▀",
            foreground: top
          )
        case (nil, let bottom?):
          context.setCell(
            x: x,
            y: cellY,
            character: "▄",
            foreground: bottom
          )
        }
      }
    }
  }

  private func pixel(x: Int, y: Int) -> Color? {
    guard x >= 0, x < width, y >= 0, y < height else {
      return nil
    }
    let index = y * width + x
    guard pixels.indices.contains(index) else {
      return nil
    }
    return pixels[index]
  }
}
