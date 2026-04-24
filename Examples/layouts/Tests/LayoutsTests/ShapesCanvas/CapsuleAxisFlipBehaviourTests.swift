import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: swap the two capsules' frame sizes (and therefore
/// their colours' axes). The wide capsule is now drawn green and the
/// tall capsule blue. This proves the row-count invariant is genuinely
/// keyed off the per-capsule frame size, not off colour identity.
@MainActor
private struct CapsuleAxisFlipSwappedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Capsule axis flip").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 4) {
        Capsule().fill(Color.blue).frame(width: 3, height: 20)
        Capsule().fill(Color.green).frame(width: 20, height: 3)
      }
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct CapsuleAxisFlipBehaviourTests {
  /// Observed raster (60×30 viewport, `.padding(1)` outer, header
  /// + 1-row spacing before the HStack):
  ///
  /// ```
  /// [1] | Capsule axis flip|
  /// [2] |                                                     |
  /// [3] | ⢠⣴⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⡄    ⣴⣷⡄          |  blue+green rows
  /// [4] | ⢺⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡗    ⣿⣿⡇          |  blue+green
  /// [5] | ⠈⠙⠻⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠟⠋⠁    ⣿⣿⡇          |  blue+green
  /// [6] |                         ⣿⣿⡇                          |  green only
  /// ...
  /// [22]|                         ⠻⡿⠃                          |  green only
  /// ```
  ///
  /// Two row-count invariants (axis-flipped capsules paint very
  /// different vertical extents):
  ///   - The blue (wide, 20×3) capsule paints across exactly 3 rows.
  ///   - The green (tall, 3×20) capsule paints across exactly 20 rows.
  ///
  /// The 3-vs-20 row split is the cheap, axis-agnostic proxy for
  /// "Capsule rounds the SHORT axis": wide → semicircular caps left
  /// and right, only the cell's vertical band; tall → semicircular
  /// caps top and bottom, the cell's full vertical band.
  @Test("blue (wide) capsule paints 3 rows; green (tall) capsule paints 20 rows")
  func axisFlipsRowCountsByFrame() {
    let raster = render(CapsuleAxisFlip(), width: 60, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    let blueRows = rows(in: raster, withForeground: Color.blue)
    let greenRows = rows(in: raster, withForeground: Color.green)

    #expect(
      blueRows.count == 3,
      """
      expected blue (20×3 wide) capsule to paint exactly 3 rows; got \
      \(blueRows.count) → \(blueRows)
      \(joined)
      """
    )
    #expect(
      greenRows.count == 20,
      """
      expected green (3×20 tall) capsule to paint exactly 20 rows; got \
      \(greenRows.count) → \(greenRows)
      \(joined)
      """
    )
  }

  /// A/B vacuity: swap the capsules' frame sizes (and therefore which
  /// colour gets the wide/tall frame). Now the BLUE capsule is the
  /// tall one (20 rows) and GREEN is the wide one (3 rows). Pinning
  /// both rasters together proves the row-count invariant is keyed off
  /// the frame, not off some accident of colour ordering or HStack
  /// position.
  @Test("swapping the two frame sizes swaps which colour paints 3 vs 20 rows")
  func rowCountInvariantIsNonVacuous() {
    let baseRaster = render(
      CapsuleAxisFlip(),
      width: 60,
      height: 30,
      id: "base"
    ).rasterSurface
    let swappedRaster = render(
      CapsuleAxisFlipSwappedVariant(),
      width: 60,
      height: 30,
      id: "swapped"
    ).rasterSurface
    let baseDump = baseRaster.lines.joined(separator: "\n")
    let swappedDump = swappedRaster.lines.joined(separator: "\n")

    let baseBlueRows = rows(in: baseRaster, withForeground: Color.blue).count
    let baseGreenRows = rows(in: baseRaster, withForeground: Color.green).count
    let swappedBlueRows = rows(in: swappedRaster, withForeground: Color.blue).count
    let swappedGreenRows = rows(in: swappedRaster, withForeground: Color.green).count

    // BASE: blue=3 rows (wide), green=20 rows (tall).
    #expect(
      baseBlueRows == 3,
      "BASE expected blue=3 rows; got \(baseBlueRows)\n\(baseDump)"
    )
    #expect(
      baseGreenRows == 20,
      "BASE expected green=20 rows; got \(baseGreenRows)\n\(baseDump)"
    )

    // SWAPPED: blue=20 rows (now tall), green=3 rows (now wide).
    // If the SWAPPED variant ever stops flipping the row counts the
    // A/B vacuity check is no longer informative.
    #expect(
      swappedBlueRows == 20,
      """
      SWAPPED variant expected blue=20 rows (now tall); got \
      \(swappedBlueRows). If this fails the A/B vacuity check is no \
      longer meaningful.
      \(swappedDump)
      """
    )
    #expect(
      swappedGreenRows == 3,
      """
      SWAPPED variant expected green=3 rows (now wide); got \
      \(swappedGreenRows). If this fails the A/B vacuity check is no \
      longer meaningful.
      \(swappedDump)
      """
    )
  }
}

/// Returns the row indices that contain at least one cell whose style
/// foreground equals `colour`.
private func rows(in raster: RasterSurface, withForeground colour: Color) -> [Int] {
  var hits: [Int] = []
  for (r, row) in raster.cells.enumerated() {
    for cell in row {
      if cell.style?.foregroundColor == colour {
        hits.append(r)
        break
      }
    }
  }
  return hits
}
