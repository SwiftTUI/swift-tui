import Core
import Testing

@Test("TileStyle.Paint same-variant color interpolation")
func tileStylePaintSameVariantColor() {
  let from = TileStyle.Paint(.red)
  let to = TileStyle.Paint(.blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let color) = halfway.style else {
    Issue.record("expected .color variant after same-variant interpolation")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(color.red - expected.red) < 0.001)
}

@Test("TileStyle.Paint same-variant linear gradient interpolation")
func tileStylePaintSameVariantLinearGradient() {
  let from = TileStyle.Paint(
    LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  )
  let to = TileStyle.Paint(
    LinearGradient(colors: [.blue, .red], startPoint: .topTrailing, endPoint: .bottomLeading)
  )
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .linearGradient(let gradient) = halfway.style else {
    Issue.record("expected .linearGradient variant")
    return
  }
  #expect(abs(gradient.startPoint.x - 0.5) < 0.001)
}

@Test(
  "TileStyle.Paint cross-variant is not interpolable",
  arguments: [
    (
      TileStyle.Paint(.red),
      TileStyle.Paint(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
    ),
    (
      TileStyle.Paint(.red),
      TileStyle.Paint(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      )
    ),
    (
      TileStyle.Paint(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      ),
      TileStyle.Paint(.red)
    ),
    (
      TileStyle.Paint(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      ),
      TileStyle.Paint(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      )
    ),
    (
      TileStyle.Paint(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      ),
      TileStyle.Paint(.red)
    ),
    (
      TileStyle.Paint(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      ),
      TileStyle.Paint(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
    ),
  ]
)
func tileStylePaintCrossVariantSnap(
  pair: (from: TileStyle.Paint, to: TileStyle.Paint)
) {
  #expect(!pair.from.isInterpolable(to: pair.to))
  let snapped = pair.from.interpolated(to: pair.to, progress: 0.5)
  switch (pair.to.style, snapped.style) {
  case (.color, .color),
    (.linearGradient, .linearGradient),
    (.radialGradient, .radialGradient):
    break
  default:
    Issue.record("cross-variant interpolation must snap to the target variant")
  }
}

@Test("TileStyle with asymmetric background presence is not interpolable")
func tileStyleAsymmetricBackgroundSnap() {
  let noBackground = TileStyle(.lightShade, foreground: .red)
  let withBackground = TileStyle(
    .lightShade,
    foreground: .red,
    background: .blue
  )
  #expect(!noBackground.isInterpolable(to: withBackground))
  #expect(!withBackground.isInterpolable(to: noBackground))
  let snapped = noBackground.interpolated(to: withBackground, progress: 0.5)
  #expect(snapped.background != nil)
}

@Test("TileStyle Animatable foreground color interpolation")
func tileStyleAnimatableForeground() {
  let from = TileStyle(.lightShade, foreground: .red)
  let to = TileStyle(.lightShade, foreground: .blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let foregroundColor) = halfway.foreground.style else {
    Issue.record("expected color foreground")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(foregroundColor.red - expected.red) < 0.001)
}
