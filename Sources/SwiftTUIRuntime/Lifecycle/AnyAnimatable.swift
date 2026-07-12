package import SwiftTUICore

/// Type-erased wrapper around a value conforming to ``Animatable``.
///
/// The animation controller stores heterogeneous animatable values
/// per ``AnimatableSlot`` — opacity is a `Double`, foreground style
/// is a `LinearGradient` or a `Color` or a `TileStyle`, padding is
/// an `EdgeInsets`, and so on — and needs a uniform storage
/// representation that supports equality, same-type interpolation,
/// and unwrapping back to the original type at apply time.  This is
/// that representation.
///
/// ## Semantics
///
/// - **Equality:** two ``AnyAnimatable`` are equal iff they wrap the
///   same concrete type and the wrapped values are equal by that
///   type's own ``Equatable`` conformance.  Different wrapped types
///   compare as not-equal even if their ``animatableData`` happen to
///   coincide.
/// - **Interpolation:** ``interpolated(to:progress:)`` returns `nil`
///   when the wrapped types don't match.  The controller treats
///   `nil` as a snap signal and writes the target value directly
///   without interpolating.  Same-type interpolation uses the
///   wrapped type's ``animatableData`` arithmetic: `a + (b - a) * t`.
///   ``TileStyle`` is a special case — the variant-based type has
///   no meaningful generic ``animatableData``, so the box intercepts
///   it and dispatches to the bespoke
///   ``TileStyle/interpolated(to:progress:)`` helper.
/// - **NaN defence:** if `progress` is non-finite the box returns the
///   target value directly rather than producing `.nan` deltas that
///   would downstream trap inside ``OklabColor.init``.
/// - **Thread safety:** the wrapped value must be `Sendable`, which
///   is enforced by the `Equatable & Sendable & Animatable` bound on
///   ``init(_:)``.
package struct AnyAnimatable: Equatable, Sendable {
  private let box: any _AnyAnimatableBox

  package init<T: Animatable & Equatable & Sendable>(_ value: T) {
    self.box = _AnimatableBox(value)
  }

  package func unwrap<T: Animatable & Equatable & Sendable>(as _: T.Type) -> T? {
    box.unwrap(as: T.self)
  }

  package func interpolated(
    to other: AnyAnimatable,
    progress: Double
  ) -> AnyAnimatable? {
    box.interpolated(to: other.box, progress: progress)
  }

  package static func == (lhs: AnyAnimatable, rhs: AnyAnimatable) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }
}

/// Reports whether two animatable values are gradients whose stop counts
/// differ, which makes their `animatableData` structurally non-interpolable.
private func gradientStopCountDiffers<T>(_ lhs: T, _ rhs: T) -> Bool {
  if let lhs = lhs as? LinearGradient, let rhs = rhs as? LinearGradient {
    return lhs.gradient.stops.count != rhs.gradient.stops.count
  }
  if let lhs = lhs as? RadialGradient, let rhs = rhs as? RadialGradient {
    return lhs.gradient.stops.count != rhs.gradient.stops.count
  }
  if let lhs = lhs as? Gradient, let rhs = rhs as? Gradient {
    return lhs.stops.count != rhs.stops.count
  }
  return false
}

private protocol _AnyAnimatableBox: Sendable {
  func isEqual(to other: any _AnyAnimatableBox) -> Bool
  func unwrap<T>(as _: T.Type) -> T?
  func interpolated(
    to other: any _AnyAnimatableBox,
    progress: Double
  ) -> AnyAnimatable?
}

private struct _AnimatableBox<T: Animatable & Equatable & Sendable>: _AnyAnimatableBox {
  let value: T

  init(_ value: T) {
    self.value = value
  }

  func isEqual(to other: any _AnyAnimatableBox) -> Bool {
    guard let other = other as? _AnimatableBox<T> else { return false }
    return value == other.value
  }

  func unwrap<U>(as _: U.Type) -> U? {
    value as? U
  }

  func interpolated(
    to other: any _AnyAnimatableBox,
    progress t: Double
  ) -> AnyAnimatable? {
    guard let other = other as? _AnimatableBox<T> else { return nil }

    // Defensive: non-finite `t` upstream (e.g. a curve evaluator
    // returning .nan) would otherwise propagate into
    // `animatableData` arithmetic and trap inside color-space
    // constructors.  Snap to the target instead.
    guard t.isFinite else {
      return AnyAnimatable(other.value)
    }

    // Special case: ``TileStyle`` is variant-based (color vs
    // linear vs radial vs tile pattern).  Cross-variant values have no
    // single well-formed ``animatableData`` — Phase 2 implemented a
    // bespoke ``TileStyle.interpolated(to:progress:)`` that
    // handles the variant dispatch.  Route through it instead of
    // letting the generic ``animatableData`` path run against the
    // ``EmptyAnimatableData`` bridge.
    if let selfTile = value as? TileStyle,
      let otherTile = other.value as? TileStyle
    {
      return AnyAnimatable(
        selfTile.interpolated(to: otherTile, progress: t)
      )
    }

    // Gradients are variant in stop count: interpolating between differing
    // stop counts collapses the stops-array subtraction to empty, and the
    // ``Gradient`` setter then silently drops it (its own count guard), which
    // would leave a malformed old-stops + interpolated-endpoints gradient.
    // Snap to the target instead, mirroring the ``TileStyle`` handling above.
    if gradientStopCountDiffers(value, other.value) {
      return AnyAnimatable(other.value)
    }

    // Generic interpolation via animatableData arithmetic.
    var fromData = value.animatableData
    var delta = other.value.animatableData
    delta -= fromData
    delta.scale(by: t)
    fromData += delta
    var result = value
    result.animatableData = fromData
    return AnyAnimatable(result)
  }
}
