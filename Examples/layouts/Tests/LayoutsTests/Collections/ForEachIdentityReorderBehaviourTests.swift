import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape but the second `ForEach` block
/// uses the SAME order as the first (`[apple]`, `[banana]`,
/// `[cherry]`). Reusing the same order in both blocks means there
/// is no reorder-driven difference, so the "B reverses A" invariant
/// must FAIL when this variant is rendered.
@MainActor
private struct ForEachIdentityReorderSameOrderVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("For each identity reorder").foregroundStyle(.muted)
      Text("order A").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["[apple]", "[banana]", "[cherry]"], id: \.self) { item in
          Text(item)
        }
      }
      .border(.separator)
      Text("order B (reversed)").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["[apple]", "[banana]", "[cherry]"], id: \.self) { item in
          Text(item)
        }
      }
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ForEachIdentityReorderBehaviourTests {
  /// Observed raster (40×20 viewport):
  ///
  /// ```
  /// [1] | For each identity reorder|
  /// [3] | order A|
  /// [5] | ▛▀▀▀▀▀▀▀▀▜|
  /// [6] | ▌[apple] ▐|
  /// [7] | ▌[banana]▐|
  /// [8] | ▌[cherry]▐|
  /// [9] | ▙▄▄▄▄▄▄▄▄▟|
  /// [11]| order B (reversed)|
  /// [13]| ▛▀▀▀▀▀▀▀▀▜|
  /// [14]| ▌[cherry]▐|
  /// [15]| ▌[banana]▐|
  /// [16]| ▌[apple] ▐|
  /// [17]| ▙▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// Three invariants pinned together:
  ///   - All three items appear at least twice (once per ordering
  ///     block).
  ///   - In the FIRST (top) block, `[apple]` is on a row above
  ///     `[banana]` is above `[cherry]`.
  ///   - In the SECOND (bottom) block, the order is reversed:
  ///     `[cherry]` is above `[banana]` is above `[apple]`.
  @Test("order A is apple/banana/cherry; order B is cherry/banana/apple")
  func reorderProducesReversedRowOrder() {
    let raster = render(ForEachIdentityReorder(), width: 40, height: 20).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let appleRows = raster.rows(containing: "[apple]")
    let bananaRows = raster.rows(containing: "[banana]")
    let cherryRows = raster.rows(containing: "[cherry]")

    #expect(
      appleRows.count == 2 && bananaRows.count == 2 && cherryRows.count == 2,
      """
      expected each item to appear in both ordering blocks; got \
      apple=\(appleRows), banana=\(bananaRows), cherry=\(cherryRows)
      \(joined)
      """
    )

    guard appleRows.count == 2, bananaRows.count == 2, cherryRows.count == 2 else {
      return
    }

    // Order A (top block): apple < banana < cherry by row index.
    let appleA = appleRows[0]
    let bananaA = bananaRows[0]
    let cherryA = cherryRows[0]
    #expect(
      appleA < bananaA && bananaA < cherryA,
      """
      order A expected apple < banana < cherry; got \
      apple=\(appleA), banana=\(bananaA), cherry=\(cherryA)
      \(joined)
      """
    )

    // Order B (bottom block): cherry < banana < apple by row
    // index (reversed).
    let appleB = appleRows[1]
    let bananaB = bananaRows[1]
    let cherryB = cherryRows[1]
    #expect(
      cherryB < bananaB && bananaB < appleB,
      """
      order B expected cherry < banana < apple; got \
      cherry=\(cherryB), banana=\(bananaB), apple=\(appleB)
      \(joined)
      """
    )
  }

  /// A/B vacuity: when both ordering blocks use the SAME order,
  /// the second block is not the reverse of the first — so the
  /// reverse-order assertion must NOT hold for the variant. Pin
  /// that the canonical layout shows reversed order AND the
  /// same-order variant does not; if the variant ever flips order
  /// the A/B is no longer a valid vacuity check.
  @Test("re-using the same order in both blocks breaks the reverse invariant")
  func reorderIsNonVacuous() {
    let canonical = render(
      ForEachIdentityReorder(),
      width: 40,
      height: 20,
      id: "canonical"
    ).rasterSurface
    let sameOrder = render(
      ForEachIdentityReorderSameOrderVariant(),
      width: 40,
      height: 20,
      id: "same-order"
    ).rasterSurface

    let canonicalDump = canonical.lines.joined(separator: "\n")
    let sameDump = sameOrder.lines.joined(separator: "\n")

    func reversedInSecondBlock(_ raster: RasterSurface) -> Bool? {
      let appleRows = raster.rows(containing: "[apple]")
      let bananaRows = raster.rows(containing: "[banana]")
      let cherryRows = raster.rows(containing: "[cherry]")
      guard appleRows.count == 2, bananaRows.count == 2, cherryRows.count == 2 else {
        return nil
      }
      // Second occurrence row indices (the bottom block).
      return cherryRows[1] < bananaRows[1] && bananaRows[1] < appleRows[1]
    }

    guard let canonicalReversed = reversedInSecondBlock(canonical) else {
      Issue.record("canonical raster missing one or more items:\n\(canonicalDump)")
      return
    }
    guard let sameReversed = reversedInSecondBlock(sameOrder) else {
      Issue.record("same-order raster missing one or more items:\n\(sameDump)")
      return
    }

    // CANONICAL: second block must be reversed (cherry < banana < apple).
    #expect(
      canonicalReversed,
      "canonical expected second block to be reversed; got\n\(canonicalDump)"
    )
    // SAME-ORDER variant: second block must NOT be reversed.
    #expect(
      !sameReversed,
      """
      SAME-ORDER variant expected second block to NOT be reversed; \
      if this fails the A/B vacuity check is no longer meaningful.
      \(sameDump)
      """
    )
  }
}
