import Testing

@testable import Core

@Suite
struct RasterizerAspectCorrectionTests {
  /// At the default 8x16 metrics the subpixel aspect is square, so a
  /// circle's x and y radii in subpixel space are identical.
  @Test("8x16 metrics produce equal sub-pixel radii for a square frame")
  func squareFrameAtDefaultMetrics() {
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: Size(width: 6, height: 3),
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
      frameCells: Size(width: 6, height: 6),
      metrics: CellPixelMetrics(width: 10, height: 16, source: .reported)
    )
    // Frame pixel dims: 6*10=60 wide, 6*16=96 tall. Diameter=60. Radius=30px.
    // 30px / (10/2=5px per x-subpixel) = 6
    // 30px / (16/4=4px per y-subpixel) = 7 (integer division of 30 by 4)
    #expect(radii.rx == 6)
    #expect(radii.ry == 7)
  }

  /// At aspectRatio=2.0 the helper must produce rx == ry so existing
  /// Circle fixtures at the default metrics are preserved.
  @Test("aspectRatio 2.0 produces symmetric radii")
  func aspectRatio2IsSymmetric() {
    let frame = Size(width: 10, height: 5)
    let radii = Rasterizer.subpixelCircleRadii(
      frameCells: frame,
      metrics: .estimated
    )
    #expect(radii.rx == radii.ry)
  }
}
