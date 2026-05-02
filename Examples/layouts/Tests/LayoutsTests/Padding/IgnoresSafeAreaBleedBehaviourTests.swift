import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct IgnoresSafeAreaBleedBehaviourTests {
  /// A/B proof that `.ignoresSafeArea(.bottom)` reclaims the bottom
  /// safe-area zone established by an outer `.safeAreaPadding(.bottom, 3)`.
  ///
  /// `IgnoresSafeAreaBleed` is the WITH variant. `WithoutIgnoreVariant`
  /// below is identical except it omits `.ignoresSafeArea(.bottom)`.
  ///
  /// Observed rasters at 40×14:
  ///
  /// ```
  /// WITH                                        WITHOUT
  /// [0] |Ignores safe area bleed              █| [0] |Ignores safe area bleed              █|
  /// [1] |content 0                            █| [1] |content 0                            █|
  /// ...                                          ...
  /// [12]|content 11                           ┃| [10]|content 9                            ▼|
  /// [13]|content 12                           ▼| [11]| … empty …                           |
  ///                                              [12]| … empty …                           |
  ///                                              [13]| … empty …                           |
  /// ```
  ///
  /// Pinned: the WITH variant paints content into the reserved 3-row
  /// bottom zone; the WITHOUT variant stops 3 rows higher.
  @Test("With .ignoresSafeArea, content bleeds into the safe area zone")
  func ignoresSafeAreaPaintsIntoReservedZone() {
    let width = 40
    let height = 14
    let withIgnore = render(
      IgnoresSafeAreaBleed(),
      width: width,
      height: height,
      id: "with-ignore"
    ).rasterSurface
    let withoutIgnore = render(
      WithoutIgnoreVariant(),
      width: width,
      height: height,
      id: "without-ignore"
    ).rasterSurface

    let withRows = withIgnore.rows(containing: "content ")
    let withoutRows = withoutIgnore.rows(containing: "content ")
    let withDump = withIgnore.lines.joined(separator: "\n")
    let withoutDump = withoutIgnore.lines.joined(separator: "\n")

    #expect(
      !withRows.isEmpty,
      "baseline: with-ignore should show content; raster:\n\(withDump)"
    )
    #expect(
      !withoutRows.isEmpty,
      "baseline: without-ignore should show content; raster:\n\(withoutDump)"
    )

    // The reclaimed zone is 3 rows deep: with-ignore should paint 3
    // more content rows AND reach further down the raster than
    // without-ignore.
    #expect(
      withRows.count > withoutRows.count,
      "with-ignore rows \(withRows.count) should exceed without-ignore \(withoutRows.count); WITH:\n\(withDump)\nWITHOUT:\n\(withoutDump)"
    )
    #expect(
      (withRows.last ?? -1) > (withoutRows.last ?? -1),
      "with-ignore last content row \(withRows.last ?? -1) should be below without-ignore last content row \(withoutRows.last ?? -1)"
    )
    #expect(
      withRows.last == height - 1,
      "with-ignore should extend content to the last viewport row (\(height - 1)); got \(withRows.last ?? -1)"
    )
  }
}

/// Identical to `IgnoresSafeAreaBleed` except it omits the
/// `.ignoresSafeArea(.bottom)` modifier. Used by the A/B comparison.
private struct WithoutIgnoreVariant: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Ignores safe area bleed").foregroundStyle(.muted)
        ForEach(0..<30, id: \.self) { i in
          Text("content \(i)")
        }
      }
    }
    .safeAreaPadding(.bottom, 3)
  }
}
