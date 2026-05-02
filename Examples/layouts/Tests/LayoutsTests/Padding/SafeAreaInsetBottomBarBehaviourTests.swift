import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct SafeAreaInsetBottomBarBehaviourTests {
  /// `.safeAreaInset(edge: .bottom)` pins the `[STATUS BAR]` to the
  /// bottom of the viewport AND reduces the inner proposal to the
  /// `ScrollView`. The bar therefore occupies the last row alone, and
  /// the scrolling content stops at the row above it.
  ///
  /// Observed raster at 40×10 viewport:
  ///
  /// ```
  /// [0]|Safe area inset bottom bar             █|
  /// [1]|content 0                              █|
  /// [2]|content 1                              █|
  /// [3]|content 2                              █|
  /// [4]|content 3                              ┃|
  /// [5]|content 4                              ┃|
  /// [6]|content 5                              ┃|
  /// [7]|content 6                              ┃|
  /// [8]|content 7                              ▼|
  /// [9]|[STATUS BAR]|
  /// ```
  ///
  /// Pinned behaviour:
  ///   - `[STATUS BAR]` row is the last non-empty row (height-1).
  ///   - At least one `content N` row appears strictly above the bar.
  ///   - No `content N` row coexists with the bar on the same line.
  @Test("status bar pins to last row and does not overlap content")
  func statusBarPinsBottomAndContentStopsAbove() {
    let height = 10
    let raster = render(SafeAreaInsetBottomBar(), width: 40, height: height).rasterSurface

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

    let contentRows = raster.rows(containing: "content ")
    #expect(
      !contentRows.isEmpty,
      "expected at least one 'content N' row\n\(raster.lines.joined(separator: "\n"))"
    )
    let aboveBar = contentRows.filter { $0 < barRow }
    #expect(
      !aboveBar.isEmpty,
      "expected at least one content row strictly above the bar (\(barRow)); got \(contentRows)"
    )

    // No content row should share the bar's row — `.safeAreaInset`
    // reduces the ScrollView's proposal to leave room for the bar.
    let onBarRow = contentRows.filter { $0 == barRow }
    #expect(
      onBarRow.isEmpty,
      "expected no 'content N' on bar row (\(barRow)); got \(onBarRow)"
    )
  }
}
