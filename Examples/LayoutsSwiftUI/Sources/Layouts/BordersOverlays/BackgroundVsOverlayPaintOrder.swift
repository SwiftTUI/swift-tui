import SwiftUI

/// Two side-by-side copies of the same content pin the paint-order
/// contrast between `.background(...)` and `.overlay(...)`:
///
///   - LEFT  (background): `Text("X").background(Color.red)` — the red
///     `Rectangle` paints BEHIND the text, so the `X` glyph remains
///     visible on top of the red fill.
///   - RIGHT (overlay):    `Text("X").overlay(Color.blue ... Rectangle)` —
///     the blue `Rectangle` paints OVER the text, so the `X` glyph is
///     obscured by the overlay fill.
///
/// `.background(Color.red)` uses the `ShapeStyle` convenience overload
/// and internally resolves to `Rectangle().fill(.red)`; overlay has no
/// `ShapeStyle` overload in the library's public surface today, so the
/// right-hand box uses the content-closure form explicitly. The
/// behaviour pin is on paint order, not which overload was used.
///
/// The header `"Background vs overlay paint order"` is the catalog
/// marker.
public struct BackgroundVsOverlayPaintOrder: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Background vs overlay paint order").foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 0) {
          Text("background:").foregroundStyle(.secondary)
          Text("X")
            .frame(width: 3, height: 1)
            .background(Color.red)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("overlay:").foregroundStyle(.secondary)
          Text("X")
            .frame(width: 3, height: 1)
            .overlay {
              Rectangle().fill(Color.blue)
            }
        }
      }
    }
    .padding(1)
  }
}
