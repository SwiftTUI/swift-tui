import Core
import Testing

@Test("PatternFill.Paint same-variant color interpolation")
func patternFillPaintSameVariantColor() {
  let from = PatternFill.Paint.color(.red)
  let to = PatternFill.Paint.color(.blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let color) = halfway else {
    Issue.record("expected .color variant after same-variant interpolation")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(color.red - expected.red) < 0.001)
}

@Test("PatternFill.Paint same-variant linear gradient interpolation")
func patternFillPaintSameVariantLinearGradient() {
  let from = PatternFill.Paint.linearGradient(
    LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  )
  let to = PatternFill.Paint.linearGradient(
    LinearGradient(colors: [.blue, .red], startPoint: .topTrailing, endPoint: .bottomLeading)
  )
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .linearGradient(let g) = halfway else {
    Issue.record("expected .linearGradient variant")
    return
  }
  #expect(abs(g.startPoint.x - 0.5) < 0.001)
}

@Test(
  "PatternFill.Paint cross-variant is not interpolable",
  arguments: [
    (
      PatternFill.Paint.color(.red),
      PatternFill.Paint.linearGradient(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
    ),
    (
      PatternFill.Paint.color(.red),
      PatternFill.Paint.radialGradient(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      )
    ),
    (
      PatternFill.Paint.linearGradient(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      ),
      PatternFill.Paint.color(.red)
    ),
    (
      PatternFill.Paint.linearGradient(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      ),
      PatternFill.Paint.radialGradient(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      )
    ),
    (
      PatternFill.Paint.radialGradient(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      ),
      PatternFill.Paint.color(.red)
    ),
    (
      PatternFill.Paint.radialGradient(
        RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10)
      ),
      PatternFill.Paint.linearGradient(
        LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
    ),
  ]
)
func patternFillPaintCrossVariantSnap(
  pair: (from: PatternFill.Paint, to: PatternFill.Paint)
) {
  #expect(!pair.from.isInterpolable(to: pair.to))
  let snapped = pair.from.interpolated(to: pair.to, progress: 0.5)
  // Snap to target: result must be the same variant as `to`, not `from`.
  switch (pair.to, snapped) {
  case (.color, .color),
    (.linearGradient, .linearGradient),
    (.radialGradient, .radialGradient):
    break  // Variant matches target — correct snap.
  default:
    Issue.record("cross-variant interpolation must snap to the target variant")
  }
}

@Test("PatternFill with asymmetric background presence is not interpolable")
func patternFillAsymmetricBackgroundSnap() {
  let noBackground = PatternFill(glyph: "░", foreground: .red)
  let withBackground = PatternFill(
    glyph: "░",
    foreground: .red,
    background: .blue
  )
  #expect(!noBackground.isInterpolable(to: withBackground))
  #expect(!withBackground.isInterpolable(to: noBackground))
  // Interpolating asymmetric backgrounds snaps to target.
  let snapped = noBackground.interpolated(to: withBackground, progress: 0.5)
  #expect(snapped.background != nil)
}

@Test("PatternFill Animatable — foreground color interpolation")
func patternFillAnimatableForeground() {
  let from = PatternFill(glyph: "░", foreground: .red)
  let to = PatternFill(glyph: "░", foreground: .blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let fgColor) = halfway.foreground else {
    Issue.record("expected color foreground")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(fgColor.red - expected.red) < 0.001)
}
