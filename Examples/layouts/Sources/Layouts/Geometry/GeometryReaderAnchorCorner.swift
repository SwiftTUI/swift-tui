import TerminalUI

/// Uses `GeometryReader`'s `proxy.size` to anchor a `[X]` marker at
/// the top-right corner of the reader's frame via `.position`.
///
/// SwiftUI semantics: with a `.frame(width: 40, height: 5)` wrapping
/// the reader, `proxy.size.width` would equal 40 and `[X]` would land
/// near column 40 − 2 = 38 (centered there by `.position`).
///
/// Per `BEHAVIOUR_FINDINGS.md` finding #4 the proxy currently reports
/// the full terminal width, so `[X]` anchors at `(terminalWidth − 2,
/// 0)` — well outside the 40-wide frame.  The behaviour test pins
/// whatever lands in the raster.
///
/// The header `"Geometry reader anchor corner"` is the catalog marker.
public struct GeometryReaderAnchorCorner: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader anchor corner").foregroundStyle(.muted)
      GeometryReader { proxy in
        Text("[X]").position(x: proxy.size.width - 2, y: 0)
      }
      .frame(width: 40, height: 5)
      .border(.separator)
    }
    .padding(1)
  }
}
