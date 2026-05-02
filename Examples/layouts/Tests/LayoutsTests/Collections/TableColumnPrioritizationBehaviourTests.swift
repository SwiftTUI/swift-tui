import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant: same outer header but the `Table` is removed
/// entirely. Without the table, none of the cell markers (`[A1]`,
/// `[B1]`, `[C1]`, `[D1]`) appear in the raster — so the "all 4
/// markers visible" invariant must FAIL when this variant is
/// rendered.
@MainActor
private struct TableColumnPrioritizationNoTableVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Table column prioritization").foregroundStyle(.muted)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct TableColumnPrioritizationBehaviourTests {
  /// Observed raster (50×14 viewport):
  ///
  /// ```
  /// [1] | Table column prioritization|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [3] | ▌╭──────┬──────┬──────┬──────╮ ▐|
  /// [4] | ▌│ A    │ B    │ C    │ D    │ ▐|
  /// [5] | ▌├──────┼──────┼──────┼──────┤ ▐|
  /// [6] | ▌│ [A1] │ [B1] │ [C1] │ [D1] │ ▐|
  /// [7] | ▌├──────┼──────┼──────┼──────┤ ▐|
  /// [8] | ▌│ [A2] │ [B2] │ [C2] │ [D2] │ ▐|
  /// [9] | ▌╰──────┴──────┴──────┴──────╯ ▐|
  /// [10]| ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// Invariant: under the narrow `.frame(width: 30)` proposal the
  /// table still paints all four columns — every first-row cell
  /// marker (`[A1]`, `[B1]`, `[C1]`, `[D1]`) appears in the
  /// raster. Specific compression order is library-dependent so
  /// the test only pins that all four columns survive narrow
  /// proposal, not how residual space is distributed.
  @Test("all four cell markers appear under narrow frame proposal")
  func allColumnsSurviveNarrowProposal() {
    let raster = render(TableColumnPrioritization(), width: 50, height: 14).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    for marker in ["[A1]", "[B1]", "[C1]", "[D1]"] {
      #expect(
        raster.firstRow(containing: marker) != nil,
        "expected `\(marker)` to be painted somewhere in the raster\n\(joined)"
      )
    }
  }

  /// A/B vacuity: removing the `Table` from the layout means none
  /// of the cell markers can appear. Pin that the canonical
  /// layout paints all four markers AND the no-table variant
  /// paints none; if the variant ever paints any of `[A1]`,
  /// `[B1]`, `[C1]`, `[D1]` the A/B is no longer a valid vacuity
  /// check.
  @Test("removing the Table hides every cell marker")
  func tableMarkersAreNonVacuous() {
    let withTable = render(
      TableColumnPrioritization(),
      width: 50,
      height: 14,
      id: "with-table"
    ).rasterSurface
    let withoutTable = render(
      TableColumnPrioritizationNoTableVariant(),
      width: 50,
      height: 14,
      id: "without-table"
    ).rasterSurface

    let withDump = withTable.lines.joined(separator: "\n")
    let withoutDump = withoutTable.lines.joined(separator: "\n")

    let markers = ["[A1]", "[B1]", "[C1]", "[D1]"]

    // WITH-table: every marker present.
    for marker in markers {
      #expect(
        withTable.firstRow(containing: marker) != nil,
        "WITH-table expected `\(marker)` present\n\(withDump)"
      )
    }
    // WITHOUT-table: every marker absent.
    for marker in markers {
      #expect(
        withoutTable.firstRow(containing: marker) == nil,
        """
        WITHOUT-table variant expected `\(marker)` absent; if this \
        fails the A/B vacuity check is no longer meaningful.
        \(withoutDump)
        """
      )
    }
  }
}
