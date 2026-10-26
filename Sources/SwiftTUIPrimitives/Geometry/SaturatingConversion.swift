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

  /// `lhs * rhs`, saturating at `Int.min` and `Int.max` instead of trapping.
  package static func multiplying(_ lhs: Int, _ rhs: Int) -> Int {
    let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    guard overflow else {
      return product
    }
    return (lhs < 0) == (rhs < 0) ? .max : .min
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
  /// (Cohen-Sutherland). The crossed coordinate is set exactly, and an
  /// axis-parallel segment keeps its other coordinate exactly.
  ///
  /// With one endpoint inside the square, the other coordinate is
  /// interpolated from whichever endpoint is nearer that boundary. With both
  /// endpoints outside, or with a difference beyond the `Double` range, both
  /// can be far from the boundary, and that interpolation would cancel. Every
  /// crossing is then computed from the line through the original endpoints
  /// (`ClipLine`), so it lies within a few ulps of the larger of its own
  /// magnitude and the line's distance from the origin. Either way the
  /// clipped segment keeps its position even when the segment is vastly
  /// longer than the square.
  package static func clipped(
    from start: Point,
    to end: Point,
    within limit: Double
  ) -> (start: Point, end: Point)? {
    guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
      return nil
    }
    func outcode(_ point: Point) -> Int {
      (point.x < -limit ? 1 : 0) | (point.x > limit ? 2 : 0)
        | (point.y < -limit ? 4 : 0) | (point.y > limit ? 8 : 0)
    }
    var a = start
    var b = end
    var codeA = outcode(a)
    var codeB = outcode(b)
    let line =
      (codeA != 0 && codeB != 0) || !(end.x - start.x).isFinite || !(end.y - start.y).isFinite
      ? ClipLine(start, end) : nil
    // The segment's point on the vertical line `x` or the horizontal line `y`.
    func crossing(x: Double) -> Point {
      if let line {
        return Point(x: x, y: line.y(atX: x))
      }
      let (near, far) = abs(a.x - x) <= abs(b.x - x) ? (a, b) : (b, a)
      return Point(x: x, y: near.y + (far.y - near.y) * ((x - near.x) / (far.x - near.x)))
    }
    func crossing(y: Double) -> Point {
      if let line {
        return Point(x: line.x(atY: y), y: y)
      }
      let (near, far) = abs(a.y - y) <= abs(b.y - y) ? (a, b) : (b, a)
      return Point(x: near.x + (far.x - near.x) * ((y - near.y) / (far.y - near.y)), y: y)
    }
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
        point = crossing(y: limit)
      } else if outside & 4 != 0 {
        point = crossing(y: -limit)
      } else if outside & 2 != 0 {
        point = crossing(x: limit)
      } else {
        point = crossing(x: -limit)
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

  /// The part of a segment that a raster walk over a canvas at the origin
  /// draws, or `nil` when it draws nothing.
  ///
  /// - A segment with both endpoints in `[-limit, limit]²`, where the walk
  ///   converts coordinates exactly, is returned unchanged, bit for bit.
  /// - A segment with an endpoint in `[-reach, reach]²`, a square around the
  ///   canvas, is clipped to the limit.
  /// - A segment with both endpoints beyond the reach is clipped to the reach
  ///   instead. Its clipped endpoints then lie near the canvas, so their
  ///   rounding moves the line there by at most about `extent / reach`
  ///   samples, where a crossing at the limit would round to the limit's ulp.
  package static func rasterSegment(
    from start: Point,
    to end: Point,
    limit: Double,
    reach: Double
  ) -> (start: Point, end: Point)? {
    let reach = min(reach, limit)
    func within(_ point: Point, _ bound: Double) -> Bool {
      abs(point.x) <= bound && abs(point.y) <= bound
    }
    if within(start, reach) || within(end, reach) || (within(start, limit) && within(end, limit)) {
      return clipped(from: start, to: end, within: limit)
    }
    return clipped(from: start, to: end, within: reach)
  }

  /// The reach of ``rasterSegment(from:to:limit:reach:)`` for a canvas of
  /// `width` by `height` units at the origin: a power of two of at least
  /// 2^24 canvas extents.
  package static func reach(width: Int, height: Int) -> Double {
    let extent = Double(max(width, height, 1))
    return Double(sign: .plus, exponent: extent.exponent + 25, significand: 1)
  }

  /// The closed polygon through `points` clipped to the square
  /// `[-limit, limit]²` (Sutherland-Hodgman), or an empty array when a point
  /// is not finite or no part of it lies inside.
  ///
  /// Each crossing is computed from its edge's line, as for a segment with
  /// both endpoints outside, so it keeps its position however far the
  /// vertices lie. Clipping to a half-plane replaces the outside parts of the
  /// boundary with runs along the clip line. A closed loop made of an outside
  /// part and its run has winding number zero about every point inside, so a
  /// fill of the result inside the square, under either rule, is the fill of
  /// the polygon.
  package static func clippedPolygon(_ points: [Point], within limit: Double) -> [Point] {
    guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
      return []
    }
    var polygon = points
    for side in 0..<4 {
      guard let last = polygon.last else {
        return []
      }
      func inside(_ point: Point) -> Bool {
        switch side {
        case 0: point.x >= -limit
        case 1: point.x <= limit
        case 2: point.y >= -limit
        default: point.y <= limit
        }
      }
      func crossing(_ from: Point, _ to: Point) -> Point {
        let line = ClipLine(from, to)
        switch side {
        case 0: return Point(x: -limit, y: line.y(atX: -limit))
        case 1: return Point(x: limit, y: line.y(atX: limit))
        case 2: return Point(x: line.x(atY: -limit), y: -limit)
        default: return Point(x: line.x(atY: limit), y: limit)
        }
      }
      var output: [Point] = []
      output.reserveCapacity(polygon.count + 4)
      var previous = last
      for current in polygon {
        if inside(current) {
          if !inside(previous) {
            output.append(crossing(previous, current))
          }
          output.append(current)
        } else if inside(previous) {
          output.append(crossing(previous, current))
        }
        previous = current
      }
      polygon = output
    }
    return polygon
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

/// The line through two finite points as `a·x + b·y = c`, held in coordinates
/// scaled by `2^-exponent` so that the points' largest coordinate has a
/// magnitude in `1..<2` and no product overflows.
///
/// `c` is the points' cross product, computed with Kahan's compensated
/// determinant, so it is accurate to its own magnitude: the distance of the
/// line from the origin. Rounding `a` and `b` only turns the line about the
/// point nearest the origin. A point computed on the line therefore lies within
/// a few ulps of the larger of its own magnitude and that distance, however
/// far the two points are. A power-of-two scale changes only exponents, so the
/// computation commutes with scaling the points by a power of two.
private struct ClipLine {
  private let start: Point
  private let end: Point
  private let exponent: Int
  private let a: Double
  private let b: Double
  private let c: Double

  init(_ start: Point, _ end: Point) {
    self.start = start
    self.end = end
    let largest = max(abs(start.x), abs(start.y), abs(end.x), abs(end.y))
    let exponent = largest > 0 ? largest.exponent : 0
    self.exponent = exponent
    let x1 = Self.scaled(start.x, by: -exponent)
    let y1 = Self.scaled(start.y, by: -exponent)
    let x2 = Self.scaled(end.x, by: -exponent)
    let y2 = Self.scaled(end.y, by: -exponent)
    a = y2 - y1
    b = x1 - x2
    // x1·y2 − y1·x2 = (x1·y2 − w) + (w − y1·x2), with w = y1·x2 rounded; each
    // fused term is rounded once, and the second is exact.
    let w = y1 * x2
    c = (-w).addingProduct(x1, y2) + w.addingProduct(-y1, x2)
  }

  /// The line's y at `x`, clamped to the segment's y range.
  func y(atX x: Double) -> Double {
    if start.y == end.y {
      return start.y
    }
    guard b != 0 else {
      // Scaling merged the two x coordinates: the segment is vertical to
      // within the scale's resolution.
      return abs(start.x - x) <= abs(end.x - x) ? start.y : end.y
    }
    let scaledY = c.addingProduct(-a, Self.scaled(x, by: -exponent)) / b
    return min(max(Self.scaled(scaledY, by: exponent), min(start.y, end.y)), max(start.y, end.y))
  }

  /// The line's x at `y`, clamped to the segment's x range.
  func x(atY y: Double) -> Double {
    if start.x == end.x {
      return start.x
    }
    guard a != 0 else {
      return abs(start.y - y) <= abs(end.y - y) ? start.x : end.x
    }
    let scaledX = c.addingProduct(-b, Self.scaled(y, by: -exponent)) / a
    return min(max(Self.scaled(scaledX, by: exponent), min(start.x, end.x)), max(start.x, end.x))
  }

  /// `value · 2^exponent`, correctly rounded.
  private static func scaled(_ value: Double, by exponent: Int) -> Double {
    Double(sign: .plus, exponent: exponent, significand: value)
  }
}
