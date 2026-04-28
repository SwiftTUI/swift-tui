import GIFEditorCore
import TerminalUI

/// Renders one composited frame as a Canvas-backed grid of colored cells.
///
/// `cells` is the row-major composited buffer (`document.flattenedColors`)
/// — passing the data in this shape rather than the layer model itself
/// keeps the view ignorant of compositing rules and lets the parent
/// reuse a single flatten pass for both the canvas and the timeline
/// thumbnail.
struct CanvasView: View {
  let size: PixelSize
  let cells: [EditorColor?]
  let cursor: PixelPoint
  let selection: Selection?
  let pendingMarqueeAnchor: PixelPoint?
  let pendingGradientAnchor: PixelPoint?
  var mode: CanvasPixelGridMode = .fullCell

  var body: some View {
    ZStack(alignment: .topLeading) {
      Canvas(
        pixelGridWidth: size.width,
        height: size.height,
        pixels: resolvedPixels,
        mode: mode
      )
      .frame(width: size.width, height: mode.cellHeight(for: size.height))

      Canvas(
        CanvasOverlayDrawing(
          size: size,
          cursor: cursor,
          selection: selection,
          pendingMarqueeAnchor: pendingMarqueeAnchor,
          pendingGradientAnchor: pendingGradientAnchor,
          mode: mode
        )
      )
      .frame(width: size.width, height: mode.cellHeight(for: size.height))
    }
    .border(.separator)
  }

  private var resolvedPixels: [Color?] {
    var output: [Color?] = []
    output.reserveCapacity(size.area)
    for y in 0..<size.height {
      for x in 0..<size.width {
        output.append(fillColor(at: PixelPoint(x: x, y: y)))
      }
    }
    return output
  }

  /// Resolves the color a pixel paints. Falls back to a checkerboard
  /// background pattern for transparent cells so the user can tell
  /// transparent from "actually painted in their bg color".
  private func fillColor(at point: PixelPoint) -> Color {
    if let color = cells[size.indexOf(point)] {
      return color.toTerminalColor()
    }
    // Checkerboard for transparent.
    let shade = ((point.x + point.y) & 1) == 0 ? 0.18 : 0.10
    return Color(red: shade, green: shade, blue: shade, alpha: 1.0)
  }
}

private struct CanvasOverlayDrawing: CanvasDrawing, Equatable {
  var size: PixelSize
  var cursor: PixelPoint
  var selection: Selection?
  var pendingMarqueeAnchor: PixelPoint?
  var pendingGradientAnchor: PixelPoint?
  var mode: CanvasPixelGridMode

  func draw(into context: inout CanvasContext) {
    if let selection {
      drawSelection(selection.rect, into: &context)
    }
    if let anchor = pendingMarqueeAnchor {
      mark(anchor, character: "◇", color: .yellow, into: &context)
    }
    if let anchor = pendingGradientAnchor {
      mark(anchor, character: "◇", color: .green, into: &context)
    }
    mark(cursor, character: "◆", color: .cyan, into: &context)
  }

  private func drawSelection(
    _ rect: PixelRect,
    into context: inout CanvasContext
  ) {
    for y in rect.minY..<rect.maxY {
      for x in rect.minX..<rect.maxX {
        let point = PixelPoint(x: x, y: y)
        guard isOnSelectionBorder(point: point, rect: rect) else {
          continue
        }
        mark(point, character: "□", color: .blue, into: &context)
      }
    }
  }

  private func isOnSelectionBorder(point: PixelPoint, rect: PixelRect) -> Bool {
    guard rect.contains(point) else { return false }
    return point.x == rect.minX || point.x == rect.maxX - 1
      || point.y == rect.minY || point.y == rect.maxY - 1
  }

  private func mark(
    _ point: PixelPoint,
    character: Character,
    color: Color,
    into context: inout CanvasContext
  ) {
    guard size.contains(point) else {
      return
    }
    let cell = cellPoint(for: point)
    context.setCell(
      x: cell.x,
      y: cell.y,
      character: character,
      foreground: color
    )
  }

  private func cellPoint(for point: PixelPoint) -> PixelPoint {
    switch mode {
    case .fullCell:
      return point
    case .verticalHalfBlock:
      return PixelPoint(x: point.x, y: point.y / 2)
    }
  }
}
