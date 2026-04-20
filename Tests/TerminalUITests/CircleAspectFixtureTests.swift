import Testing

@testable import Core
@testable import TerminalUI
@testable import View

// MARK: - Braille helpers (copied from CircleEllipseCapsuleTests)

/// Returns the number of Braille dots lit in a raster cell, or 0 if
/// the cell does not contain a Braille glyph. Blank cells (U+2800)
/// report 0 because the zero-dot Braille glyph has no bits set.
private func brailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

/// Counts total cells across the entire raster surface that hold at
/// least one lit Braille dot.
private func totalLitBrailleCells(_ artifacts: FrameArtifacts) -> Int {
  var count = 0
  for row in artifacts.rasterSurface.cells {
    for cell in row where brailleDotCount(cell) > 0 {
      count += 1
    }
  }
  return count
}

/// Counts lit Braille cells in a single named row, guarding against
/// out-of-range indices.
private func litBrailleCellsInRow(
  _ artifacts: FrameArtifacts,
  row: Int
) -> Int {
  guard row >= 0, row < artifacts.rasterSurface.cells.count else {
    return 0
  }
  return artifacts.rasterSurface.cells[row].filter { brailleDotCount($0) > 0 }.count
}

// MARK: - Render helpers

@MainActor
private func renderShape<V: View>(
  _ view: V,
  frameWidth: Int,
  frameHeight: Int,
  metrics: CellPixelMetrics
) -> FrameArtifacts {
  var env = EnvironmentValues()
  // Give the renderer a canvas larger than the frame so the shape has
  // room; padding of 4 cells on each axis is sufficient.
  env.terminalSize = Size(width: frameWidth + 4, height: frameHeight + 4)
  env.cellPixelMetrics = metrics
  return DefaultRenderer().render(
    view,
    context: .init(
      identity: testIdentity("AspectFixture"),
      environmentValues: env
    )
  )
}

// MARK: - Test suite

@MainActor
@Suite("Circle/Ellipse/Capsule aspect-correction across terminal metrics")
struct CircleAspectFixtureTests {

  // MARK: Circle: basic sanity at all three metrics

  @Test(
    "Circle at each metric produces lit Braille cells",
    arguments: [
      CellPixelMetrics.estimated,
      CellPixelMetrics(width: 10, height: 16, source: .reported),
      CellPixelMetrics(width: 6, height: 14, source: .reported),
    ]
  )
  func circleProducesLitCells(metrics: CellPixelMetrics) {
    let artifacts = renderShape(
      Circle().fill(Color.white).frame(width: 10, height: 10),
      frameWidth: 10,
      frameHeight: 10,
      metrics: metrics
    )
    #expect(totalLitBrailleCells(artifacts) > 0)
  }

  // MARK: Circle: aspect correction is active

  @Test("Circle raster differs between default (8x16) and stretched (10x16) metrics")
  func circleAspectCorrectionIsActive() {
    // At 8x16 (aspectRatio=2.0) sub-pixels are square: rx==ry.
    // At 10x16 (aspectRatio=1.6) sub-pixels are oblong: rx < ry.
    // The resulting glyph layout must differ in at least the per-row
    // distribution even if the total lit-cell count happens to match.
    let defaultArtifacts = renderShape(
      Circle().fill(Color.white).frame(width: 10, height: 10),
      frameWidth: 10,
      frameHeight: 10,
      metrics: .estimated
    )
    let stretchedArtifacts = renderShape(
      Circle().fill(Color.white).frame(width: 10, height: 10),
      frameWidth: 10,
      frameHeight: 10,
      metrics: CellPixelMetrics(width: 10, height: 16, source: .reported)
    )

    #expect(totalLitBrailleCells(defaultArtifacts) > 0)
    #expect(totalLitBrailleCells(stretchedArtifacts) > 0)

    let defaultCount = totalLitBrailleCells(defaultArtifacts)
    let stretchedCount = totalLitBrailleCells(stretchedArtifacts)

    if defaultCount != stretchedCount {
      // Total lit-cell counts diverge: aspect correction is provably active.
      return
    }

    // Counts happen to match; compare the per-row distributions.
    let rowCount = min(
      defaultArtifacts.rasterSurface.cells.count,
      stretchedArtifacts.rasterSurface.cells.count
    )
    var foundRowDifference = false
    outer: for row in 0..<rowCount {
      let defaultRow = defaultArtifacts.rasterSurface.cells[row]
      let stretchedRow = stretchedArtifacts.rasterSurface.cells[row]
      for i in 0..<min(defaultRow.count, stretchedRow.count) {
        if brailleDotCount(defaultRow[i]) != brailleDotCount(stretchedRow[i]) {
          foundRowDifference = true
          break outer
        }
      }
    }
    #expect(
      foundRowDifference,
      "Circle output at 8x16 (estimated) and 10x16 (reported) should not be identical; check that cellPixelMetrics flows through to the rasterizer."
    )
  }

  // MARK: Circle: wide-cell metrics (12x16 — subpixels are 6 wide x 4 tall)

  @Test("Circle raster differs between default (8x16) and wide-cell (12x16) metrics")
  func circleWideCellAspectCorrectionIsActive() {
    // 8x16: subpixel = 4px wide x 4px tall (square).
    // 12x16: subpixel = 6px wide x 4px tall (wider than tall).
    // Different sub-pixel aspect means different rx vs ry, so the
    // rendered glyph distribution must differ.
    let defaultArtifacts = renderShape(
      Circle().fill(Color.white).frame(width: 10, height: 10),
      frameWidth: 10,
      frameHeight: 10,
      metrics: .estimated
    )
    let wideCellArtifacts = renderShape(
      Circle().fill(Color.white).frame(width: 10, height: 10),
      frameWidth: 10,
      frameHeight: 10,
      metrics: CellPixelMetrics(width: 12, height: 16, source: .reported)
    )

    #expect(totalLitBrailleCells(defaultArtifacts) > 0)
    #expect(totalLitBrailleCells(wideCellArtifacts) > 0)

    let defaultCount = totalLitBrailleCells(defaultArtifacts)
    let wideCellCount = totalLitBrailleCells(wideCellArtifacts)

    if defaultCount != wideCellCount {
      return
    }

    let rowCount = min(
      defaultArtifacts.rasterSurface.cells.count,
      wideCellArtifacts.rasterSurface.cells.count
    )
    var foundRowDifference = false
    outer: for row in 0..<rowCount {
      let defaultRow = defaultArtifacts.rasterSurface.cells[row]
      let wideCellRow = wideCellArtifacts.rasterSurface.cells[row]
      for i in 0..<min(defaultRow.count, wideCellRow.count) {
        if brailleDotCount(defaultRow[i]) != brailleDotCount(wideCellRow[i]) {
          foundRowDifference = true
          break outer
        }
      }
    }
    #expect(
      foundRowDifference,
      "Circle output at 8x16 (estimated) and 12x16 (reported) should not be identical; check that cellPixelMetrics flows through to the rasterizer."
    )
  }

  // MARK: Ellipse: smoke test at non-default metric

  @Test("Ellipse at non-default metric (6x14) produces lit Braille cells")
  func ellipseAspectSmoke() {
    let artifacts = renderShape(
      Ellipse().fill(Color.white).frame(width: 10, height: 5),
      frameWidth: 10,
      frameHeight: 5,
      metrics: CellPixelMetrics(width: 6, height: 14, source: .reported)
    )
    #expect(totalLitBrailleCells(artifacts) > 0)
  }

  // MARK: Capsule: smoke test at non-default metric

  @Test("Capsule at non-default metric (10x16) produces lit Braille cells")
  func capsuleAspectSmoke() {
    let artifacts = renderShape(
      Capsule().fill(Color.white).frame(width: 10, height: 5),
      frameWidth: 10,
      frameHeight: 5,
      metrics: CellPixelMetrics(width: 10, height: 16, source: .reported)
    )
    #expect(totalLitBrailleCells(artifacts) > 0)
  }
}
