import SwiftUI

/// Two `Capsule`s drawn side-by-side, demonstrating that the rounded
/// ends snap to the **shorter axis** of the frame.
///
/// The left capsule has a wide 20×3 frame: short axis is the height,
/// so the left/right ends are rounded (semicircular caps) and the
/// middle is a horizontal pill. The right capsule has a tall 3×20
/// frame: short axis is the width, so the top/bottom ends are rounded
/// and the middle is a vertical pill.
///
/// Layout shape: `VStack(alignment: .leading)` header + an
/// `HStack(alignment: .top, spacing: 4)` with two `Capsule().fill(...)`
/// children at flipped frame sizes.
///
/// Observable invariants pinned by the behaviour test:
///   - The wide blue capsule paints across roughly 3 rows of the
///     viewport (its 20×3 frame).
///   - The tall green capsule paints across roughly 20 rows (its 3×20
///     frame). The ratio of "blue rows" to "green rows" is the cheap
///     proxy for "axis flipped" — the wide capsule is short-and-wide,
///     the tall capsule is narrow-and-tall.
public struct CapsuleAxisFlip: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("Capsule axis flip").foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: cell(4)) {
        Capsule().fill(Color.blue).frame(width: cell(20), height: cell(3))
        Capsule().fill(Color.green).frame(width: cell(3), height: cell(20))
      }
    }
    .padding(cell(1))
  }
}
