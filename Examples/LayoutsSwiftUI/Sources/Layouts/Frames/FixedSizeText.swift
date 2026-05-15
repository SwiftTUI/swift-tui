import SwiftUI

/// Pairs a narrow `.frame(width: 10)` with a `.fixedSize()` modifier on
/// a single Text child. The fixed-size modifier asks the view to use
/// its own intrinsic size instead of honouring the parent's proposal,
/// so the long marker `"thelongerstring"` renders at its intrinsic
/// 15-cell width even inside a 10-cell-wide frame.
///
/// The contrast case (the same text without `.fixedSize()`) sits
/// directly above so the behaviour difference is visible: the plain
/// copy is either wrapped or truncated by the 10-wide frame, while the
/// fixed-size copy escapes the frame in full.
///
/// The header `"FixedSize text"` is the catalog marker.
public struct FixedSizeText: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("FixedSize text").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: cell(1)) {
        Text("without .fixedSize():").foregroundStyle(.secondary)
        Text("thelongerstring")
          .frame(width: cell(10))
          .border(Color.gray)
        Text("with .fixedSize():").foregroundStyle(.secondary)
        Text("thelongerstring")
          .fixedSize()
          .frame(width: cell(10))
          .border(Color.gray)
      }
    }
    .padding(cell(1))
  }
}
