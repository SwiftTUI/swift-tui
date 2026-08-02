/// The ``Animatable`` conformance of ``Color`` uses OKLab components.
/// The animation controller uses linear ``VectorArithmetic`` during interpolation.
/// OKLab makes this arithmetic correspond to perceptually linear color transitions.
/// In L-a-b space, `a + (b - a) * t` equals the result of ``Color/interpolated(to:progress:method:)`` with ``Color/MixingMethod/perceptual``.
/// Thus, animation keeps the existing visual behavior.
/// This behavior comes from Phase 6 of `ANIMATION_PLAN.md`.
///
/// The getter delegates to ``Color/oklab()``.
/// The setter reconstructs a color through ``Color/_fromOklab(_:alpha:profile:)``.
/// Then it maps the gamut to the source profile with ``Color/GamutMappingPolicy/compressPerceptual``.
/// The `perceptual` interpolation path uses the same sequence at `Color.swift:1615-1624`.
///
/// The setter uses `self.profile` for the OKLab reconstruction and the gamut map.
/// Callers must supply one profile for a cross-profile animation.
/// The setter projects the animation result through the profile of the receiver.
/// Different profiles for `from` and `to` can cause small hue changes for non-sRGB receivers.
/// In practice, `from` and `to` share a profile because they come from the same `Color` literal family.
///
/// Each setter call runs `Color._fromOklab(...)` and then `.mapped(to:policy: .compressPerceptual)`.
/// Thus, one setter call per frame runs the full OKLab → sRGB → gamut-compress chain each frame.
/// Property-slot animation makes one setter call for each affected identity in each frame.
/// For repeated read-modify-write cycles, read `animatableData` once, mutate it in place, and set it once.
extension Color: Animatable {
  // Layout: ((l, a), (b, alpha)) — matches the getter below
  // so that linear VectorArithmetic arithmetic over the four Doubles
  // interpolates perceptually in OKLab space.
  public typealias AnimatableData = AnimatablePair<
    AnimatablePair<Double, Double>,
    AnimatablePair<Double, Double>
  >

  public var animatableData: AnimatableData {
    get {
      let lab = self.oklab()
      return AnimatablePair(
        AnimatablePair(lab.l, lab.a),
        AnimatablePair(lab.b, self.alpha)
      )
    }
    set {
      let lab = OklabColor(
        l: newValue.first.first,
        a: newValue.first.second,
        b: newValue.second.first
      )
      let alpha = newValue.second.second
      let reconstructed = Color._fromOklab(
        lab,
        alpha: alpha,
        profile: self.profile
      )
      self = reconstructed.mapped(
        to: self.profile,
        policy: .compressPerceptual
      )
    }
  }
}
