import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct LayoutPriorityCascadeBehaviourTests {
  /// At a generous width (40) every child fits, so all four markers
  /// appear in full somewhere in the raster. Markers are header-proof
  /// (`"K"`, `"Z"`, `"XXXXXXXXXXXX"`, `"YYYYYYYYYYYY"` share no
  /// characters with `"Layout priority cascade"`), so a positive
  /// match cannot be satisfied by the header row.
  @Test("At width 40 all four cascade children fit in full")
  func wideProposalLetsAllSurvive() {
    let raster = render(LayoutPriorityCascade(), width: 40, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("XXXXXXXXXXXX"),
      "width 40: priority-0 'XXXXXXXXXXXX' should appear in full\n\(joined)"
    )
    #expect(
      joined.contains("K"),
      "width 40: priority-1 'K' should appear\n\(joined)"
    )
    #expect(
      joined.contains("YYYYYYYYYYYY"),
      "width 40: priority-0 'YYYYYYYYYYYY' should appear in full\n\(joined)"
    )
    #expect(
      joined.contains("Z"),
      "width 40: priority-2 'Z' should appear\n\(joined)"
    )

    // The two priority markers must share the HStack row as each
    // other — not merely "appear somewhere" (defends against any
    // future header change that might reintroduce the false-green).
    let kRows = raster.rows(containing: "K")
    let zRows = raster.rows(containing: "Z")
    let sharedRow = Set(kRows).intersection(Set(zRows))
    #expect(
      !sharedRow.isEmpty,
      "width 40: 'K' rows \(kRows) and 'Z' rows \(zRows) should share at least one row\n\(joined)"
    )
  }

  /// At a tight width (12) the priority-2 child (`"Z"`) must survive
  /// intact and the priority-1 child (`"K"`) should also survive —
  /// the cascade shaves the two priority-0 strings first. Both
  /// priority siblings must land on the same HStack row as each other
  /// (the HStack only has one row).
  @Test("At width 12 priority-1 'K' and priority-2 'Z' both survive")
  func tightProposalKeepsHighPriorityChildren() {
    let raster = render(LayoutPriorityCascade(), width: 12, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let kRows = raster.rows(containing: "K")
    let zRows = raster.rows(containing: "Z")

    #expect(
      !kRows.isEmpty,
      "width 12: priority-1 'K' should survive intact\n\(joined)"
    )
    #expect(
      !zRows.isEmpty,
      "width 12: priority-2 'Z' should survive intact\n\(joined)"
    )

    // Both survive on the same HStack row.
    let sharedRow = Set(kRows).intersection(Set(zRows))
    #expect(
      !sharedRow.isEmpty,
      "width 12: 'K' rows \(kRows) and 'Z' rows \(zRows) should share at least one row\n\(joined)"
    )

    // Both low-priority strings cannot possibly fit in full at width 12.
    let xFull = joined.contains("XXXXXXXXXXXX")
    let yFull = joined.contains("YYYYYYYYYYYY")
    #expect(
      !(xFull && yFull),
      "width 12: both priority-0 markers cannot fit in full; at least one should truncate\n\(joined)"
    )
  }
}
