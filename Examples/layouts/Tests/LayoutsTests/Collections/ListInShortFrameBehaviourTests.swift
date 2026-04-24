import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape but the `.frame(height:)` is grown
/// from 5 to 50, which is enough vertical room for all 20 rows
/// (plain List style draws a separator between each row, so 20
/// rows + 19 separators = 39 lines). With the larger frame `row 19`
/// is no longer scrolled or clipped — so the `row 19 == nil`
/// invariant must FAIL when this variant is rendered.
@MainActor
private struct ListInShortFrameTallVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("List in short frame").foregroundStyle(.muted)
      List(selection: .constant(nil as String?)) {
        ForEach(0..<20, id: \.self) { i in
          Text("row \(i)").tag("\(i)")
        }
      }
      .listStyle(.plain)
      .frame(height: 50)
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ListInShortFrameBehaviourTests {
  /// Observed raster (40×14 viewport):
  ///
  /// ```
  /// [1] | List in short frame|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|   <- top border
  /// [3] | ▌                                    ▐|
  /// [4] | ▌row 0                               ▐|
  /// [5] | ▌────────────────────────────────────▐|
  /// [6] | ▌row 1                               ▐|
  /// [7] | ▌↓                                   ▐|
  /// [8] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|   <- bottom border
  /// ```
  ///
  /// Two invariants pinned together:
  ///   - `row 0` is painted inside the viewport (the first content
  ///     row of the bordered region).
  ///   - `row 19` is NOT painted anywhere — the 20-row List cannot
  ///     fit in the 5-row frame, so the tail is scrolled or clipped
  ///     off.
  @Test("row 0 visible; row 19 not visible in short frame")
  func shortFrameClipsTailRows() {
    let raster = render(ListInShortFrame(), width: 40, height: 14).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      raster.firstRow(containing: "row 0") != nil,
      "expected `row 0` inside viewport\n\(joined)"
    )
    #expect(
      raster.firstRow(containing: "row 19") == nil,
      "expected `row 19` NOT present (20 rows do not fit in 5-row frame)\n\(joined)"
    )
  }

  /// A/B vacuity: when the frame is grown from 5 to 50 there is
  /// enough room for every row (plain List style draws a separator
  /// between rows, so 20 rows + 19 separators = 39 lines plus
  /// padding — frame=50 fits comfortably), so `row 19` becomes
  /// visible. Pin that the SHORT-frame layout hides it AND the
  /// TALL-frame variant shows it; if the variant ever stops
  /// painting `row 19` the A/B is no longer a valid vacuity check.
  @Test("growing the frame to 50 reveals row 19")
  func shortFrameClippingIsNonVacuous() {
    let shortRaster = render(
      ListInShortFrame(),
      width: 60,
      height: 80,
      id: "short-frame"
    ).rasterSurface
    let tallRaster = render(
      ListInShortFrameTallVariant(),
      width: 60,
      height: 80,
      id: "tall-frame"
    ).rasterSurface

    let shortDump = shortRaster.lines.joined(separator: "\n")
    let tallDump = tallRaster.lines.joined(separator: "\n")

    // SHORT frame: row 19 must NOT appear.
    #expect(
      shortRaster.firstRow(containing: "row 19") == nil,
      "SHORT frame expected row 19 absent; got\n\(shortDump)"
    )
    // TALL frame: row 19 MUST appear (otherwise the vacuity check
    // is no longer informative).
    #expect(
      tallRaster.firstRow(containing: "row 19") != nil,
      """
      TALL-frame variant (frame height 30) expected `row 19` to be \
      visible; if this fails the A/B vacuity check is no longer \
      meaningful.
      \(tallDump)
      """
    )
  }
}
