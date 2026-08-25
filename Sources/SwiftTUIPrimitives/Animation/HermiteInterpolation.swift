// MARK: - VectorArithmetic scaling helper

extension VectorArithmetic {
  /// A copy of this value scaled by `factor`; the non-mutating spelling of
  /// ``scale(by:)`` for interpolation math that composes several terms.
  package func scaled(by factor: Double) -> Self {
    var copy = self
    copy.scale(by: factor)
    return copy
  }
}

// MARK: - Hermite interpolation

/// Cubic Hermite interpolation over ``VectorArithmetic`` values, the segment
/// interpolator behind the keyframe family's cubic keyframes (SwiftTUIViews).
///
/// Tangents are expressed in value units per unit of the normalized segment
/// parameter `t` in `0...1`. A caller holding velocities in value units per
/// second scales them by the segment duration first.
package enum HermiteInterpolation {
  /// The interpolated value at `t`.
  package static func value<V: VectorArithmetic>(
    from start: V,
    to end: V,
    startTangent: V,
    endTangent: V,
    at t: Double
  ) -> V {
    let t2 = t * t
    let t3 = t2 * t
    let h00 = 2 * t3 - 3 * t2 + 1
    let h10 = t3 - 2 * t2 + t
    let h01 = -2 * t3 + 3 * t2
    let h11 = t3 - t2
    var result = start.scaled(by: h00)
    result += startTangent.scaled(by: h10)
    result += end.scaled(by: h01)
    result += endTangent.scaled(by: h11)
    return result
  }

  /// The derivative of ``value(from:to:startTangent:endTangent:at:)`` with
  /// respect to `t`, in value units per unit `t`.
  package static func derivative<V: VectorArithmetic>(
    from start: V,
    to end: V,
    startTangent: V,
    endTangent: V,
    at t: Double
  ) -> V {
    let t2 = t * t
    let dh00 = 6 * t2 - 6 * t
    let dh10 = 3 * t2 - 4 * t + 1
    let dh01 = -6 * t2 + 6 * t
    let dh11 = 3 * t2 - 2 * t
    var result = start.scaled(by: dh00)
    result += startTangent.scaled(by: dh10)
    result += end.scaled(by: dh01)
    result += endTangent.scaled(by: dh11)
    return result
  }

  /// The Catmull-Rom tangent estimate at a keyframe: the chord between its
  /// neighbors divided by the time they span. A non-positive `span` yields a
  /// zero tangent (coincident keyframes carry no slope information).
  package static func catmullRomTangent<V: VectorArithmetic>(
    previous: V,
    next: V,
    span: Double
  ) -> V {
    guard span > 0 else { return .zero }
    return (next - previous).scaled(by: 1 / span)
  }
}
