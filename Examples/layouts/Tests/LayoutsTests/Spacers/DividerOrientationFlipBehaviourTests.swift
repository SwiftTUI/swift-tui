import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct DividerOrientationFlipBehaviourTests {
  /// Snapshot the entire raster so the orientation invariant is
  /// debuggable when it ever drifts. The test below pins the actual
  /// glyph and placement assertions; this case keeps the raw layout
  /// near the assertions in source for review-time orientation.
  @Test("Raster contains both panels and both row/column markers")
  func rasterShowsBothPanels() {
    let raster = render(DividerOrientationFlip(), width: 60, height: 8).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    for marker in ["V-1", "V-2", "H-1", "H-2"] {
      #expect(
        joined.contains(marker),
        "expected `\(marker)` somewhere in the raster\n\(joined)"
      )
    }
  }

  /// In the LEFT panel (`VStack`), `Divider()` draws a HORIZONTAL
  /// rule whose glyph is `─` (the default `.single` border set's top
  /// edge, used for stroke painting via `BorderGlyphSet.horizontal`).
  ///
  /// Pin: a row of `─` glyphs sits BETWEEN the row containing `V-1`
  /// and the row containing `V-2`.
  @Test("VStack divider draws a horizontal rule between V-1 and V-2 rows")
  func vstackDividerIsHorizontalRule() {
    let raster = render(DividerOrientationFlip(), width: 60, height: 8).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let v1Row = raster.firstRow(containing: "V-1"),
      let v2Row = raster.firstRow(containing: "V-2")
    else {
      Issue.record("expected `V-1` and `V-2` rows present\n\(joined)")
      return
    }

    #expect(
      v2Row > v1Row,
      "expected V-2 below V-1; got V-1 row=\(v1Row), V-2 row=\(v2Row)\n\(joined)"
    )

    // Find a row strictly between V-1 and V-2 that contains `─`.
    var foundHorizontalRuleRow: Int? = nil
    for row in (v1Row + 1)..<v2Row {
      if let line = raster.row(at: row), line.contains("─") {
        foundHorizontalRuleRow = row
        break
      }
    }

    #expect(
      foundHorizontalRuleRow != nil,
      """
      expected a horizontal-rule row (containing `─`) between V-1 \
      (row \(v1Row)) and V-2 (row \(v2Row))
      \(joined)
      """
    )
  }

  /// In the RIGHT panel (`HStack`), `Divider()` draws a VERTICAL rule
  /// whose glyph is `│` (the default `.single` border set's left edge,
  /// used for stroke painting via `BorderGlyphSet.vertical`).
  ///
  /// Pin: on the row carrying `H-1` and `H-2`, a `│` glyph sits at a
  /// column STRICTLY BETWEEN the columns of `H-1` and `H-2`.
  @Test("HStack divider draws a vertical rule between H-1 and H-2 cells")
  func hstackDividerIsVerticalRule() {
    let raster = render(DividerOrientationFlip(), width: 60, height: 8).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let row = raster.firstRow(containing: "H-1"),
      let line = raster.row(at: row),
      let colH1 = column(of: "H-1", in: line),
      let colH2 = column(of: "H-2", in: line)
    else {
      Issue.record("expected `H-1` and `H-2` on the same row\n\(joined)")
      return
    }

    #expect(
      colH1 < colH2,
      "expected H-1 (col=\(colH1)) left of H-2 (col=\(colH2))\nrow: '\(line)'"
    )

    // `H-1` is 3 cells wide; the vertical rule must sit AFTER the
    // last cell of H-1 (`colH1 + 3`) and BEFORE the first cell of H-2
    // (`colH2`).
    let chars = Array(line)
    let searchStart = colH1 + 3
    let searchEnd = colH2  // exclusive
    var foundVerticalRuleCol: Int? = nil
    if searchStart < searchEnd {
      for col in searchStart..<searchEnd where chars[col] == "│" {
        foundVerticalRuleCol = col
        break
      }
    }

    #expect(
      foundVerticalRuleCol != nil,
      """
      expected a vertical-rule glyph (`│`) between H-1 (col \(colH1)) \
      and H-2 (col \(colH2)) on the H-row
      row: '\(line)'
      """
    )
  }
}
