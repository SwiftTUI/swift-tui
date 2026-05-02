import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct NegativeOffsetEscapeBehaviourTests {
  /// A/B comparison: render the layout with `.offset(x: -2)` (the
  /// canonical `NegativeOffsetEscape`) AND a copy without the offset
  /// modifier.  The `[ESC]` glyph in the WITH-offset variant must
  /// appear two cells to the LEFT of where it appears in the
  /// WITHOUT-offset variant.
  ///
  /// This pins two facts at once:
  ///   1. Negative offsets translate the painted child leftward.
  ///   2. The shift is exactly the offset value (2 cells), not
  ///      clamped to the parent frame's left edge.
  @Test(".offset(x: -2) paints exactly 2 cells left of natural position")
  func negativeOffsetShiftsPaintLeft() {
    let withOffset = render(
      NegativeOffsetEscape(),
      width: 40,
      height: 10,
      id: "with-offset"
    ).rasterSurface
    let withoutOffset = render(
      WithoutOffsetVariant(),
      width: 40,
      height: 10,
      id: "without-offset"
    ).rasterSurface

    let withDump = withOffset.lines.joined(separator: "\n")
    let withoutDump = withoutOffset.lines.joined(separator: "\n")

    guard let rowWith = withOffset.firstRow(containing: "[ESC]"),
      let lineWith = withOffset.row(at: rowWith),
      let colWith = column(of: "[ESC]", in: lineWith)
    else {
      Issue.record("WITH-offset variant: missing [ESC]\nWITH:\n\(withDump)")
      return
    }

    guard let rowWithout = withoutOffset.firstRow(containing: "[ESC]"),
      let lineWithout = withoutOffset.row(at: rowWithout),
      let colWithout = column(of: "[ESC]", in: lineWithout)
    else {
      Issue.record("WITHOUT-offset variant: missing [ESC]\nWITHOUT:\n\(withoutDump)")
      return
    }

    // Same row in both variants — offset is x-only.
    #expect(
      rowWith == rowWithout,
      "expected same row in both variants; with=\(rowWith) without=\(rowWithout)"
    )

    // [ESC] paints LEFT of natural position.
    #expect(
      colWith < colWithout,
      "expected [ESC] with .offset(x:-2) to paint at smaller column than without offset; got with=\(colWith) without=\(colWithout)\nWITH:\n\(withDump)\nWITHOUT:\n\(withoutDump)"
    )

    // The shift is exactly 2 cells.
    #expect(
      colWithout - colWith == 2,
      "expected exactly a 2-cell shift; got with=\(colWith) without=\(colWithout) diff=\(colWithout - colWith)\nWITH:\n\(withDump)\nWITHOUT:\n\(withoutDump)"
    )
  }
}

/// Identical to `NegativeOffsetEscape` except `[ESC]` carries no
/// `.offset(x:)`. Used by the A/B comparison above. The spacer uses
/// ASCII `#` glyphs (1 cell each) so character indices match cell
/// columns for the column-comparison assertions.
private struct WithoutOffsetVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Negative offset escape").foregroundStyle(.muted)
      HStack(spacing: 0) {
        Text("#####").frame(width: 5, height: 1)
        Text("[ESC]")
      }
    }
    .padding(4)
    .border(set: .single)
  }
}
