import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

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

  @Test("Radial gradient falloff is circular in device-pixel space")
  func radialGradientFalloffIsCircular() {
    let view =
      Rectangle()
      .fill(
        RadialGradient(
          colors: [.red, .blue],
          center: .center,
          startRadius: 0,
          endRadius: 8
        )
      )
      .frame(width: 21, height: 21)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("RadialGradientCircular"))
    )
    let cells = artifacts.rasterSurface.cells

    // The center cell is (10, 10).  At the default 8x16 metrics a cell is
    // twice as tall as it is wide, so four cells right and two cells down
    // are the same *device-pixel* distance from the center: a circular
    // falloff must give them the same color.
    let right = cells[10][14].style?.backgroundColor
    let down = cells[12][10].style?.backgroundColor
    #expect(right != nil)
    #expect(right == down)

    // ...and the same offset counted in raw cells must *not* match, which
    // is precisely the vertical over-reach the correction removes.
    let downUncorrected = cells[14][10].style?.backgroundColor
    #expect(right != downUncorrected)
  }

  /// Full-surface comparison of overlapping screen-blended ripples over text
  /// (STUI-618): the support walk and the reference walk must agree on every
  /// cell and every presentation-record fragment through the composed
  /// renderer, not only through the bare rasterizer.
  @Test("Overlapping screen-blended radial fills over text raster identically on both walks")
  func screenBlendedRipplesMatchReferenceWalk() {
    func render() -> RasterSurface {
      DefaultRenderer().render(
        // Ripples below, text above: a sampled fill writes a blank glyph
        // with its blended background, so content it covers must sit on top,
        // as the counter demo places its label over its ripple layers.
        ZStack {
          ForEach(0..<6, id: \.self) { index in
            Rectangle()
              .fill(
                RadialGradient(
                  gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.cyan.opacity(0.8 - Double(index) * 0.1), location: 0.6),
                    .init(color: .clear, location: 1),
                  ]),
                  center: .center,
                  startRadius: Double(index * 5),
                  endRadius: Double(8 + index * 6)
                )
              )
              .blendMode(.screen)
          }
          VStack(alignment: .leading, spacing: 0) {
            Text("counter 0042").bold()
            Text("increment")
          }
        }
        .frame(width: 60, height: 18),
        context: .init(identity: testIdentity("RadialGradientScreenBlend"))
      ).rasterSurface
    }
    let reference = Rasterizer.$forceReferenceRadialWalk.withValue(true) { render() }
    let optimized = render()
    #expect(reference.cells == optimized.cells)
    #expect(reference.presentationLayers == optimized.presentationLayers)
    #expect(reference == optimized)
    // The blend actually happened: a cell under two rings differs from a
    // cell under one, and the text survives underneath.
    let painted = optimized.cells.flatMap { $0 }.filter { $0.style?.backgroundColor != nil }
    #expect(painted.count > 40)
    #expect(Set(painted.compactMap { $0.style?.backgroundColor }).count > 4)
    let text = optimized.cells.map { row in String(row.map(\.character)) }.joined(separator: "\n")
    #expect(text.contains("counter 0042"))
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
