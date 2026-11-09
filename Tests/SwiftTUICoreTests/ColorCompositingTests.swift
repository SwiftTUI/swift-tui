import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Test(
  "Color.composited applies every built-in blend mode in linear sRGB",
  arguments: [
    (BlendMode.normal, (0.80, 0.40, 0.20)),
    (BlendMode.multiply, (0.16, 0.24, 0.14)),
    (BlendMode.screen, (0.84, 0.76, 0.76)),
    (BlendMode.overlay, (0.32, 0.52, 0.52)),
    (BlendMode.darken, (0.20, 0.40, 0.20)),
    (BlendMode.lighten, (0.80, 0.60, 0.70)),
  ]
)
func colorCompositingAppliesBlendMode(
  mode: BlendMode,
  expected: (red: Double, green: Double, blue: Double)
) {
  let source = Color(red: 0.80, green: 0.40, blue: 0.20, profile: .linearSRGB)
  let backdrop = Color(red: 0.20, green: 0.60, blue: 0.70, profile: .linearSRGB)

  let actual = source.composited(over: backdrop, mode: mode, workingSpace: .linearSRGB)

  expectColor(actual, red: expected.red, green: expected.green, blue: expected.blue)
}

private func expectColor(
  _ actual: Color,
  red: Double,
  green: Double,
  blue: Double,
  alpha: Double = 1.0,
  tolerance: Double = 0.0001
) {
  #expect(abs(actual.red - red) < tolerance)
  #expect(abs(actual.green - green) < tolerance)
  #expect(abs(actual.blue - blue) < tolerance)
  #expect(abs(actual.alpha - alpha) < tolerance)
}

@Test("translucent cell backgrounds use source-over alpha weights")
func translucentTextStyleComposition() throws {
  let under = Color(red: 0, green: 0, blue: 1, alpha: 0.5, profile: .linearSRGB)
  let over = Color(red: 1, green: 0, blue: 0, alpha: 0.5, profile: .linearSRGB)
  let actual = try #require(
    ResolvedTextStyle(backgroundColor: over)
      .composited(over: ResolvedTextStyle(backgroundColor: under)).backgroundColor)
  // Equal input alphas contribute 2:1 after source-over normalization.
  let expected = under.withAlpha(1).mixed(with: over.withAlpha(1), amount: 2.0 / 3)
  expectColor(actual, red: expected.red, green: expected.green, blue: expected.blue, alpha: 0.75)
}
