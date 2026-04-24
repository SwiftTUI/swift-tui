import TerminalUI

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
      Text("ZStack sized by largest").foregroundStyle(.muted)
      ZStack {
        Text("·").frame(width: 3, height: 1)
        Rectangle().fill(Color.gray).frame(width: 30, height: 10)
      }
    }
    .padding(1)
  }
}
