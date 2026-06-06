import Testing

@testable import SwiftTUICore

@Suite
struct RasterBackdropCoverageTests {
  @Test("coverage classifier treats empty and whitespace cells as background only")
  func coverageClassifierTreatsEmptyAndWhitespaceAsBackgroundOnly() {
    #expect(rasterBackdropCoverage(for: nil, spanWidth: 1) == .none)
    #expect(rasterBackdropCoverage(for: " ", spanWidth: 1) == .none)
    #expect(rasterBackdropCoverage(for: "A", spanWidth: 0) == .none)
  }

  @Test("coverage classifier maps block and shade glyphs to full coverage")
  func coverageClassifierMapsBlockAndShadeGlyphsToFullCoverage() {
    #expect(rasterBackdropCoverage(for: "█", spanWidth: 1) == .full)
    #expect(rasterBackdropCoverage(for: "▓", spanWidth: 1) == .full)
    #expect(rasterBackdropCoverage(for: "▒", spanWidth: 1) == .full)
    #expect(rasterBackdropCoverage(for: "░", spanWidth: 1) == .full)
  }

  @Test("coverage classifier maps half and quadrant glyphs to quadrant masks")
  func coverageClassifierMapsHalfAndQuadrantGlyphsToMasks() {
    #expect(rasterBackdropCoverage(for: "▀", spanWidth: 1) == .quadrant(mask: 0b0011))
    #expect(rasterBackdropCoverage(for: "▄", spanWidth: 1) == .quadrant(mask: 0b1100))
    #expect(rasterBackdropCoverage(for: "▌", spanWidth: 1) == .quadrant(mask: 0b0101))
    #expect(rasterBackdropCoverage(for: "▐", spanWidth: 1) == .quadrant(mask: 0b1010))
    #expect(rasterBackdropCoverage(for: "▗", spanWidth: 1) == .quadrant(mask: 0b1000))
  }

  @Test("coverage classifier maps braille and ordinary glyphs")
  func coverageClassifierMapsBrailleAndOrdinaryGlyphs() {
    #expect(rasterBackdropCoverage(for: "\u{2800}", spanWidth: 1) == .none)
    #expect(rasterBackdropCoverage(for: "\u{2801}", spanWidth: 1) == .braille(mask: 0b0000_0001))
    #expect(rasterBackdropCoverage(for: "A", spanWidth: 1) == .textApproximation)
    #expect(rasterBackdropCoverage(for: "界", spanWidth: 2) == .textApproximation)
  }
}
