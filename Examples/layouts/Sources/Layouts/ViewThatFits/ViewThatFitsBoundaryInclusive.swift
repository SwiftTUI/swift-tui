import SwiftTUI

/// Two side-by-side `ViewThatFits` containers whose first candidate
/// (`Text("HELLO")`, 5 cells wide) sits exactly on the boundary of one
/// proposal (`.frame(width: 5)`) and just past it in the other
/// (`.frame(width: 4)`).
///
/// This layout pins the boundary semantics of the library's
/// `ViewThatFits` selector: at proposal width N, does a candidate of
/// intrinsic width N count as "fits" (inclusive) or "does not fit"
/// (exclusive)?
///
/// The library's `LayoutEngine.fits(_:within:)` uses `value <= limit`,
/// so the inclusive case applies: at width 5 the 5-cell `HELLO`
/// candidate fits and is chosen. At width 4 it no longer fits and the
/// fallback `Text("HI")` (2 cells) is chosen.
///
/// Layout shape:
///
/// ```
/// HStack(spacing: 4) {
///   VStack { Text("at width 5:"); ViewThatFits { "HELLO"; "HI" }.frame(width: 5).border(.separator) }
///   VStack { Text("at width 4:"); ViewThatFits { "HELLO"; "HI" }.frame(width: 4).border(.separator) }
/// }
/// ```
///
/// The header `"View that fits boundary inclusive"` is the catalog
/// marker.
public struct ViewThatFitsBoundaryInclusive: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("View that fits boundary inclusive")
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 0) {
          Text("at width 5:").foregroundStyle(.muted)
          ViewThatFits {
            Text("HELLO")
            Text("HI")
          }
          .frame(width: 5)
          .border(.separator)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("at width 4:").foregroundStyle(.muted)
          ViewThatFits {
            Text("HELLO")
            Text("HI")
          }
          .frame(width: 4)
          .border(.separator)
        }
      }
    }
    .padding(1)
  }
}
