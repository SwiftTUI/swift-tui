import TerminalUI

/// A `Canvas` whose drawing intentionally paints far past the canvas
/// frame, with `.clipped()` ensuring only cells inside the frame
/// reach the raster.
///
/// The drawing stretches a horizontal line to three times the canvas's
/// cell-space width. That overflow is silently clipped by the canvas grid
/// itself (the context is sized to the frame), so `Canvas` already cannot
/// paint outside its own drawing buffer. `.clipped()` is the cell-level
/// guarantee: it ensures any
/// cells the canvas does paint (or would paint via overflow modifiers
/// downstream) cannot escape the 10-cell frame in the raster.
///
/// Layout shape: `VStack(alignment: .leading)` header + `Canvas(...)`
/// with `.foregroundStyle(Color.cyan).frame(width: 10, height: 4)
/// .clipped().border(.separator)`.
///
/// Observable invariants pinned by the behaviour test:
///   - Cells inside the 10-cell canvas frame on the line's row are
///     painted with cyan foreground (Braille glyphs in U+2800..U+28FF
///     range).
///   - No cyan foreground cell appears at column > frame's right edge
///     within the canvas's row band — `.clipped()` (and the canvas's
///     own subpixel bounds) keep the overflow out of the raster.
public struct CanvasHonorsClipped: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Canvas honors clipped").foregroundStyle(.muted)
      Canvas(LineDrawing())
        .foregroundStyle(Color.cyan)
        .frame(width: 10, height: 4)
        .clipped()
        .border(.separator)
    }
    .padding(1)
  }
}

/// Drawing that paints a horizontal line at the canvas's vertical
/// midline extending to three times the canvas's own cell-space width. The
/// overflow is what `.clipped()` (and the canvas grid bounds) must drop.
private struct LineDrawing: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    let y = Double(context.size.height) / 2
    context.line(
      from: Point(x: 0, y: y),
      to: Point(x: Double(context.size.width * 3), y: y)
    )
  }
}
