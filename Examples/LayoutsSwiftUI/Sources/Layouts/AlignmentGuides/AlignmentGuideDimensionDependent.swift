import SwiftUI

/// Three boxed children of mixed heights (1/2/3 content rows)
/// inside an `HStack(alignment: .bottom)`. The HStack pulls each
/// child's `.bottom` guide to a common raster row, so the bottom
/// borders of the three boxes coincide.
///
/// The `.bottom` alignment guide's default value is the child's
/// height (see `Sources/Core/GeometryTypes.swift`'s
/// `BottomAlignmentID.defaultValue`), i.e. `{ d in d.height }`. The
/// effective layout is therefore equivalent to writing
/// `.alignmentGuide(.bottom) { d in d.height }` on every child —
/// the canonical "dimension-dependent guide" form. This layout pins
/// that equivalence: the default `.bottom` guide IS a
/// dimension-dependent guide.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading) {
///   Text("Alignment guide dimension dependent")
///   HStack(alignment: .bottom, spacing: 2) {
///     Text("[A]")            .border(Color.gray)
///     Text("[B]\n[B]")       .border(Color.gray)
///     Text("[C]\n[C]\n[C]")  .border(Color.gray)
///   }
///   .border(Color.gray)
/// }
/// ```
///
/// The catalog marker `"Alignment guide dimension dependent"` is
/// the first row.
public struct AlignmentGuideDimensionDependent: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("Alignment guide dimension dependent").foregroundStyle(.secondary)
      HStack(alignment: .bottom, spacing: cell(2)) {
        Text("[A]").border(Color.gray)
        Text("[B]\n[B]").border(Color.gray)
        Text("[C]\n[C]\n[C]").border(Color.gray)
      }
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}
