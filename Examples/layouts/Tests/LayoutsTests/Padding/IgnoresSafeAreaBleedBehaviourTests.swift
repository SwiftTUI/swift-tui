import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct IgnoresSafeAreaBleedBehaviourTests {
  /// `.ignoresSafeArea(.bottom)` lets the `ScrollView`'s drawing area
  /// extend INTO the bottom row. When the `[STATUS BAR]` is overlaid
  /// at the ZStack's bottom alignment, the bar text covers the
  /// scroll-content cells in its column range but the scroll
  /// indicator on the trailing edge peeks through on the same row,
  /// providing observable evidence that the ScrollView paints through
  /// the bar zone.
  ///
  /// Observed raster at 40×10 viewport:
  ///
  /// ```
  /// [0]|Ignores safe area bleed                █|
  /// [1]|content 0                              █|
  /// [2]|content 1                              █|
  /// [3]|content 2                              █|
  /// [4]|content 3                              ┃|
  /// [5]|content 4                              ┃|
  /// [6]|content 5                              ┃|
  /// [7]|content 6                              ┃|
  /// [8]|content 7                              ┃|
  /// [9]|[STATUS BAR]                           ▼|
  /// ```
  ///
  /// Compare with `SafeAreaInsetBottomBar` (layout #16) where the
  /// scroll indicator's last glyph sits one row HIGHER (row 8) and
  /// the bar row contains only the bar text — the `.safeAreaInset`
  /// modifier reduces the ScrollView proposal there. In this layout
  /// the ZStack overlay does not reduce the proposal and the
  /// `.ignoresSafeArea(.bottom)` modifier is consistent with the
  /// observed behaviour: the ScrollView occupies the full ZStack
  /// height including the bar's row.
  ///
  /// Pinned behaviour:
  ///   - `[STATUS BAR]` row is the last row (height-1).
  ///   - The same row contains a non-bar glyph at the trailing column
  ///     (the scroll indicator `▼`), proving the ScrollView paints
  ///     through the bar zone.
  @Test("scroll indicator extends into the status-bar row (bleed)")
  func scrollIndicatorReachesBarRow() {
    let width = 40
    let height = 10
    let raster = render(IgnoresSafeAreaBleed(), width: width, height: height).rasterSurface

    guard let barRow = raster.firstRow(containing: "[STATUS BAR]") else {
      Issue.record(
        "expected '[STATUS BAR]' in raster:\n\(raster.lines.joined(separator: "\n"))"
      )
      return
    }
    #expect(
      barRow == height - 1,
      "expected status bar at last row (\(height - 1)); got \(barRow)"
    )

    guard let barLine = raster.row(at: barRow) else { return }
    let barCols = Array(barLine)

    // The `[STATUS BAR]` text covers the leading columns. The
    // trailing columns on the same row should contain the
    // ScrollView's vertical indicator glyph, evidencing the bleed.
    // Scan for any non-space, non-bar-text glyph after the closing
    // `]` of the bar.
    let closingBracketIndex = barCols.firstIndex(of: "]")
    guard let closingBracketIndex else {
      Issue.record(
        "expected ']' in bar row '\(barLine)'"
      )
      return
    }
    let trailing = barCols[barCols.index(after: closingBracketIndex)...]
    let hasNonSpaceTrailing = trailing.contains { !$0.isWhitespace }

    #expect(
      hasNonSpaceTrailing,
      "expected ScrollView indicator glyph after ']' on bar row \(barRow); row='\(barLine)'\n\(raster.lines.joined(separator: "\n"))"
    )
  }
}
