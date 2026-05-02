import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct AlertAnchorStableBehaviourTests {
  /// Pins the anchor-stable invariant: presenting an `.alert(...)` does
  /// not reflow the underlying content. Renders two sibling variants —
  /// the canonical `AlertAnchorStable` (alert hidden) and a
  /// closed-state-locked `_AlertOpenVariant` (alert shown via a
  /// `@State` initialised to `true`) — and asserts that `[FIRST CELL]`
  /// occupies the SAME row and column in both rasters.
  ///
  /// If the alert overlay reflowed the underlying content (e.g., by
  /// stealing a row, narrowing the proposal, or shifting the leading
  /// edge), `[FIRST CELL]`'s coordinates would diverge between the two
  /// rasters and this test would fail.
  @Test("alert overlay does not reflow underlying content's anchor cell")
  func alertDoesNotReflowUnderlyingContent() {
    // Width 120 so the centered, ≤48-cell-wide alert surface lands in
    // the middle of the viewport (~cols 36..83) and leaves the
    // underlying content's leading-edge columns (where `[FIRST CELL]`
    // sits) UNCOVERED on the left. Otherwise the alert would overpaint
    // the anchor and we'd be unable to read its post-overlay column.
    let closed = render(
      AlertAnchorStable(),
      width: 120,
      height: 20,
      id: "alert-anchor-stable.closed"
    ).rasterSurface
    let open = render(
      _AlertOpenVariant(),
      width: 120,
      height: 20,
      id: "alert-anchor-stable.open"
    ).rasterSurface

    let closedJoined = closed.lines.joined(separator: "\n")
    let openJoined = open.lines.joined(separator: "\n")

    guard let closedRow = closed.firstRow(containing: "[FIRST CELL]") else {
      Issue.record(
        """
        expected [FIRST CELL] in alert-closed raster but did not find it
        \(closedJoined)
        """
      )
      return
    }
    guard let openRow = open.firstRow(containing: "[FIRST CELL]") else {
      Issue.record(
        """
        expected [FIRST CELL] in alert-open raster but did not find it
        \(openJoined)
        """
      )
      return
    }

    let closedCol = column(of: "[FIRST CELL]", in: closed.row(at: closedRow))
    let openCol = column(of: "[FIRST CELL]", in: open.row(at: openRow))

    #expect(
      closedRow == openRow,
      """
      [FIRST CELL] row drifted across alert show/hide: \
      closed row=\(closedRow), open row=\(openRow). The alert overlay \
      is reflowing the underlying content vertically.
      --- closed ---
      \(closedJoined)
      --- open ---
      \(openJoined)
      """
    )
    #expect(
      closedCol == openCol,
      """
      [FIRST CELL] column drifted across alert show/hide: \
      closed col=\(closedCol ?? -1), open col=\(openCol ?? -1). The \
      alert overlay is reflowing the underlying content horizontally.
      --- closed ---
      \(closedJoined)
      --- open ---
      \(openJoined)
      """
    )
  }
}

/// Test-only sibling of ``AlertAnchorStable`` whose `@State Bool` is
/// initialised to `true`, so the alert is presented from the very
/// first resolve. Lets the behaviour test render an "alert shown"
/// raster without driving any state transitions.
private struct _AlertOpenVariant: View {
  @State private var alwaysShowing: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Alert anchor stable")
      // VACUITY: uncomment the following line to inject an extra row
      // above [FIRST CELL] in only the open variant. The behaviour
      // test then fails because [FIRST CELL]'s row drifts down by 1
      // in the open raster vs. the closed raster — proving the
      // assertion is observing the underlying content's row.
      // Text("[INJECTED REFLOW]")
      Text("[FIRST CELL]")
      ForEach(0..<5, id: \.self) { i in
        Text("body row \(i)")
      }
    }
    .padding(1)
    .alert(
      "Title",
      isPresented: $alwaysShowing,
      actions: {
        Text("OK")
      },
      message: {
        EmptyView()
      }
    )
  }
}
