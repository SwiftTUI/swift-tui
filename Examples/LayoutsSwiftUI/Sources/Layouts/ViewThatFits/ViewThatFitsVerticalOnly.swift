import SwiftUI

/// Three side-by-side `ViewThatFits(in: .vertical)` containers, each
/// fed a different outer height via `.frame(height:)`.  The candidate
/// set (TALL3 = 3 rows, MED2 = 2 rows, SHORT1 = 1 row) is the same for
/// all three; only the proposal HEIGHT changes.
///
/// SwiftUI semantics for `ViewThatFits(in: .vertical)`: the container
/// only fits-checks the VERTICAL axis. Horizontal width is not part of
/// the fit decision. Candidates are tried in declaration order; the
/// first whose vertical extent fits the proposal is chosen.
///
/// Expected picks under per-container heights:
///
///   - height 5 → `[TALL3]` row (3 lines, fits in 5)
///   - height 2 → `[MED2]` row  (2 lines, fits in 2; TALL3 does not)
///   - height 1 → `[SHORT1]`    (1 line, fits in 1; MED2 does not)
///
/// All three containers are stacked top-to-bottom in an outer
/// `VStack`; the chosen rows must therefore appear in declaration
/// order (TALL3 before MED2 before SHORT1) in the raster.
///
/// The header `"View that fits vertical only"` is the catalog marker.
public struct ViewThatFitsVerticalOnly: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("View that fits vertical only")

      Text("at height 5:").foregroundStyle(.secondary)
      ViewThatFits(in: .vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("[TALL3]")
          Text("[TALL3]")
          Text("[TALL3]")
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("[MED2]")
          Text("[MED2]")
        }
        Text("[SHORT1]")
      }
      .frame(width: cell(12), height: cell(5))
      .border(Color.gray)

      Text("at height 2:").foregroundStyle(.secondary)
      ViewThatFits(in: .vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("[TALL3]")
          Text("[TALL3]")
          Text("[TALL3]")
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("[MED2]")
          Text("[MED2]")
        }
        Text("[SHORT1]")
      }
      .frame(width: cell(12), height: cell(2))
      .border(Color.gray)

      Text("at height 1:").foregroundStyle(.secondary)
      ViewThatFits(in: .vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("[TALL3]")
          Text("[TALL3]")
          Text("[TALL3]")
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("[MED2]")
          Text("[MED2]")
        }
        Text("[SHORT1]")
      }
      .frame(width: cell(12), height: cell(1))
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}
