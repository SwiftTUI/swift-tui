import SwiftTUIRuntime

/// Demonstrates that `.offset(x: -2)` paints content to the LEFT of
/// where the layout would otherwise place it — and that, with no
/// `.clipped()` on an enclosing container, the painted glyphs can
/// escape into cells the parent did not reserve for them.
///
/// The layout is an HStack containing a 5-cell spacer block followed
/// by `[ESC]`.  Without offset, `[ESC]` would paint immediately after
/// the 5 spacer cells.  With `.offset(x: -2)` it paints 2 cells to
/// the left of that natural position; the parent does not clip, so
/// the negative offset is observable in the raster.
///
/// The header `"Negative offset escape"` is the catalog marker.
public struct NegativeOffsetEscape: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Negative offset escape").foregroundStyle(.muted)
      HStack(spacing: 0) {
        Text("#####").frame(width: 5, height: 1)
        Text("[ESC]").offset(x: -2)
      }
    }
    .padding(4)
    .border(set: .single)
  }
}
