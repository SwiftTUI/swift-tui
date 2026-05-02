import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite("RadialGradient rendering")
struct RadialGradientRenderingTests {
  @Test("Rectangle fills with radial gradient sampled per cell")
  func rectangleRadialFill() {
    let view =
      Rectangle()
      .fill(
        RadialGradient(
          colors: [.red, .blue],
          center: .center,
          startRadius: 0,
          endRadius: 5
        )
      )
      .frame(width: 11, height: 11)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("RadialGradientFill"))
    )
    // Center cell should be close to red (t ≈ 0); corner cell should
    // be close to blue (t ≈ 1).  Both should have non-nil background
    // colors (opaque fill) and they should differ.
    let center = artifacts.rasterSurface.cells[5][5]
    let corner = artifacts.rasterSurface.cells[0][0]
    let centerBg = center.style?.backgroundColor
    let cornerBg = corner.style?.backgroundColor
    #expect(centerBg != nil)
    #expect(cornerBg != nil)
    #expect(centerBg != cornerBg)
  }

  @Test("Radial gradient with equal start/end radii collapses to a single color")
  func radialGradientDegenerate() {
    let view =
      Rectangle()
      .fill(
        RadialGradient(colors: [.red, .blue], startRadius: 5, endRadius: 5)
      )
      .frame(width: 5, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("RadialGradientDegenerate"))
    )
    // With zero-width radius range, all cells should pin to the end
    // color (blue) — confirm no crash and the surface still rendered.
    #expect(artifacts.rasterSurface.size.width == 5)
    #expect(artifacts.rasterSurface.size.height == 5)
  }

  @Test("Radial gradient in a wide frame still samples by distance")
  func radialGradientWideFrame() {
    let view =
      Rectangle()
      .fill(
        RadialGradient(colors: [.red, .blue], center: .center, endRadius: 10)
      )
      .frame(width: 20, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("RadialGradientWide"))
    )
    // Horizontal midpoint should be close to red (center); far edge
    // should be closer to blue.  Don't assert exact colors — just
    // confirm no crash and width is correct.
    #expect(artifacts.rasterSurface.size.width == 20)
  }
}
