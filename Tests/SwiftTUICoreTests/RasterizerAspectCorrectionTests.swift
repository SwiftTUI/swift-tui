import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct RasterizerAspectCorrectionTests {
  /// At the default 8x16 metrics the subpixel aspect is square, so a
  /// circle's x and y radii in subpixel space are identical.
  @Test("8x16 metrics produce equal sub-pixel radii for a square frame")
  func squareFrameAtDefaultMetrics() {
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: CellSize(width: 6, height: 3),
      metrics: .estimated
    )
    // Frame pixel dims: 6*8=48 wide, 3*16=48 tall. Diameter=48. Radius=24px.
    // 24px / (8/2=4px per x-subpixel) = 6
    // 24px / (16/4=4px per y-subpixel) = 6
    #expect(radii.rx == 6)
    #expect(radii.ry == 6)
  }

  /// Cells stretched horizontally (10x16) have non-square sub-pixels;
  /// the x/y radii differ to produce a pixel-true circle.
  @Test("stretched-width metrics produce unequal sub-pixel radii")
  func stretchedWidthMetrics() {
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: CellSize(width: 6, height: 6),
      metrics: CellPixelMetrics(width: 10, height: 16, source: .reported)
    )
    // Frame pixel dims: 6*10=60 wide, 6*16=96 tall. Diameter=60. Radius=30px.
    // 30px / (10/2=5px per x-subpixel) = 6
    // 30px / (16/4=4px per y-subpixel) = 7 (integer division of 30 by 4)
    #expect(radii.rx == 6)
    #expect(radii.ry == 7)
  }

  /// The prepared radial sampler applies the same aspect correction as the
  /// reference sampler: cells at equal *device-pixel* distance from the
  /// centre resolve to equal colours, and the raw-cell offset does not
  /// (STUI-618).
  @Test("prepared radial sampling is aspect-corrected like the reference")
  func preparedRadialSamplingIsAspectCorrected() {
    let bounds = CellRect(origin: .zero, size: CellSize(width: 21, height: 21))
    let gradient = RadialGradient(
      colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 8)
    for metrics in [
      CellPixelMetrics.estimated, CellPixelMetrics(width: 10, height: 15, source: .reported),
    ] {
      let prepared = PreparedRadialGradient(
        gradient, aspectRatio: metrics.aspectRatio, bounds: bounds)
      let rasterizer = Rasterizer()
      for y in 0..<21 {
        for x in 0..<21 {
          #expect(
            prepared.color(atCellX: x, y: y)
              == rasterizer.sample(
                gradient, in: bounds, aspectRatio: metrics.aspectRatio, x: x, y: y),
            "cell (\(x), \(y)) at \(metrics)")
        }
      }
    }
    // At 2:1 metrics four cells right equals two cells down in pixel space.
    let prepared = PreparedRadialGradient(gradient, aspectRatio: 2, bounds: bounds)
    #expect(prepared.color(atCellX: 14, y: 10) == prepared.color(atCellX: 10, y: 12))
    #expect(prepared.color(atCellX: 14, y: 10) != prepared.color(atCellX: 10, y: 14))
  }

  /// At aspectRatio=2.0 the helper must produce rx == ry so existing
  /// Circle fixtures at the default metrics are preserved.
  @Test("aspectRatio 2.0 produces symmetric radii")
  func aspectRatio2IsSymmetric() {
    let frame = CellSize(width: 10, height: 5)
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: frame,
      metrics: .estimated
    )
    #expect(radii.rx == radii.ry)
  }
}
