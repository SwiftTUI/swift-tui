extension PatternFill.Paint {
  /// Returns `true` when `self` and `other` can be interpolated
  /// under the animation pipeline.  Cross-variant transitions
  /// (e.g. `.color` → `.linearGradient`) snap at the controller
  /// level — same-variant transitions interpolate via the wrapped
  /// type's own `animatableData`.
  public func isInterpolable(to other: PatternFill.Paint) -> Bool {
    switch (self, other) {
    case (.color, .color):
      return true
    case (.linearGradient(let a), .linearGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    case (.radialGradient(let a), .radialGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    default:
      return false
    }
  }

  /// Returns the interpolated paint at `progress` from `self` to
  /// `other`.  Cross-variant transitions snap to `other`.
  public func interpolated(
    to other: PatternFill.Paint,
    progress t: Double
  ) -> PatternFill.Paint {
    switch (self, other) {
    case (.color(var a), .color(let b)):
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .color(a)

    case (.linearGradient(var a), .linearGradient(let b)):
      guard a.animatableData.isInterpolable(to: b.animatableData) else {
        return .linearGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .linearGradient(a)

    case (.radialGradient(var a), .radialGradient(let b)):
      // RadialGradient.AnimatableData doesn't expose an
      // `isInterpolable` shim (unlike LinearGradient — see the
      // `AnimatablePair where ...` extension below), so check the
      // inner gradient's stop-count compatibility directly.
      guard
        a.gradient.animatableData.isInterpolable(
          to: b.gradient.animatableData
        )
      else {
        return .radialGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .radialGradient(a)

    default:
      // Cross-variant: snap to target.
      return other
    }
  }
}

extension AnimatablePair
where
  First == Gradient.AnimatableData,
  Second == LinearGradient.EndpointsData
{
  // Namespace hook for LinearGradient.AnimatableData interpolability
  // checks.  Gradient count mismatch is the only non-interpolable
  // case.
  public func isInterpolable(to other: Self) -> Bool {
    first.isInterpolable(to: other.first)
  }
}

extension PatternFill {
  /// Returns `true` when both `foreground` and `background` can
  /// be interpolated to their counterparts in `other` (same
  /// variants, compatible gradient stop counts, and matching
  /// background presence).
  public func isInterpolable(to other: PatternFill) -> Bool {
    guard glyph == other.glyph else { return false }
    guard foreground.isInterpolable(to: other.foreground) else { return false }
    switch (background, other.background) {
    case (nil, nil):
      return true
    case (let a?, let b?):
      return a.isInterpolable(to: b)
    default:
      return false
    }
  }

  /// Returns the pattern fill at `progress` from `self` to `other`.
  /// Glyph changes snap (glyph identity is not interpolable).
  /// Background presence must match or the entire pattern snaps.
  public func interpolated(
    to other: PatternFill,
    progress t: Double
  ) -> PatternFill {
    guard isInterpolable(to: other) else { return other }
    let newForeground = foreground.interpolated(to: other.foreground, progress: t)
    let newBackground: PatternFill.Paint?
    switch (background, other.background) {
    case (nil, nil):
      newBackground = nil
    case (let a?, let b?):
      newBackground = a.interpolated(to: b, progress: t)
    default:
      newBackground = other.background
    }
    return PatternFill(
      glyph: glyph,
      foreground: newForeground,
      background: newBackground
    )
  }
}

/// Bridge conformance so ``PatternFill`` can be wrapped by
/// ``AnyAnimatable``.  The animatable data is deliberately empty:
/// ``PatternFill`` is variant-based (color vs gradient vs gradient
/// shape), so cross-variant values have no single well-formed
/// `animatableData`.  The animation controller's type-erased
/// interpolation path intercepts ``PatternFill`` values before
/// invoking the generic `animatableData` arithmetic and routes them
/// through ``PatternFill/interpolated(to:progress:)`` instead — the
/// variant-aware helper defined above.
///
/// If a caller ever reaches the generic path with a ``PatternFill``
/// (e.g. by wrapping one in ``AnyAnimatable`` and then asking for
/// `animatableData` directly), interpolation becomes a no-op that
/// returns the source value: ``EmptyAnimatableData`` arithmetic
/// has nothing to carry.  The controller's special-case path
/// ensures that never happens in practice.
extension PatternFill: Animatable {
  public var animatableData: EmptyAnimatableData {
    get { EmptyAnimatableData() }
    set { /* intentionally unused */  }
  }
}
