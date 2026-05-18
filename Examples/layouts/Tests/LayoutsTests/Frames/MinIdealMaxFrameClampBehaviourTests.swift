import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct MinIdealMaxFrameClampBehaviourTests {
  /// Three stacked `clamped` copies, each wrapped in an outer
  /// fixed-width frame that is below min (10), at ideal (40), or
  /// above max (80) of the clamp `minWidth: 20, idealWidth: 40,
  /// maxWidth: 60`.
  ///
  /// The `.border(.separator)` around each clamped copy makes the
  /// actual measured width visible as a horizontal run of border
  /// cells. The test sums the length of each visible border run and
  /// pins:
  ///
  ///   - below-min copy: border run >= 20 (clamped up to minWidth).
  ///   - ideal copy:     border run in [38, 42] (at idealWidth ± 2).
  ///   - above-max copy: border run <= 60 (clamped down to maxWidth).
  ///
  /// A ±2 tolerance absorbs border character counting edges.
  /// Observed raster at 80×20 viewport:
  /// ```
  /// [1] | Min ideal max frame clamp|
  /// [3] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|                                     (width 22 = 20 inner + 2 border)
  /// [5] | ▌      clamped       ▐|
  /// [7] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// [9] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|                   (width 40)
  /// [15]|          ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|  (width 70)
  /// ```
  ///
  /// Pinned behaviour:
  ///   - below-min copy (outer width 10): inner frame clamps UP to
  ///     minWidth (20 inner + 2 border = 22 total). Correct.
  ///   - ideal copy (outer width 40): inner frame matches the outer
  ///     proposal (40 total). Correct.
  ///   - above-max copy (outer width 80): inner frame clamps down to
  ///     maxWidth (60 inner + 2 border cells).
  ///
  /// Note: the original spec compared inner max width against
  /// border-included width and made the clamp look like a divergence.
  /// This test pins the SwiftUI-faithful ceiling.
  @Test("border widths demonstrate min→ideal→max clamping")
  func borderWidthsMatchClamp() {
    let raster = render(MinIdealMaxFrameClamp(), width: 80, height: 20).rasterSurface

    let rowsWithClamped = raster.rows(containing: "clamped")
    #expect(
      rowsWithClamped.count == 3,
      "expected 3 'clamped' labels; got \(rowsWithClamped.count)\n\(raster.lines.joined(separator: "\n"))"
    )
    guard rowsWithClamped.count == 3 else { return }

    // The border for each clamped box surrounds the text row. The
    // clamped Text has no padding so the layout renders as:
    //   top border row   (all corners + horizontals)
    //   blank side-wall  (left wall + spaces + right wall)
    //   clamped text row
    //   blank side-wall
    //   bottom border row
    // The top border row therefore sits at y-2 from the clamped
    // text row. Length of the contiguous non-space run on that row
    // is the outer border width of the clamped view.
    let widths = rowsWithClamped.map { y -> Int in
      let borderRow = y - 2
      guard let line = raster.row(at: borderRow) else { return 0 }
      return longestNonSpaceRun(in: line)
    }

    guard widths.count == 3 else { return }
    let belowMin = widths[0]
    let ideal = widths[1]
    let aboveMax = widths[2]

    // Below-min copy clamps UP to minWidth (20 inner + 2 border).
    #expect(
      belowMin >= 22,
      "below-min copy measured \(belowMin); expected >=22 (min 20 + 2 border)"
    )
    // Ideal copy sits at outer frame proposal when proposal == idealWidth.
    #expect(
      (38...42).contains(ideal),
      "ideal copy measured \(ideal); expected ~40 (±2)"
    )
    #expect(
      (60...64).contains(aboveMax),
      "above-max copy measured \(aboveMax); expected ~62 (max 60 + 2 border)"
    )
  }

  /// Returns the length of the longest contiguous run of
  /// non-whitespace characters in `line`.
  private func longestNonSpaceRun(in line: String) -> Int {
    var best = 0
    var current = 0
    for char in line {
      if char.isWhitespace {
        if current > best { best = current }
        current = 0
      } else {
        current += 1
      }
    }
    return max(best, current)
  }
}
