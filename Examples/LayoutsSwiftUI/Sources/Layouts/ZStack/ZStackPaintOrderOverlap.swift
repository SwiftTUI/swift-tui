import SwiftUI

/// Pins the ZStack paint-order rule: children paint in declared order,
/// so a later child paints OVER an earlier child at any shared cell.
///
/// Two same-size `Rectangle`s are stacked — a red fill first, a blue
/// fill second.  Both frames are `10 × 4`, so they overlap on every
/// cell of the 10×4 box.  The behaviour test samples a cell inside
/// the shared region and asserts its `style?.backgroundColor` is
/// `Color.blue`, proving the blue (later) child won over red.
///
/// The header `"ZStack paint order overlap"` is the catalog marker
/// and sits above the stack so it never collides with the sampled
/// region.
public struct ZStackPaintOrderOverlap: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("ZStack paint order overlap").foregroundStyle(.secondary)
      ZStack {
        Rectangle().fill(Color.red).frame(width: 10, height: 4)
        Rectangle().fill(Color.blue).frame(width: 10, height: 4)
      }
    }
    .padding(1)
  }
}
