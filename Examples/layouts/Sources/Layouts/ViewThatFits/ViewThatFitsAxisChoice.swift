import SwiftTUIRuntime

/// Three side-by-side `ViewThatFits` containers, each fed a different
/// outer width via `.frame(width:)`. The candidate set is the same for
/// all three (long → medium → short); only the proposal width changes.
///
/// SwiftUI semantics: `ViewThatFits` measures each candidate against
/// the proposal in declaration order and picks the FIRST that fits.
/// At a generous 60-cell proposal the long candidate fits and is
/// chosen; at 12 cells the long no longer fits, the medium does, so
/// medium wins; at 4 cells only the single-character short candidate
/// fits.
///
/// Layout shape:
///
/// ```
/// VStack(alignment: .leading, spacing: 1) {
///   Text("View that fits axis choice")
///   Text("at width 60:")
///   ViewThatFits { Text("[LONG: ...]"); Text("[MEDIUM]"); Text("[S]") }.frame(width: 60).border(.separator)
///   Text("at width 12:")
///   ViewThatFits { same... }.frame(width: 12).border(.separator)
///   Text("at width 4:")
///   ViewThatFits { same... }.frame(width: 4).border(.separator)
/// }
/// ```
///
/// The header `"View that fits axis choice"` is the catalog marker.
public struct ViewThatFitsAxisChoice: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("View that fits axis choice")
      Group {
        Text("at width 60:").foregroundStyle(.muted)
        ViewThatFits {
          Text("[LONG: a long candidate]")
          Text("[MEDIUM]")
          Text("[S]")
        }
        .frame(width: 60)
        .border(.separator)

        Text("at width 12:").foregroundStyle(.muted)
        ViewThatFits {
          Text("[LONG: a long candidate]")
          Text("[MEDIUM]")
          Text("[S]")
        }
        .frame(width: 12)
        .border(.separator)

        Text("at width 4:").foregroundStyle(.muted)
        ViewThatFits {
          Text("[LONG: a long candidate]")
          Text("[MEDIUM]")
          Text("[S]")
        }
        .frame(width: 4)
        .border(.separator)
      }
    }
    .padding(1)
  }
}
