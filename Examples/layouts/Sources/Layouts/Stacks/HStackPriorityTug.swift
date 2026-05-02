import SwiftTUI

/// An HStack of three children whose middle child has
/// `layoutPriority(1)` while the outer two default to priority `0`.
/// Under a tight width proposal the priority-1 child keeps its full
/// text while the outer two give way first.
///
/// The outer children use a distinctively long string ("aaaaaaaaaaaa"
/// / "bbbbbbbbbbbb") so truncation is visible in the raster. The
/// middle child uses `"keep"` — short enough that a tight proposal
/// can still honour it in full.
///
/// The header `"HStack priority tug"` is the catalog marker. Placing
/// it in its own row keeps the priority-tug assertions isolated from
/// the header text.
public struct HStackPriorityTug: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("HStack priority tug").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("aaaaaaaaaaaa").layoutPriority(0)
        Text("keep").layoutPriority(1)
        Text("bbbbbbbbbbbb").layoutPriority(0)
      }
    }
  }
}
