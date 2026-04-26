import SwiftUI

/// Three fixed-width `Text` children inside an `HStack(spacing: 0)` where
/// the middle child carries `.offset(x: 6)`.  The offset is a PAINT-ONLY
/// translation in SwiftUI's model: the HStack still lays the middle child
/// out at its natural position, so the third child sits immediately
/// after the middle child's MEASURED (un-offset) frame.  The third
/// child's column therefore equals `A.width + B.width = 3 + 3 = 6`
/// rather than `3 + 3 + 6 = 12`.
///
/// The header `"Offset preserves measured size"` is the catalog marker.
public struct OffsetPreservesMeasuredSize: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Offset preserves measured size").foregroundStyle(.secondary)
      HStack(spacing: 0) {
        Text("[A]").frame(width: 3)
        Text("[B]").frame(width: 3).offset(x: 6)
        Text("[C]").frame(width: 3)
      }
    }
    .padding(1)
  }
}
