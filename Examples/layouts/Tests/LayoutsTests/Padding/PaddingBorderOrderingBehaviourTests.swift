import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PaddingBorderOrderingBehaviourTests {
  /// Two `Text("A")` boxes side-by-side in an `HStack` differ only in
  /// the order of `.padding(1)` vs `.border(.separator)`. The visible
  /// border width pins SwiftUI-faithful semantics:
  ///
  ///   - LEFT  (`.padding(1).border(.separator)`): padding sits INSIDE
  ///     the border, so the border ring measures `1 + 1 + 1 + 1 + 1 = 5`
  ///     cells wide (left wall + leading pad + char + trailing pad +
  ///     right wall).
  ///   - RIGHT (`.border(.separator).padding(1)`): border hugs the
  ///     letter (`1 + 1 + 1 = 3` cells wide); the outer padding adds
  ///     empty cells OUTSIDE the border ring rather than inside.
  ///
  /// Observed raster at 60×12 viewport:
  ///
  /// ```
  /// [3]| ╭───╮|
  /// [4]| │   │     ╭─╮|
  /// [5]| │ A │     │A│|
  /// [6]| │   │     ╰─╯|
  /// [7]| ╰───╯|
  /// ```
  ///
  /// On the row containing both `A` glyphs, the left-box border run
  /// (`│ A │` → 5 non-space cells) is wider than the right-box border
  /// run (`│A│` → 3 non-space cells).
  @Test("padding-inside-border yields a wider ring than border-inside-padding")
  func leftBoxIsWiderThanRightBox() {
    let raster = render(PaddingBorderOrdering(), width: 60, height: 12).rasterSurface

    // Both `A` glyphs share the central row of the HStack.
    guard let aRow = raster.firstRow(containing: "A") else {
      Issue.record(
        "expected a row containing 'A' in raster:\n\(raster.lines.joined(separator: "\n"))"
      )
      return
    }
    guard let line = raster.row(at: aRow) else { return }
    let cells = Array(line)

    // The vertical wall glyph from `.border(.separator)` is `│`.
    // Each box contributes two walls, so the row should hold exactly
    // four wall columns. The box-span is `right_wall - left_wall + 1`.
    let walls = cells.enumerated().compactMap { $0.element == "│" ? $0.offset : nil }

    #expect(
      walls.count == 4,
      "expected exactly 4 border walls; got walls=\(walls)\nrow: '\(line)'"
    )
    guard walls.count == 4 else { return }

    let leftBoxSpan = walls[1] - walls[0] + 1
    let rightBoxSpan = walls[3] - walls[2] + 1

    // Padding-inside-border (left) box is WIDER than
    // border-inside-padding (right) box because the padding adds
    // interior cells (left form) vs exterior cells (right form).
    #expect(
      leftBoxSpan > rightBoxSpan,
      "expected left box span (\(leftBoxSpan)) > right box span (\(rightBoxSpan))\nrow: '\(line)'"
    )

    // Pin the exact measured spans for the SwiftUI-faithful shape:
    //   left  = wall + pad + char + pad + wall = 5
    //   right = wall + char + wall            = 3
    #expect(
      leftBoxSpan == 5,
      "expected left ring span 5 (1 wall + 1 pad + 1 char + 1 pad + 1 wall); got \(leftBoxSpan)"
    )
    #expect(
      rightBoxSpan == 3,
      "expected right ring span 3 (1 wall + 1 char + 1 wall); got \(rightBoxSpan)"
    )
  }
}
