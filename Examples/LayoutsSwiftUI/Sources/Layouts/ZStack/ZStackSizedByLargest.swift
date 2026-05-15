import SwiftUI

/// Pins the ZStack sizing rule: the stack reports a size equal to the
/// largest child's measured size along each axis.  A tiny `Text("·")`
/// sized `3 × 1` is stacked over a `Rectangle().fill(Color.gray)` sized
/// `30 × 10`; the ZStack's footprint — proven by the region of
/// gray-filled raster cells — is `30 × 10`, not the small child's size.
///
/// The header `"ZStack sized by largest"` is the catalog marker.
public struct ZStackSizedByLargest: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("ZStack sized by largest").foregroundStyle(.secondary)
      ZStack {
        Text("·").frame(width: cell(3), height: cell(1))
        Rectangle().fill(Color.gray).frame(width: cell(30), height: cell(10))
      }
    }
    .padding(cell(1))
  }
}
