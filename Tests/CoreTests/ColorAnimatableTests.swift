import Testing

@testable import Core

@Test("Color animatableData round-trips via OKLab")
func colorAnimatableRoundTrip() {
  var red = Color.red
  let originalRed = red
  let data = red.animatableData
  red.animatableData = data
  // Round-trip through the OKLab representation should produce a
  // color within a tight epsilon of the original (floating point
  // drift through sRGB → OKLab → sRGB is bounded but non-zero).
  #expect(abs(red.red - originalRed.red) < 0.001)
  #expect(abs(red.green - originalRed.green) < 0.001)
  #expect(abs(red.blue - originalRed.blue) < 0.001)
  #expect(abs(red.alpha - originalRed.alpha) < 0.001)
}

@Test(
  "Color halfway interpolation via animatableData matches perceptual method",
  arguments: [
    (Color.red, Color.blue),
    (Color.green, Color.red),
    (Color.blue, Color.yellow),
    (
      Color(red: 0.3, green: 0.7, blue: 0.5),
      Color(red: 0.9, green: 0.2, blue: 0.4)
    ),
  ]
)
func colorHalfwayInterpolationMatchesPerceptual(
  pair: (from: Color, to: Color)
) {
  let from = pair.from
  let to = pair.to

  // Path A: animatable-data arithmetic.
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var pathA = from
  var pathAData = pathA.animatableData
  pathAData += delta
  pathA.animatableData = pathAData

  // Path B: existing Color.interpolated(to:progress:method:.perceptual).
  let pathB = from.interpolated(to: to, progress: 0.5, method: .perceptual)

  // Both paths go through OKLab perceptual interpolation and must
  // produce colors within floating-point epsilon of each other.
  #expect(abs(pathA.red - pathB.red) < 0.001)
  #expect(abs(pathA.green - pathB.green) < 0.001)
  #expect(abs(pathA.blue - pathB.blue) < 0.001)
  #expect(abs(pathA.alpha - pathB.alpha) < 0.001)
}

@Test("Color animatableData zero from arithmetic-zero OKLab")
func colorAnimatableZero() {
  // Zero for AnimatablePair<AnimatablePair<Double, Double>, ...>
  // should be the origin in OKLab space, which round-trips to a
  // zero-alpha black.
  let data: Color.AnimatableData = .zero
  #expect(data.first.first == 0)
  #expect(data.first.second == 0)
  #expect(data.second.first == 0)
  #expect(data.second.second == 0)
}

@Test("Color alpha animates independently via animatableData")
func colorAlphaAnimation() {
  let opaque = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
  let transparent = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.0)
  var delta = transparent.animatableData
  delta -= opaque.animatableData
  delta.scale(by: 0.5)
  var halfway = opaque
  var halfwayData = halfway.animatableData
  halfwayData += delta
  halfway.animatableData = halfwayData
  #expect(abs(halfway.alpha - 0.5) < 0.001)
}
