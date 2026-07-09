import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct CellPixelMetricsTests {
  @Test("aspect ratio is height divided by width")
  func aspectRatioDivision() {
    let m = CellPixelMetrics(width: 8, height: 16, source: .reported)
    #expect(m.aspectRatio == 2.0)
  }

  @Test("aspect ratio for square cells is 1.0")
  func aspectRatioSquare() {
    let m = CellPixelMetrics(width: 10, height: 10, source: .reported)
    #expect(m.aspectRatio == 1.0)
  }

  @Test("estimated default is 8x16 and flagged as estimated")
  func estimatedDefault() {
    #expect(CellPixelMetrics.estimated.width == 8)
    #expect(CellPixelMetrics.estimated.height == 16)
    #expect(CellPixelMetrics.estimated.source == .estimated)
    #expect(CellPixelMetrics.estimated.aspectRatio == 2.0)
  }

  @Test("equatable discriminates by source")
  func equatableDiscriminatesBySource() {
    let reported = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let estimated = CellPixelMetrics(width: 8, height: 16, source: .estimated)
    #expect(reported != estimated)
  }

  @Test("equatable discriminates by width and height")
  func equatableDiscriminatesByDimensions() {
    let a = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let b = CellPixelMetrics(width: 10, height: 16, source: .reported)
    #expect(a != b)
  }
}
