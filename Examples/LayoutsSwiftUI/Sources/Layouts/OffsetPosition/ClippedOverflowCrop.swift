import SwiftUI

/// Demonstrates that `.clipped()` crops content that paints past the
/// modified view's measured frame.  A `Text("aaaa…")` (16 cells of `a`)
/// is constrained to `.frame(width: 8, height: 1)` — the text's
/// intrinsic painting would overflow 8 cells to the right, but
/// `.clipped()` trims every cell past the 8-cell frame so columns
/// 8..15 of the row stay blank.
///
/// The header `"Clipped overflow crop"` is the catalog marker on its
/// own row; the clipped row sits below it.
public struct ClippedOverflowCrop: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("Clipped overflow crop").foregroundStyle(.secondary)
      Text("aaaaaaaaaaaaaaaa")
        .fixedSize()
        .frame(width: cell(8), height: cell(1))
        .clipped()
    }
    .padding(cell(1))
  }
}
