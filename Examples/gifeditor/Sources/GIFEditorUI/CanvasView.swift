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
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let cursor: GIFEditorCore.PixelPoint
  let selection: Selection?
  let pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  let pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint? = nil
  var mode: CanvasPixelGridMode = .verticalHalfBlock

  var body: some View {
    CanvasSurfaceView(
      size: size,
      cells: cells,
      cursor: cursor,
      selection: selection,
      pendingMarqueeAnchor: pendingMarqueeAnchor,
      pendingGradientAnchor: pendingGradientAnchor,
      hover: hover,
      mode: mode
    )
    .border(.separator, set: .single)
  }
}

private struct CanvasSurfaceView: View {
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let cursor: GIFEditorCore.PixelPoint
  let selection: Selection?
  let pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  let pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint? = nil
  var mode: CanvasPixelGridMode = .verticalHalfBlock

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
          pixels: resolvedPixels,
          cursor: cursor,
          selection: selection,
          pendingMarqueeAnchor: pendingMarqueeAnchor,
          pendingGradientAnchor: pendingGradientAnchor,
          hover: hover,
          mode: mode
        )
      )
      .frame(width: size.width, height: mode.cellHeight(for: size.height))
    }
    .frame(width: size.width, height: mode.cellHeight(for: size.height))
  }

  private var resolvedPixels: [Color?] {
    var output: [Color?] = []
    output.reserveCapacity(size.area)
    for y in 0..<size.height {
      for x in 0..<size.width {
        output.append(fillColor(at: GIFEditorCore.PixelPoint(x: x, y: y)))
      }
    }
    return output
  }

  /// Resolves the color a pixel paints. Falls back to a checkerboard
  /// background pattern for transparent cells so the user can tell
  /// transparent from "actually painted in their bg color".
  private func fillColor(at point: GIFEditorCore.PixelPoint) -> Color {
    if let color = cells[size.indexOf(point)] {
      return color.toTerminalColor()
    }
    // Checkerboard for transparent.
    let shade = ((point.x + point.y) & 1) == 0 ? 0.18 : 0.10
    return Color(red: shade, green: shade, blue: shade, alpha: 1.0)
  }
}

private struct CanvasOverlayDrawing: CanvasDrawing, Equatable {
  var size: GIFEditorCore.PixelSize
  var pixels: [Color?]
  var cursor: GIFEditorCore.PixelPoint
  var selection: Selection?
  var pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  var pendingGradientAnchor: GIFEditorCore.PixelPoint?
  var hover: GIFEditorCore.PixelPoint?
  var mode: CanvasPixelGridMode

  func draw(into context: inout CanvasContext) {
    if let hover, hover != cursor {
      mark(hover, kind: .hover, into: &context)
    }
    if let selection {
      drawSelection(selection.rect, into: &context)
    }
    if let anchor = pendingMarqueeAnchor {
      mark(anchor, kind: .anchor(color: .yellow), into: &context)
    }
    if let anchor = pendingGradientAnchor {
      mark(anchor, kind: .anchor(color: .green), into: &context)
    }
    mark(cursor, kind: .cursor, into: &context)
  }

  private func drawSelection(
    _ rect: PixelRect,
    into context: inout CanvasContext
  ) {
    for y in rect.minY..<rect.maxY {
      for x in rect.minX..<rect.maxX {
        let point = GIFEditorCore.PixelPoint(x: x, y: y)
        guard isOnSelectionBorder(point: point, rect: rect) else {
          continue
        }
        mark(point, kind: .selection, into: &context)
      }
    }
  }

  private func isOnSelectionBorder(point: GIFEditorCore.PixelPoint, rect: PixelRect) -> Bool {
    guard rect.contains(point) else { return false }
    return point.x == rect.minX || point.x == rect.maxX - 1
      || point.y == rect.minY || point.y == rect.maxY - 1
  }

  private func mark(
    _ point: GIFEditorCore.PixelPoint,
    kind: OverlayMark,
    into context: inout CanvasContext
  ) {
    guard size.contains(point) else {
      return
    }
    let cell = cellPoint(for: point)
    let style = kind.style(for: point, mode: mode)
    context.setCell(
      x: cell.x,
      y: cell.y,
      character: style.character,
      foreground: style.color,
      background: backgroundColor(behind: point)
    )
  }

  private func cellPoint(for point: GIFEditorCore.PixelPoint) -> GIFEditorCore.PixelPoint {
    switch mode {
    case .fullCell:
      return point
    case .verticalHalfBlock:
      return GIFEditorCore.PixelPoint(x: point.x, y: point.y / 2)
    }
  }

  private func backgroundColor(behind point: GIFEditorCore.PixelPoint) -> Color? {
    switch mode {
    case .fullCell:
      return pixelColor(at: point)
    case .verticalHalfBlock:
      let pairedY = point.y.isMultiple(of: 2) ? point.y + 1 : point.y - 1
      return pixelColor(at: GIFEditorCore.PixelPoint(x: point.x, y: pairedY))
    }
  }

  private func pixelColor(at point: GIFEditorCore.PixelPoint) -> Color? {
    guard size.contains(point) else {
      return nil
    }
    let index = size.indexOf(point)
    guard pixels.indices.contains(index) else {
      return nil
    }
    return pixels[index]
  }
}

private enum OverlayMark: Equatable {
  case cursor
  case hover
  case selection
  case anchor(color: Color)

  func style(
    for point: GIFEditorCore.PixelPoint,
    mode: CanvasPixelGridMode
  ) -> (character: Character, color: Color) {
    switch mode {
    case .fullCell:
      switch self {
      case .cursor:
        return ("◆", .cyan)
      case .hover:
        return ("·", .magenta)
      case .selection:
        return ("□", .blue)
      case .anchor(let color):
        return ("◇", color)
      }
    case .verticalHalfBlock:
      let halfBlock: Character = point.y.isMultiple(of: 2) ? "▀" : "▄"
      switch self {
      case .cursor:
        return (halfBlock, .cyan)
      case .hover:
        return (halfBlock, .magenta)
      case .selection:
        return (halfBlock, .blue)
      case .anchor(let color):
        return (halfBlock, color)
      }
    }
  }
}

struct InteractiveCanvasView: View {
  let size: GIFEditorCore.PixelSize
  let cells: [EditorColor?]
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void
  var mode: CanvasPixelGridMode = .verticalHalfBlock

  @State private var dragAnchor: GIFEditorCore.PixelPoint?
  @State private var lastDragPoint: GIFEditorCore.PixelPoint?
  @State private var hover: GIFEditorCore.PixelPoint?

  var body: some View {
    EnvironmentReader(\.pointerInputCapabilities) { pointerInputCapabilities in
      CanvasSurfaceView(
        size: size,
        cells: cells,
        cursor: model.cursor,
        selection: model.selection,
        pendingMarqueeAnchor: model.pendingMarqueeAnchor,
        pendingGradientAnchor: model.pendingGradientAnchor,
        hover: hover,
        mode: mode
      )
      .contentShape(
        canvasPointerTargetPath(
          width: size.width,
          height: mode.cellHeight(for: size.height)
        )
      )
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
          .onChanged { value in
            handleDragChange(value)
          }
          .onEnded { value in
            handleDragEnd(value)
          }
      )
      .onPointerHover { phase in
        updateHover(phase, precision: pointerInputCapabilities.precision)
      }
      .focusable(true, interactions: .edit)
    }
  }

  private func handleDragChange(_ value: DragGesture.Value) {
    let anchor =
      dragAnchor
      ?? canvasPixelPoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode,
        size: size
      )
    let current = canvasPixelPoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode,
      size: size
    )

    if dragAnchor == nil {
      dragAnchor = anchor
      model.beginCanvasDrag(at: anchor)
    }
    model.updateCanvasDrag(startingAt: anchor, from: lastDragPoint, to: current)
    lastDragPoint = current
    hover = current
    refresh()
  }

  private func handleDragEnd(_ value: DragGesture.Value) {
    let anchor =
      dragAnchor
      ?? canvasPixelPoint(
        forLocalCell: value.startLocation,
        precision: value.pointer.precision,
        mode: mode,
        size: size
      )
    let current = canvasPixelPoint(
      forLocalCell: value.location,
      precision: value.pointer.precision,
      mode: mode,
      size: size
    )

    model.endCanvasDrag(startingAt: anchor, from: lastDragPoint, to: current)
    dragAnchor = nil
    lastDragPoint = nil
    hover = current
    refresh()
  }

  private func updateHover(_ phase: HoverPhase, precision: PointerPrecision) {
    switch phase {
    case .entered(let location), .moved(let location):
      hover = canvasPixelPoint(
        forLocalCell: location,
        precision: precision,
        mode: mode,
        size: size
      )
    case .exited:
      hover = nil
    }
  }
}

func canvasPixelPoint(
  forLocalCell point: Point,
  precision: PointerPrecision,
  mode: CanvasPixelGridMode,
  size: GIFEditorCore.PixelSize
) -> GIFEditorCore.PixelPoint {
  let location = canvasPointerLocation(point, precision: precision)
  let ySubdivisions =
    switch mode {
    case .fullCell: 1
    case .verticalHalfBlock: 2
    }
  return GIFEditorCore.PixelPoint(
    x: canvasGridCoordinate(location.x, subdivisions: 1, maxIndex: size.width - 1),
    y: canvasGridCoordinate(location.y, subdivisions: ySubdivisions, maxIndex: size.height - 1)
  )
}

private func canvasPointerLocation(
  _ point: Point,
  precision: PointerPrecision
) -> Point {
  switch precision {
  case .cell:
    Point(point.containingCell)
  case .subCell:
    point
  }
}

private func canvasGridCoordinate(
  _ value: Double,
  subdivisions: Int,
  maxIndex: Int
) -> Int {
  guard maxIndex > 0 else {
    return 0
  }
  let scaled = (value * Double(subdivisions)).rounded(.down)
  guard scaled.isFinite else {
    return scaled.sign == .minus || scaled.isNaN ? 0 : maxIndex
  }
  return min(max(0, Int(scaled)), maxIndex)
}

private func canvasPointerTargetPath(width: Int, height: Int) -> Path {
  let width = max(0, width)
  let height = max(0, height)
  var path = Path()
  guard width > 0, height > 0 else {
    return path
  }
  path.move(to: .zero)
  path.addLine(to: Point(x: Double(width), y: 0))
  path.addLine(to: Point(x: Double(width), y: Double(height)))
  path.addLine(to: Point(x: 0, y: Double(height)))
  path.close()
  return path
}
