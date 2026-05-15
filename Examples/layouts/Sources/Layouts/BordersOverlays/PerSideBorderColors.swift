import SwiftTUIRuntime

/// A single bordered box with each of the four sides painted a
/// different color via
/// `BorderEdgeStyle(top:right:bottom:left:)`. The `.heavy` border set
/// renders with `━ ┃ ┏ ┓ ┗ ┛` glyphs; each edge's glyphs carry their
/// own per-edge color. This pins that the 4-color edge-style overload
/// is threaded through the rasterizer and paints distinct foreground
/// colors per side.
///
/// The header `"Per-side border colors"` is the catalog marker.
public struct PerSideBorderColors: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Per-side border colors").foregroundStyle(.muted)
      Text("X")
        .padding(2)
        .border(
          BorderEdgeStyle(top: .red, right: .yellow, bottom: .green, left: .blue),
          set: .heavy
        )
    }
    .padding(1)
  }
}
