import SwiftTUI

/// Demonstrates that `.position(x:y:)` anchors the CENTER of its child
/// at an absolute point in the wrapper's coordinate space, ignoring any
/// sibling layout that would otherwise place it.
///
/// A ZStack provides a visible background (a muted-filled `Rectangle`)
/// so the absolute position contrast is obvious; the `[PIN]` label is
/// anchored at `(x: 60, y: 5)` — an OFF-CENTER point chosen so that
/// removing `.position` produces a visibly different raster (the
/// natural ZStack layout would center `[PIN]` near column 40, row 14).
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
        Text("[PIN]").position(x: 60, y: 5)
      }
    }
  }
}
