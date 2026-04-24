import TerminalUI

/// Demonstrates that `.position(x:y:)` anchors the CENTER of its child
/// at an absolute point in the wrapper's coordinate space, ignoring any
/// sibling layout that would otherwise place it.
///
/// A ZStack provides a visible background (a muted-filled `Rectangle`)
/// so the absolute position contrast is obvious; the `[PIN]` label is
/// centered at `(x: 40, y: 14)` on an 80×28 surface (middle of the
/// viewport).
///
/// The header `"Position ignores layout"` is the catalog marker; it
/// lives above the positioned area so the raster row containing `[PIN]`
/// is solely the positioned text.
public struct PositionIgnoresLayout: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Position ignores layout").foregroundStyle(.muted)
      ZStack {
        Rectangle().fill(Color.blue)
        Text("[PIN]").position(x: 40, y: 14)
      }
    }
  }
}
