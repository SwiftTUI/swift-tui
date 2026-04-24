import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct LayoutPriorityCascadeBehaviourTests {
  /// At a generous width (40) every child fits, so all four markers
  /// appear in full somewhere in the raster.
  @Test("At width 40 all four cascade children fit in full")
  func wideProposalLetsAllSurvive() {
    let raster = render(LayoutPriorityCascade(), width: 40, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("aaaaaaaaaa"),
      "width 40: priority-0 'aaaaaaaaaa' should appear in full\n\(joined)"
    )
    #expect(
      joined.contains("b"),
      "width 40: priority-1 'b' should appear\n\(joined)"
    )
    #expect(
      joined.contains("cccccccccc"),
      "width 40: priority-0 'cccccccccc' should appear in full\n\(joined)"
    )
    #expect(
      joined.contains("d"),
      "width 40: priority-2 'd' should appear\n\(joined)"
    )
  }

  /// At a tight width (12) the priority-2 child ("d") must survive
  /// intact and the priority-1 child ("b") should also survive — the
  /// cascade shaves the two priority-0 strings first. Both priority
  /// siblings must land on the same HStack row as each other (the
  /// HStack only has one row).
  @Test("At width 12 priority-1 'b' and priority-2 'd' both survive")
  func tightProposalKeepsHighPriorityChildren() {
    let raster = render(LayoutPriorityCascade(), width: 12, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let bRows = raster.rows(containing: "b")
    let dRows = raster.rows(containing: "d")

    #expect(
      !bRows.isEmpty,
      "width 12: priority-1 'b' should survive intact\n\(joined)"
    )
    #expect(
      !dRows.isEmpty,
      "width 12: priority-2 'd' should survive intact\n\(joined)"
    )

    // Both survive on the same HStack row.
    let sharedRow = Set(bRows).intersection(Set(dRows))
    #expect(
      !sharedRow.isEmpty,
      "width 12: 'b' rows \(bRows) and 'd' rows \(dRows) should share at least one row\n\(joined)"
    )

    // Both low-priority strings cannot possibly fit in full at width 12.
    let aFull = joined.contains("aaaaaaaaaa")
    let cFull = joined.contains("cccccccccc")
    #expect(
      !(aFull && cFull),
      "width 12: both priority-0 markers cannot fit in full; at least one should truncate\n\(joined)"
    )
  }
}
