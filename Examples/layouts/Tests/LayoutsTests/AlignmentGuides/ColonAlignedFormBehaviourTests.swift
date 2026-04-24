import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape and label/value pairs, but the
/// `label:` text has no `.frame(width: 8, alignment: .trailing)`.
/// Without the trailing-aligned fixed-width column the labels start
/// at the row's leading edge, so the four `:` characters sit at
/// different raster columns (one column past the end of each label).
@MainActor
private struct ColonAlignedFormFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Colon aligned form").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        row(label: "name", value: "Alice")
        row(label: "email", value: "alice@example.com")
        row(label: "color", value: "blue")
        row(label: "x", value: "42")
      }
      .border(.separator)
    }
    .padding(1)
  }

  private func row(label: String, value: String) -> some View {
    HStack(spacing: 0) {
      Text("\(label):")
      Text(" \(value)")
    }
  }
}

@MainActor
@Suite
struct ColonAlignedFormBehaviourTests {
  /// Pins that the four `name:` / `email:` / `color:` / `x:` rows
  /// all paint their `:` glyph at the same raster column.
  ///
  /// Observed raster (60×14 viewport, layout has `.padding(1)` and
  /// `.border(.separator)`):
  ///
  /// ```
  /// [1] | Colon aligned form|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [3] | ▌   name: Alice            ▐|
  /// [4] | ▌  email: alice@example.com▐|
  /// [5] | ▌  color: blue             ▐|
  /// [6] | ▌      x: 42               ▐|
  /// [7] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// Each value-row contains exactly one `:` (the colon after the
  /// label) and the value strings deliberately contain no `:`. The
  /// invariant is that the column of the `:` in each row is the
  /// same.
  @Test("All four label colons share a single raster column")
  func colonsShareColumn() {
    let raster = render(ColonAlignedForm(), width: 60, height: 14).rasterSurface
    let dump = raster.lines.joined(separator: "\n")

    guard let nameRow = raster.firstRow(containing: "name:"),
      let emailRow = raster.firstRow(containing: "email:"),
      let colorRow = raster.firstRow(containing: "color:"),
      let xRow = raster.firstRow(containing: "x:")
    else {
      Issue.record("missing one or more label rows in raster:\n\(dump)")
      return
    }

    guard let nameLine = raster.row(at: nameRow),
      let emailLine = raster.row(at: emailRow),
      let colorLine = raster.row(at: colorRow),
      let xLine = raster.row(at: xRow)
    else {
      Issue.record("raster rows missing")
      return
    }

    guard let nameCol = column(of: ":", in: nameLine),
      let emailCol = column(of: ":", in: emailLine),
      let colorCol = column(of: ":", in: colorLine),
      let xCol = column(of: ":", in: xLine)
    else {
      Issue.record("one of the label rows is missing a ':' character\n\(dump)")
      return
    }

    #expect(
      nameCol == emailCol,
      "name: col (\(nameCol)) ≠ email: col (\(emailCol))\n\(dump)"
    )
    #expect(
      emailCol == colorCol,
      "email: col (\(emailCol)) ≠ color: col (\(colorCol))\n\(dump)"
    )
    #expect(
      colorCol == xCol,
      "color: col (\(colorCol)) ≠ x: col (\(xCol))\n\(dump)"
    )
  }

  /// A/B vacuity: removing the `.frame(width: 8, alignment:
  /// .trailing)` from each label collapses the alignment — labels
  /// of different intrinsic widths produce colons at different
  /// columns.
  @Test("Removing the trailing-aligned frame breaks colon alignment")
  func colonAlignmentIsNonVacuous() {
    let withFrame = render(
      ColonAlignedForm(),
      width: 60,
      height: 14,
      id: "with-frame"
    ).rasterSurface
    let withoutFrame = render(
      ColonAlignedFormFlattenedVariant(),
      width: 60,
      height: 14,
      id: "without-frame"
    ).rasterSurface

    let withDump = withFrame.lines.joined(separator: "\n")
    let withoutDump = withoutFrame.lines.joined(separator: "\n")

    func colonColumns(in raster: RasterSurface) -> [Int]? {
      let labels = ["name:", "email:", "color:", "x:"]
      var cols: [Int] = []
      for label in labels {
        guard let row = raster.firstRow(containing: label),
          let line = raster.row(at: row),
          let col = column(of: ":", in: line)
        else { return nil }
        cols.append(col)
      }
      return cols
    }

    guard let withCols = colonColumns(in: withFrame) else {
      Issue.record("WITH-frame raster missing labels:\n\(withDump)")
      return
    }
    guard let withoutCols = colonColumns(in: withoutFrame) else {
      Issue.record("WITHOUT-frame raster missing labels:\n\(withoutDump)")
      return
    }

    // WITH-frame: all colon columns must be equal.
    #expect(
      Set(withCols).count == 1,
      "WITH-frame expected all colon cols equal; got \(withCols)\n\(withDump)"
    )
    // WITHOUT-frame: not all colon columns are equal — at least
    // two of {name, email, color, x} land at different columns.
    #expect(
      Set(withoutCols).count > 1,
      """
      WITHOUT-frame (no trailing-aligned column) expected at least \
      two colon columns to differ; got \(withoutCols). If they all \
      coincide here the A/B is no longer a valid vacuity check.
      \(withoutDump)
      """
    )
  }
}
