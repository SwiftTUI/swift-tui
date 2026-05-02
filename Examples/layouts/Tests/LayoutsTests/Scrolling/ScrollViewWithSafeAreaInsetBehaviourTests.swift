import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ScrollViewWithSafeAreaInsetBehaviourTests {
  /// Observed raster at 40×20:
  ///
  /// ```
  /// [0] ||
  /// [1] | Scroll view with safe area inset|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|   <- top border
  /// [3] | ▌[TOP BAR]                           ▐|   <- inset row
  /// [4] | ▌entry 0                            █▐|   <- first content row
  /// [5] | ▌entry 1                            █▐|
  /// ...
  /// [13]| ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|   <- bottom border
  /// ```
  ///
  /// Two invariants:
  ///   - `[TOP BAR]` is painted strictly ABOVE `entry 0` — the inset
  ///     at `.top` reserves a row and reduces the inner proposal so
  ///     content flows beneath it.
  ///   - A/B comparison: removing `.safeAreaInset(edge: .top)` makes
  ///     `entry 0` start strictly higher on screen (the reserved row
  ///     becomes available for content).
  @Test("top inset pins above content; entry 0 starts below the bar")
  func topInsetReservesFirstRowAndShiftsContent() {
    let width = 40
    let height = 20

    let withInset = render(
      ScrollViewWithSafeAreaInset(),
      width: width,
      height: height,
      id: "with-inset"
    ).rasterSurface
    let withoutInset = render(
      WithoutTopInsetVariant(),
      width: width,
      height: height,
      id: "without-inset"
    ).rasterSurface

    let withDump = withInset.lines.joined(separator: "\n")
    let withoutDump = withoutInset.lines.joined(separator: "\n")

    guard let barRow = withInset.firstRow(containing: "[TOP BAR]") else {
      Issue.record("expected `[TOP BAR]` in the WITH variant raster\n\(withDump)")
      return
    }
    guard let entry0Row = withInset.firstRow(containing: "entry 0") else {
      Issue.record("expected `entry 0` in the WITH variant raster\n\(withDump)")
      return
    }

    #expect(
      barRow < entry0Row,
      """
      expected `[TOP BAR]` row (\(barRow)) strictly above `entry 0` \
      row (\(entry0Row)) — the inset should reserve a row at the top \
      of the viewport.
      \(withDump)
      """
    )

    // Inset removes exactly one row from the ScrollView's proposal.
    // `entry 0` should sit one row below the bar.
    #expect(
      entry0Row == barRow + 1,
      "expected `entry 0` directly below `[TOP BAR]`; barRow=\(barRow), entry0Row=\(entry0Row)\n\(withDump)"
    )

    // A/B: without the inset, `entry 0` should start strictly higher
    // (no inset row to reserve space).
    guard let entry0RowWithout = withoutInset.firstRow(containing: "entry 0") else {
      Issue.record("expected `entry 0` in the WITHOUT variant raster\n\(withoutDump)")
      return
    }
    #expect(
      entry0RowWithout < entry0Row,
      """
      A/B: without `.safeAreaInset(edge: .top)`, entry 0 should start \
      higher; WITH row=\(entry0Row), WITHOUT row=\(entry0RowWithout).
      WITH:\n\(withDump)
      WITHOUT:\n\(withoutDump)
      """
    )
    #expect(
      !withoutInset.lines.joined(separator: "\n").contains("[TOP BAR]"),
      "WITHOUT variant should not paint `[TOP BAR]`\n\(withoutDump)"
    )
  }
}

/// Identical to `ScrollViewWithSafeAreaInset` except it omits the
/// `.safeAreaInset(edge: .top)` modifier. Used by the A/B comparison
/// to prove the inset is what shifts content down.
private struct WithoutTopInsetVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll view with safe area inset").foregroundStyle(.muted)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { i in
            Text("entry \(i)")
          }
        }
      }
      .frame(height: 10)
      .border(.separator)
    }
    .padding(1)
  }
}
