/// Overflow-free integer conversions for caller- and host-supplied numbers.
///
/// Geometry, input and diagnostics code converts `Double` values it does not
/// control into `Int` cells, samples and counters. `Int(_:)` traps for NaN,
/// infinity and any value outside `Int`'s range, so every such conversion goes
/// through here instead. A converted value saturates at half of `Int`'s range,
/// which leaves room to add or subtract another in-range coordinate without
/// overflowing.
package enum SaturatingConversion {
  /// The smallest converted value. NaN converts here, a cell outside every
  /// finite region.
  package static let lowerBound = Int.min / 2

  /// The largest converted value.
  package static let upperBound = Int.max / 2

  /// Rounds `value` by `rule` and converts it to `Int`, saturating at
  /// `lowerBound` and `upperBound`. NaN converts to `lowerBound`.
  ///
  /// Inside the bounds the result equals `Int(value.rounded(rule))`, so finite
  /// in-range output is unchanged.
  package static func int(
    _ value: Double,
    rounding rule: FloatingPointRoundingRule
  ) -> Int {
    guard !value.isNaN else {
      return lowerBound
    }
    let rounded = value.rounded(rule)
    if rounded <= Double(lowerBound) {
      return lowerBound
    }
    if rounded >= Double(upperBound) {
      return upperBound
    }
    return Int(rounded)
  }

  /// `lhs + rhs`, saturating at `Int.min` and `Int.max` instead of trapping.
  package static func adding(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    guard overflow else {
      return sum
    }
    return rhs < 0 ? .min : .max
  }

  /// `lhs - rhs`, saturating at `Int.min` and `Int.max` instead of trapping.
  package static func subtracting(_ lhs: Int, _ rhs: Int) -> Int {
    let (difference, overflow) = lhs.subtractingReportingOverflow(rhs)
    guard overflow else {
      return difference
    }
    return rhs < 0 ? .max : .min
  }

  /// `-value`; `Int.min`, which has no negation, maps to `Int.max`.
  package static func negated(_ value: Int) -> Int {
    subtracting(0, value)
  }

  /// The sum of `values`, added in order with each step saturating like
  /// `adding(_:_:)`. Equal to `values.reduce(0, +)` whenever no partial sum
  /// overflows.
  package static func sum(_ values: some Sequence<Int>) -> Int {
    values.reduce(0, adding)
  }

  /// `(lhs * rhs) / divisor` without an intermediate overflow, for
  /// non-negative operands and a positive divisor, saturating at `Int.max`.
  /// Equal to the plain expression whenever the product fits in `Int`.
  package static func multiplied(_ lhs: Int, by rhs: Int, dividedBy divisor: Int) -> Int {
    let product = lhs.multipliedFullWidth(by: rhs)
    // The quotient fits in `Int` exactly when the product is below
    // 2^63 · divisor, that is when `product >> 63` is below the divisor.
    guard 2 * product.high + Int(product.low >> 63) < divisor else {
      return .max
    }
    return divisor.dividingFullWidth(product).quotient
  }
}

/// Overflow-free conversions into `Duration` for caller-supplied seconds,
/// speeds and sums.
///
/// `Duration.seconds(_: Double)` and `Duration * Double` trap for NaN,
/// infinity and magnitudes past their attosecond range, and
/// `Duration.components` traps past `Int64.max` seconds. These conversions
/// saturate at `durationBound` instead, and NaN converts to zero.
extension SaturatingConversion {
  /// The longest duration a conversion produces: 2^62 seconds, about 146
  /// billion years. It is half of `Int64`'s range, so a bounded duration keeps
  /// readable `components`, and adding one to another bounded duration or to a
  /// clock's current instant stays representable.
  package static let durationBound = Duration.seconds(durationBoundSeconds)

  /// `durationBound` in whole seconds.
  package static let durationBoundSeconds: Int64 = 1 << 62

  /// `Duration.seconds(seconds)`, saturating at ±`durationBound`. NaN
  /// converts to zero. Inside the bound the result is exactly
  /// `.seconds(seconds)`.
  package static func duration(seconds: Double) -> Duration {
    guard !seconds.isNaN else {
      return .zero
    }
    let limit = Double(durationBoundSeconds)
    if seconds >= limit {
      return durationBound
    }
    if seconds <= -limit {
      return .zero - durationBound
    }
    return .seconds(seconds)
  }

  /// `duration * factor`, saturating at ±`durationBound`. A NaN product
  /// (a NaN factor, or zero times infinity) converts to zero. Inside the bound
  /// the result is exactly `duration * factor`.
  package static func duration(_ duration: Duration, scaledBy factor: Double) -> Duration {
    // `Duration / Duration` is a `Double` quotient and cannot trap.
    let seconds = duration / .seconds(1) * factor
    guard !seconds.isNaN else {
      return .zero
    }
    let limit = Double(durationBoundSeconds)
    if seconds >= limit {
      return durationBound
    }
    if seconds <= -limit {
      return .zero - durationBound
    }
    return duration * factor
  }

  /// `lhs + rhs` with each operand and the sum clamped to ±`durationBound`.
  /// Equal to `lhs + rhs` whenever the operands and the sum are inside the
  /// bound.
  package static func adding(_ lhs: Duration, _ rhs: Duration) -> Duration {
    clamped(clamped(lhs) + clamped(rhs))
  }

  /// `duration` clamped to ±`durationBound`.
  package static func clamped(_ duration: Duration) -> Duration {
    min(max(duration, .zero - durationBound), durationBound)
  }
}

/// Clipping of continuous line segments before their endpoints are converted
/// to integers.
package enum SegmentClipping {
  /// The part of the segment from `start` to `end` inside the square
  /// `[-limit, limit]²`, or `nil` when an endpoint is not finite or no part of
  /// the segment lies inside.
  ///
  /// A segment already inside the square is returned unchanged, bit for bit.
  /// Otherwise each outside endpoint moves onto the boundary it crosses
  /// (Cohen-Sutherland). The crossed coordinate is set exactly and the other
  /// is interpolated from whichever endpoint is nearer that boundary, so the
  /// clipped segment keeps its position even when the segment is vastly longer
  /// than the square.
  ///
  /// Finite endpoints of opposite sign beyond half the `Double` range have no
  /// representable difference. Such a segment is clipped at half scale: halving
  /// changes only exponents, so the halved segment has the same outcodes
  /// against the halved square and the same crossing fractions, and its clipped
  /// endpoints double back exactly.
  package static func clipped(
    from start: Point,
    to end: Point,
    within limit: Double
  ) -> (start: Point, end: Point)? {
    guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
      return nil
    }
    guard (end.x - start.x).isFinite, (end.y - start.y).isFinite else {
      func scaled(_ point: Point, by factor: Double) -> Point {
        Point(x: point.x * factor, y: point.y * factor)
      }
      // Halved differences are at most `greatestFiniteMagnitude`.
      guard
        let halved = clipped(
          from: scaled(start, by: 0.5), to: scaled(end, by: 0.5), within: limit / 2)
      else {
        return nil
      }
      return (scaled(halved.start, by: 2), scaled(halved.end, by: 2))
    }
    func outcode(_ point: Point) -> Int {
      (point.x < -limit ? 1 : 0) | (point.x > limit ? 2 : 0)
        | (point.y < -limit ? 4 : 0) | (point.y > limit ? 8 : 0)
    }
    // The segment's point on the vertical line `x` or the horizontal line `y`.
    func crossing(x: Double, _ a: Point, _ b: Point) -> Point {
      let (near, far) = abs(a.x - x) <= abs(b.x - x) ? (a, b) : (b, a)
      return Point(x: x, y: near.y + (far.y - near.y) * ((x - near.x) / (far.x - near.x)))
    }
    func crossing(y: Double, _ a: Point, _ b: Point) -> Point {
      let (near, far) = abs(a.y - y) <= abs(b.y - y) ? (a, b) : (b, a)
      return Point(x: near.x + (far.x - near.x) * ((y - near.y) / (far.y - near.y)), y: y)
    }
    var a = start
    var b = end
    var codeA = outcode(a)
    var codeB = outcode(b)
    // Each pass fixes one coordinate of one endpoint; four passes reach the
    // square unless rounding leaves a point a hair outside a corner.
    for _ in 0..<8 {
      if codeA | codeB == 0 {
        return (a, b)
      }
      if codeA & codeB != 0 {
        return nil
      }
      let outside = codeA != 0 ? codeA : codeB
      let point: Point
      if outside & 8 != 0 {
        point = crossing(y: limit, a, b)
      } else if outside & 4 != 0 {
        point = crossing(y: -limit, a, b)
      } else if outside & 2 != 0 {
        point = crossing(x: limit, a, b)
      } else {
        point = crossing(x: -limit, a, b)
      }
      if outside == codeA {
        a = point
        codeA = outcode(a)
      } else {
        b = point
        codeB = outcode(b)
      }
    }
    func clamped(_ point: Point) -> Point {
      Point(x: min(max(point.x, -limit), limit), y: min(max(point.y, -limit), limit))
    }
    return (clamped(a), clamped(b))
  }

  /// The interval of `t` in `0...1` whose points `start + t * (end - start)`
  /// lie in the closed box (Liang-Barsky), or `nil` when none do or the
  /// segment's extent is not finite.
  package static func parameterInterval(
    from start: Point,
    to end: Point,
    minX: Double,
    minY: Double,
    maxX: Double,
    maxY: Double
  ) -> (lower: Double, upper: Double)? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    guard dx.isFinite, dy.isFinite else {
      return nil
    }
    var lower = 0.0
    var upper = 1.0
    for (p, q) in [
      (-dx, start.x - minX), (dx, maxX - start.x), (-dy, start.y - minY), (dy, maxY - start.y),
    ] {
      guard q.isFinite else {
        return nil
      }
      if p == 0 {
        if q < 0 {
          return nil
        }
        continue
      }
      let r = q / p
      if p < 0 {
        if r > upper {
          return nil
        }
        lower = max(lower, r)
      } else {
        if r < lower {
          return nil
        }
        upper = min(upper, r)
      }
    }
    return lower <= upper ? (lower, upper) : nil
  }
}
