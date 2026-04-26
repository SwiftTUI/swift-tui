import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape and child markers as
/// ``RadialLayout``, but the custom ``RingLayout`` container is
/// replaced by a `VStack`.  Without the radial layout policy the
/// four `[E]/[S]/[W]/[N]` markers stack vertically (in source
/// order: E, S, W, N), so the spatial relationships pinned by the
/// canonical raster (E to the right of center, W to the left,
/// N above S) no longer hold.
@MainActor
private struct RadialLayoutFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Radial layout").foregroundStyle(.muted)
      VStack {
        Text("[E]")
        Text("[S]")
        Text("[W]")
        Text("[N]")
      }
      .frame(width: 24, height: 16)
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct RadialLayoutBehaviourTests {
  /// Pins the cardinal placement of the four `[E]/[S]/[W]/[N]`
  /// children around the center of a 24×16 ring.
  ///
  /// Observed raster (excerpt) at 80×30:
  ///
  /// ```
  /// Radial layout
  /// ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
  /// ▌                        ▐
  /// ▌          [N]           ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌    [W]         [E]     ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌                        ▐
  /// ▌          [S]           ▐
  /// ▌                        ▐
  /// ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟
  /// ```
  ///
  /// Asserted invariants:
  ///   - `[N]` row strictly above `[E]/[W]` row strictly above `[S]` row
  ///   - `[E]` and `[W]` share a row
  ///   - `[E]` column > `[W]` column
  ///   - `[N]` column ≈ `[S]` column (both at the horizontal midline)
  @Test("RingLayout places [E][S][W][N] at cardinal compass directions")
  func cardinalPlacement() {
    let raster = render(RadialLayout(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let nRow = raster.firstRow(containing: "[N]"),
      let sRow = raster.firstRow(containing: "[S]"),
      let eRow = raster.firstRow(containing: "[E]"),
      let wRow = raster.firstRow(containing: "[W]")
    else {
      Issue.record("missing one or more cardinal markers in raster\n\(joined)")
      return
    }

    // Row ordering: N above E/W above S.
    #expect(
      nRow < eRow,
      "expected [N] (row \(nRow)) strictly above [E] (row \(eRow))\n\(joined)"
    )
    #expect(
      nRow < wRow,
      "expected [N] (row \(nRow)) strictly above [W] (row \(wRow))\n\(joined)"
    )
    #expect(
      eRow < sRow,
      "expected [E] (row \(eRow)) strictly above [S] (row \(sRow))\n\(joined)"
    )
    #expect(
      wRow < sRow,
      "expected [W] (row \(wRow)) strictly above [S] (row \(sRow))\n\(joined)"
    )
    #expect(
      eRow == wRow,
      """
      expected [E] (row \(eRow)) and [W] (row \(wRow)) to share a \
      row (the horizontal midline of the ring).
      \(joined)
      """
    )

    // Column ordering: E to the right of W; N and S at the
    // horizontal midline.
    guard let eCol = column(of: "[E]", in: raster.row(at: eRow)),
      let wCol = column(of: "[W]", in: raster.row(at: wRow)),
      let nCol = column(of: "[N]", in: raster.row(at: nRow)),
      let sCol = column(of: "[S]", in: raster.row(at: sRow))
    else {
      Issue.record("missing one or more marker columns\n\(joined)")
      return
    }

    #expect(
      eCol > wCol,
      """
      expected [E] (col \(eCol)) strictly right of [W] (col \(wCol)). \
      If this fails, the ring is no longer placing East/West \
      symmetrically about the center.
      \(joined)
      """
    )
    #expect(
      nCol == sCol,
      """
      expected [N] (col \(nCol)) and [S] (col \(sCol)) at the same \
      column (the vertical midline of the ring).
      \(joined)
      """
    )
    // The midline column for N/S sits between the W and E columns.
    #expect(
      nCol > wCol && nCol < eCol,
      """
      expected the N/S midline column (\(nCol)) to sit between the \
      W column (\(wCol)) and the E column (\(eCol)).
      \(joined)
      """
    )
  }

  /// A/B vacuity: replacing the custom `RingLayout` with a
  /// `VStack` removes the radial placement.  In the variant, the
  /// four markers stack vertically in source order
  /// (`[E]/[S]/[W]/[N]`), so:
  ///   - `[E]` and `[W]` no longer share a row,
  ///   - `[N]` no longer sits above `[E]`/`[W]`,
  ///   - `[S]` no longer sits below the others.
  @Test("replacing RingLayout with VStack collapses cardinals into a vertical line")
  func ringLayoutIsNonVacuous() {
    let withRing = render(
      RadialLayout(),
      width: 80,
      height: 30,
      id: "with-ring"
    ).rasterSurface
    let withoutRing = render(
      RadialLayoutFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-ring"
    ).rasterSurface

    let withDump = withRing.lines.joined(separator: "\n")
    let withoutDump = withoutRing.lines.joined(separator: "\n")

    guard let withE = withRing.firstRow(containing: "[E]"),
      let withW = withRing.firstRow(containing: "[W]")
    else {
      Issue.record("WITH-Ring missing E or W marker\n\(withDump)")
      return
    }
    guard let withoutE = withoutRing.firstRow(containing: "[E]"),
      let withoutW = withoutRing.firstRow(containing: "[W]")
    else {
      Issue.record("WITHOUT-Ring missing E or W marker\n\(withoutDump)")
      return
    }

    // WITH-Ring: E and W must share a row.  WITHOUT-Ring (VStack):
    // they must NOT share a row.
    #expect(
      withE == withW,
      "WITH-Ring expected [E] and [W] on the same row; got E=\(withE) W=\(withW)\n\(withDump)"
    )
    #expect(
      withoutE != withoutW,
      """
      WITHOUT-Ring (VStack) expected [E] and [W] on DIFFERENT rows; \
      got E=\(withoutE) W=\(withoutW). If they share a row in the \
      VStack variant, the A/B is no longer a valid vacuity check.
      \(withoutDump)
      """
    )
  }

  @Test("RingLayout is eligible for frame-tail worker layout")
  func ringLayoutRunsOnFrameTailWorker() async throws {
    let artifacts = await renderAsync(
      RingLayout(radius: 4) {
        Text("[E]")
        Text("[S]")
        Text("[W]")
        Text("[N]")
      },
      width: 20,
      height: 12
    )
    let workerTimings = try #require(artifacts.diagnostics.workerTimings)

    #expect(artifacts.diagnostics.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(workerTimings.rasterCompute != .zero)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("[E]"))
  }
}
