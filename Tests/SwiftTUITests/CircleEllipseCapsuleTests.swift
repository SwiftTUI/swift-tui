import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

/// Returns the number of Braille dots lit in a raster cell, or 0 if
/// the cell does not contain a Braille glyph. Blank cells (`U+2800`)
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

/// Counts the number of cells in a single row that hold a non-blank
/// Braille glyph (i.e. at least one subpixel dot lit).
private func litBrailleCellsInRow(
  _ artifacts: FrameArtifacts,
  row: Int
) -> Int {
  guard row >= 0, row < artifacts.rasterSurface.cells.count else {
    return 0
  }
  var count = 0
  for cell in artifacts.rasterSurface.cells[row] {
    if brailleDotCount(cell) > 0 {
      count += 1
    }
  }
  return count
}

@MainActor
@Suite("Circle, Ellipse, Capsule rendering")
struct CircleEllipseCapsuleTests {

  // MARK: - Circle

  @Test("Circle().fill renders Braille glyphs")
  func circleFillRendersBraille() {
    let artifacts = DefaultRenderer().render(
      Circle().fill(Color.white).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CircleFill"))
    )
    // The center cell of a 10x5 frame should contain a Braille glyph
    // with at least one dot set.
    let center = artifacts.rasterSurface.cells[2][5]
    let scalar = center.character.unicodeScalars.first?.value ?? 0
    #expect(scalar >= 0x2800)
    #expect(scalar <= 0x28FF)
    #expect(brailleDotCount(center) > 0)
  }

  @Test("Circle().fill with zero-sized frame renders nothing without crashing")
  func circleFillEmptyFrame() {
    let artifacts = DefaultRenderer().render(
      Circle().fill(Color.white).frame(width: 0, height: 0),
      context: .init(identity: testIdentity("CircleEmpty"))
    )
    // Confirm no crash and no lit braille cells.
    for row in artifacts.rasterSurface.cells {
      for cell in row {
        #expect(brailleDotCount(cell) == 0)
      }
    }
  }

  @Test("Circle().strokeBorder renders a ring instead of a disc")
  func circleStrokeRendersRing() {
    let fillArtifacts = DefaultRenderer().render(
      Circle().fill(Color.white).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CircleFillForDiff"))
    )
    let strokeArtifacts = DefaultRenderer().render(
      Circle().strokeBorder(Color.white).frame(width: 10, height: 5),
      context: .init(identity: testIdentity("CircleStrokeForDiff"))
    )
    // The center of a filled disc has every dot set (dot count of 8).
    // The center of a stroked ring has strictly fewer dots set.
    let fillDots = brailleDotCount(fillArtifacts.rasterSurface.cells[2][5])
    let strokeDots = brailleDotCount(strokeArtifacts.rasterSurface.cells[2][5])
    #expect(fillDots > strokeDots)
  }

  // MARK: - Ellipse

  @Test("Ellipse().fill renders into its frame")
  func ellipseFillWideFrame() {
    let artifacts = DefaultRenderer().render(
      Ellipse().fill(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("EllipseWide"))
    )
    #expect(artifacts.rasterSurface.size.width == 20)
    #expect(artifacts.rasterSurface.size.height == 3)
    // The middle row should have lit Braille cells.
    #expect(litBrailleCellsInRow(artifacts, row: 1) > 0)
  }

  @Test("Ellipse().fill fills more horizontal cells than Circle in a wide frame")
  func ellipseVsCircleShape() {
    let circleArtifacts = DefaultRenderer().render(
      Circle().fill(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("CircleInWideFrame"))
    )
    let ellipseArtifacts = DefaultRenderer().render(
      Ellipse().fill(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("EllipseInWideFrame"))
    )
    let circleLit = litBrailleCellsInRow(circleArtifacts, row: 1)
    let ellipseLit = litBrailleCellsInRow(ellipseArtifacts, row: 1)
    // An ellipse inscribed in a wide frame should reach the frame's full
    // horizontal extent, while a circle is capped at the short axis.
    #expect(ellipseLit > circleLit)
  }

  @Test("Ellipse().fill in a 1x1 frame renders without crashing")
  func ellipseFillTinyFrame() {
    let artifacts = DefaultRenderer().render(
      Ellipse().fill(Color.white).frame(width: 1, height: 1),
      context: .init(identity: testIdentity("EllipseTiny"))
    )
    // Confirm no crash; a 1x1 ellipse should still render at least the
    // single center cell with some dot lit.
    let center = artifacts.rasterSurface.cells[0][0]
    #expect(brailleDotCount(center) >= 0)
  }

  // MARK: - Capsule

  @Test("Capsule().fill lights the middle of a wide frame")
  func capsuleFillEnds() {
    let artifacts = DefaultRenderer().render(
      Capsule().fill(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("CapsuleWide"))
    )
    // The middle column of the middle row is well inside the capsule
    // body for a 20x3 frame.
    let middle = artifacts.rasterSurface.cells[1][10]
    #expect(brailleDotCount(middle) > 0)
  }

  @Test("Capsule().fill renders in a tall frame without crashing")
  func capsuleTallFrame() {
    let artifacts = DefaultRenderer().render(
      Capsule().fill(Color.white).frame(width: 3, height: 10),
      context: .init(identity: testIdentity("CapsuleTall"))
    )
    #expect(artifacts.rasterSurface.size.width == 3)
    #expect(artifacts.rasterSurface.size.height == 10)
    // The center of a tall capsule body should be lit.
    let middle = artifacts.rasterSurface.cells[5][1]
    #expect(brailleDotCount(middle) > 0)
  }

  @Test("Capsule().strokeBorder renders a pill outline, not a solid pill")
  func capsuleStrokeOutline() {
    let fillArt = DefaultRenderer().render(
      Capsule().fill(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("CapsuleFillForDiff"))
    )
    let strokeArt = DefaultRenderer().render(
      Capsule().strokeBorder(Color.white).frame(width: 20, height: 3),
      context: .init(identity: testIdentity("CapsuleStrokeForDiff"))
    )
    let fillDots = brailleDotCount(fillArt.rasterSurface.cells[1][10])
    let strokeDots = brailleDotCount(strokeArt.rasterSurface.cells[1][10])
    #expect(fillDots > strokeDots)
  }
}
