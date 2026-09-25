/// A color pre-converted to the Oklab mixing space, for repeated perceptual
/// mixing against another prepared endpoint.
///
/// ``Color/interpolated(to:progress:method:)`` with the default `.perceptual`
/// method converts *both* endpoints to Oklab on every call. A gradient
/// sampler calls it once per cell with the same two stop colors, so the two
/// conversions are recomputed thousands of times per paint for identical
/// inputs. Preparing an endpoint hoists that conversion.
///
/// The hoist is bit-exact: ``Color/oklab()`` is a pure function of the color's
/// stored components, so the `OklabColor` computed here is the same value —
/// the same three doubles — that `interpolated` would compute per call, and
/// ``Color/perceptualMix(_:_:progress:)`` performs the remaining arithmetic
/// in the same order on the same operands. (A quantized lookup table by
/// progress would *not* be bit-exact and is deliberately not offered.)
package struct PreparedPerceptualMixEndpoint: Equatable, Sendable {
  /// The original color; its `alpha` and `profile` feed the mix exactly as
  /// `interpolated` reads them from `self` and `other`.
  package let color: Color
  /// `color.oklab()`, computed once.
  package let lab: OklabColor

  package init(_ color: Color) {
    self.color = color
    self.lab = color.oklab()
  }
}

extension Color {
  /// Mixes two prepared endpoints perceptually at `progress`.
  ///
  /// Produces a `Color` bit-identical to
  /// `lower.color.interpolated(to: upper.color, progress: progress)` with the
  /// default `.perceptual` method: the same clamp of `progress`, the same
  /// alpha lerp, the same per-channel Oklab lerps, and the same
  /// `_fromOklab(…).mapped(to: lower.profile, policy: .compressPerceptual)`
  /// tail. Keep this body in lockstep with the `.perceptual` case of
  /// ``Color/interpolated(to:progress:method:)``; the raster equivalence
  /// tests compare the two over a grid of colors and progress values.
  package static func perceptualMix(
    _ lower: PreparedPerceptualMixEndpoint,
    _ upper: PreparedPerceptualMixEndpoint,
    progress: Double
  ) -> Color {
    let t = _PrismNumeric.clamp(progress, 0.0, 1.0)
    let alpha = _PrismNumeric.lerp(lower.color.alpha, upper.color.alpha, t)
    let a = lower.lab
    let b = upper.lab
    let mixed = OklabColor(
      l: _PrismNumeric.lerp(a.l, b.l, t),
      a: _PrismNumeric.lerp(a.a, b.a, t),
      b: _PrismNumeric.lerp(a.b, b.b, t)
    )
    return Color._fromOklab(mixed, alpha: alpha, profile: lower.color.profile).mapped(
      to: lower.color.profile, policy: .compressPerceptual)
  }
}
