import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct HStackPriorityTugBehaviourTests {
  /// At a generous width all three children fit; the low-priority
  /// "aaaaaaaaaaaa" and high-priority "keep" both appear in full.
  @Test("At width 40 all three children fit in full")
  func wideProposalLetsAllSurvive() {
    let raster = render(HStackPriorityTug(), width: 40, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("aaaaaaaaaaaa"),
      "width 40: low-priority 'aaaaaaaaaaaa' should appear in full\n\(joined)"
    )
    #expect(
      joined.contains("keep"),
      "width 40: priority-1 'keep' should appear\n\(joined)"
    )
    #expect(
      joined.contains("bbbbbbbbbbbb"),
      "width 40: low-priority 'bbbbbbbbbbbb' should appear in full\n\(joined)"
    )
  }

  /// At a tight width (16) the priority-1 "keep" child must survive
  /// intact — this is the strong invariant of `.layoutPriority`. The
  /// outer low-priority children must give way first; the exact
  /// truncation rule is library-defined but at minimum neither
  /// low-priority marker should survive in its full form at this
  /// width because their full lengths (12 each) + "keep" (4) + 2
  /// spacing cells = 30, which cannot fit in 16 cells.
  @Test("At width 16 the priority-1 child survives intact")
  func tightProposalKeepsPriorityChild() {
    let raster = render(HStackPriorityTug(), width: 16, height: 6).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      joined.contains("keep"),
      "width 16: priority-1 'keep' should survive intact\n\(joined)"
    )

    let aFull = joined.contains("aaaaaaaaaaaa")
    let bFull = joined.contains("bbbbbbbbbbbb")
    #expect(
      !(aFull && bFull),
      "width 16: both low-priority markers cannot fit in full; at least one should truncate\n\(joined)"
    )
  }
}
