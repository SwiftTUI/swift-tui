import GIFEditorCore
import TerminalUI

/// Renders one composited frame as a grid of 1×1 colored cells.
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

  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<size.height, id: \.self) { y in
        rowView(y: y)
      }
    }
    .border(.separator)
  }

  private func rowView(y: Int) -> some View {
    HStack(spacing: 0) {
      ForEach(0..<size.width, id: \.self) { x in
        cellView(at: PixelPoint(x: x, y: y))
      }
    }
  }

  private func cellView(at point: PixelPoint) -> some View {
    Rectangle()
      .fill(fillColor(at: point))
      .frame(width: 1, height: 1)
      .overlay { overlayMark(at: point) }
  }

  /// Resolves the color a cell paints. Falls back to a checkerboard
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

  /// Cursor + selection rectangle + pending-marquee anchor markers
  /// all paint here as 1-cell overlays so they don't disturb the
  /// per-pixel fill color.
  @ViewBuilder
  private func overlayMark(at point: PixelPoint) -> some View {
    if point == cursor {
      Rectangle()
        .stroke(.tint)
        .frame(width: 1, height: 1)
    } else if let anchor = pendingMarqueeAnchor, point == anchor {
      Rectangle()
        .stroke(.warning)
        .frame(width: 1, height: 1)
    } else if let anchor = pendingGradientAnchor, point == anchor {
      Rectangle()
        .stroke(.success)
        .frame(width: 1, height: 1)
    } else if let selection, isOnSelectionBorder(point: point, rect: selection.rect) {
      Rectangle()
        .stroke(.selection)
        .frame(width: 1, height: 1)
    } else {
      EmptyView()
    }
  }

  private func isOnSelectionBorder(point: PixelPoint, rect: PixelRect) -> Bool {
    guard rect.contains(point) else { return false }
    return point.x == rect.minX || point.x == rect.maxX - 1
      || point.y == rect.minY || point.y == rect.maxY - 1
  }
}
