/// ``Color``'s ``Animatable`` conformance uses OKLab components so
/// that linear ``VectorArithmetic`` arithmetic — which is what the
/// animation controller performs during interpolation —
/// corresponds to perceptually linear color transitions.  OKLab is
/// designed so that `a + (b - a) * t` in L-a-b space equals the
/// result of ``Color/interpolated(to:progress:method:)`` with
/// ``Color/MixingMethod/perceptual``, preserving the existing
/// visual behavior of color animation introduced in
/// `ANIMATION_PLAN.md`'s Phase 6.
///
/// The getter delegates to ``Color/oklab()``; the setter
/// reconstructs a color via ``Color/_fromOklab(_:alpha:profile:)``
/// and gamut-maps it back to the source profile with
/// ``Color/GamutMappingPolicy/compressPerceptual`` — the same
/// sequence the existing `perceptual` interpolation path uses at
/// `Color.swift:1615-1624`.
///
/// Profile preservation: the setter uses `self.profile` as the
/// destination profile for both the OKLab reconstruction and the
/// gamut map.  Cross-profile animation is caller-enforced — the
/// setter will silently re-project an animation result through the
/// receiver's profile, which may produce subtle hue drift for non-
/// sRGB receivers if the `from`/`to` originated from different
/// profiles.  In practice, the `from` and `to` of an animation
/// always share a profile because they originate from the same
/// `Color` literal family.
///
/// Cost model: every setter call runs `Color._fromOklab(...)` followed
/// by `.mapped(to:policy: .compressPerceptual)`, so an animation that
/// drives this setter once per frame pays the full OKLab → sRGB →
/// gamut-compress chain per frame.  Acceptable for Phase 3's property-
/// slot animation (one setter call per affected identity per frame),
/// but callers performing repeated read-modify-write cycles in a tight
/// loop should batch: read `animatableData` once, mutate in place, set
/// once.
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
