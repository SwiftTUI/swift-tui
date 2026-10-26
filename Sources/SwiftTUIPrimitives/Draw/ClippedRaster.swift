#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

/// The integer drawing primitives shared by `BrailleCanvas` and the canvas
/// grid buffer, clipped to a `width` x `height` sample buffer before they
/// iterate.
///
/// Callers pass any `Int` geometry. Work is bounded by the buffer rather than
/// by the shape, no caller value takes part in trapping arithmetic (spans and
/// offsets are formed in `Int128`), and every sample `plot` receives lies in
/// the buffer. Inside the buffer each primitive lights exactly the samples its
/// unclipped walk lit. The exception is an ellipse outline that
/// `parametricOutline` declines, which `ellipseOutline` approximates instead.
package enum ClippedRaster {
  // MARK: - Lines

  /// Visits the in-buffer samples of the Bresenham line from `start` to
  /// `end`.
  ///
  /// With both endpoints in the buffer this is the classic walk. Otherwise
  /// only the major-axis steps inside the buffer are visited. The walk takes
  /// one major-axis step per iteration and its minor offset after `k` steps
  /// is `floor((2 * minor * k + major) / (2 * major))`; that value follows from
  /// the walk's error recurrence and is computed exactly in `UInt128`, so the
  /// clipped samples are the unclipped walk's samples inside the buffer.
  package static func line(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard width > 0, height > 0 else {
      return
    }
    func inside(_ point: (x: Int, y: Int)) -> Bool {
      point.x >= 0 && point.x < width && point.y >= 0 && point.y < height
    }
    if inside(start), inside(end) {
      bresenham(from: start, to: end, plot: plot)
      return
    }
    let dx = distance(start.x, end.x)
    let dy = distance(start.y, end.y)
    if dx >= dy {
      walk(
        major: (start.x, start.x < end.x, dx, width),
        minor: (start.y, start.y < end.y, dy, height)
      ) { plot($0, $1) }
    } else {
      walk(
        major: (start.y, start.y < end.y, dy, height),
        minor: (start.x, start.x < end.x, dx, width)
      ) { plot($1, $0) }
    }
  }

  private static func bresenham(
    from start: (x: Int, y: Int),
    to end: (x: Int, y: Int),
    plot: (Int, Int) -> Void
  ) {
    var x0 = start.x
    var y0 = start.y
    let x1 = end.x
    let y1 = end.y
    let dx = abs(x1 - x0)
    let sx = x0 < x1 ? 1 : -1
    let dy = -abs(y1 - y0)
    let sy = y0 < y1 ? 1 : -1
    var error = dx + dy

    while true {
      plot(x0, y0)
      if x0 == x1, y0 == y1 { break }
      let e2 = 2 * error
      if e2 >= dy {
        if x0 == x1 { break }
        error += dy
        x0 += sx
      }
      if e2 <= dx {
        if y0 == y1 { break }
        error += dx
        y0 += sy
      }
    }
  }

  /// `|a - b|`, exact for every pair of `Int`s.
  private static func distance(_ a: Int, _ b: Int) -> UInt {
    a <= b ? UInt(bitPattern: b &- a) : UInt(bitPattern: a &- b)
  }

  /// One axis of a clipped walk: its start, direction, step count and buffer
  /// extent.
  private typealias WalkAxis = (origin: Int, ascending: Bool, count: UInt, limit: Int)

  private static func walk(
    major: WalkAxis,
    minor: WalkAxis,
    plot: (_ major: Int, _ minor: Int) -> Void
  ) {
    guard let steps = stepRange(major) else {
      return
    }
    for step in steps {
      let offset = minorOffset(step: step, minor: minor.count, major: major.count)
      // The offset is at most the minor extent, so the true coordinate lies
      // between the endpoints and the wrapping arithmetic is exact.
      let minorCoordinate =
        minor.ascending
        ? minor.origin &+ Int(bitPattern: offset) : minor.origin &- Int(bitPattern: offset)
      guard minorCoordinate >= 0, minorCoordinate < minor.limit else {
        continue
      }
      let majorCoordinate =
        major.ascending
        ? major.origin &+ Int(bitPattern: step) : major.origin &- Int(bitPattern: step)
      plot(majorCoordinate, minorCoordinate)
    }
  }

  /// The steps `0...count` whose major coordinate lies in `0..<limit`.
  private static func stepRange(_ axis: WalkAxis) -> ClosedRange<UInt>? {
    let last = axis.limit - 1
    let lower: UInt
    let upper: UInt
    if axis.ascending {
      guard axis.origin <= last else {
        return nil
      }
      lower = axis.origin >= 0 ? 0 : axis.origin.magnitude
      // `last - origin` is in `0..<2^bitWidth`; wrapping makes it exact.
      upper = UInt(bitPattern: last &- axis.origin)
    } else {
      guard axis.origin >= 0 else {
        return nil
      }
      lower = axis.origin > last ? UInt(axis.origin - last) : 0
      upper = UInt(axis.origin)
    }
    let clampedUpper = min(upper, axis.count)
    return lower <= clampedUpper ? lower...clampedUpper : nil
  }

  /// `floor((2 * minor * step + major) / (2 * major))`: the walk's minor
  /// offset after `step` major steps, rounding a half up.
  private static func minorOffset(step: UInt, minor: UInt, major: UInt) -> UInt {
    guard major > 0 else {
      return 0
    }
    let (quotient, remainder) = (UInt128(step) * UInt128(minor))
      .quotientAndRemainder(dividingBy: UInt128(major))
    // `step <= major`, so the rounded quotient is at most `minor`.
    return UInt(quotient) + (remainder >= UInt128(major) - remainder ? 1 : 0)
  }

  // MARK: - Rectangles

  package static func fillRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    bufferWidth: Int,
    bufferHeight: Int,
    plot: (Int, Int) -> Void
  ) {
    guard width > 0, height > 0 else {
      return
    }
    let left = Int128(x)
    let right = left + Int128(width) - 1
    let top = Int128(y)
    guard let rows = clipped(top, top + Int128(height) - 1, limit: bufferHeight) else {
      return
    }
    for row in rows {
      plotRow(
        Int128(row), from: left, through: right, width: bufferWidth, height: bufferHeight,
        plot: plot)
    }
  }

  package static func strokeRect(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    bufferWidth: Int,
    bufferHeight: Int,
    plot: (Int, Int) -> Void
  ) {
    guard width > 0, height > 0 else {
      return
    }
    let left = Int128(x)
    let right = left + Int128(width) - 1
    let top = Int128(y)
    let bottom = top + Int128(height) - 1
    plotRow(top, from: left, through: right, width: bufferWidth, height: bufferHeight, plot: plot)
    if height > 1 {
      plotRow(
        bottom, from: left, through: right, width: bufferWidth, height: bufferHeight, plot: plot)
    }
    if height > 2 {
      plotColumn(
        left, from: top + 1, through: bottom - 1, width: bufferWidth, height: bufferHeight,
        plot: plot)
      if width > 1 {
        plotColumn(
          right, from: top + 1, through: bottom - 1, width: bufferWidth, height: bufferHeight,
          plot: plot)
      }
    }
  }

  // MARK: - Circles and ellipses

  /// Radii whose sum is at most this keep the original parametric or
  /// midpoint outline, whose work is proportional to the radius. A larger
  /// ellipse walks only its samples near the buffer (`parametricOutline`) and
  /// falls back to `ellipseOutline` where that is not bounded by the buffer. A
  /// larger circle uses `ellipseOutline`, which lights the midpoint circle's
  /// samples.
  package static func usesExactOutline(
    radiusX: Int,
    radiusY: Int,
    width: Int,
    height: Int
  ) -> Bool {
    Int128(radiusX) + Int128(radiusY) <= 4_096 + 4 * (Int128(width) + Int128(height))
  }

  /// Whether the ellipse's bounding box meets the buffer. Every outline
  /// sample and connecting line stays inside that box, so when it misses the
  /// buffer nothing would be drawn.
  package static func boundingBoxMeetsBuffer(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int,
    width: Int,
    height: Int
  ) -> Bool {
    let x = Int128(centerX)
    let y = Int128(centerY)
    return x - Int128(radiusX) < Int128(width) && x + Int128(radiusX) >= 0
      && y - Int128(radiusY) < Int128(height) && y + Int128(radiusY) >= 0
  }

  /// Fills a disc row by row with `floor(sqrt(r² - dy²))` half-spans, visiting
  /// only buffer rows.
  package static func fillCircle(
    centerX: Int,
    centerY: Int,
    radius: Int,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard radius >= 0 else {
      return
    }
    let x = Int128(centerX)
    let y = Int128(centerY)
    guard let rows = clipped(y - Int128(radius), y + Int128(radius), limit: height) else {
      return
    }
    for row in rows {
      let span = discHalfSpan(radius: radius, offset: Int(Int128(row) - y).magnitude)
      plotRow(
        Int128(row), from: x - Int128(span), through: x + Int128(span), width: width,
        height: height, plot: plot)
    }
  }

  /// `floor(sqrt(radius² - offset²))` for `0 <= offset <= radius`, exactly.
  ///
  /// Below 2^52 the operand is exact in `Double` and its correctly rounded
  /// root cannot reach the next integer, so the `Double` root is the floor.
  /// Above, the root can round up to `radius` itself, so one Newton step from
  /// the `Double` estimate and a final correction give the exact floor.
  private static func discHalfSpan(radius: Int, offset: UInt) -> Int {
    let r = UInt128(radius)
    let d = UInt128(offset)
    let value = (r - d) * (r + d)
    guard value >= 1 << 52 else {
      return Int(Double(value).squareRoot().rounded(.down))
    }
    var root = UInt128(Double(value).squareRoot())
    root = (root + value / root) / 2
    while root * root > value {
      root -= 1
    }
    while (root + 1) * (root + 1) <= value {
      root += 1
    }
    return Int(root)
  }

  /// Fills an ellipse row by row with `EllipseRasterization` half-spans,
  /// visiting only buffer rows. A zero radius draws the point or axis segment.
  package static func fillEllipse(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard radiusX >= 0, radiusY >= 0 else {
      return
    }
    let x = Int128(centerX)
    let y = Int128(centerY)
    if radiusY == 0 {
      plotRow(
        y, from: x - Int128(radiusX), through: x + Int128(radiusX), width: width, height: height,
        plot: plot)
      return
    }
    if radiusX == 0 {
      plotColumn(
        x, from: y - Int128(radiusY), through: y + Int128(radiusY), width: width, height: height,
        plot: plot)
      return
    }
    guard let rows = clipped(y - Int128(radiusY), y + Int128(radiusY), limit: height) else {
      return
    }
    for row in rows {
      let span = Int128(
        EllipseRasterization.halfSpan(
          radiusX: radiusX, radiusY: radiusY, offsetY: Int(Int128(row) - y)))
      plotRow(
        Int128(row), from: x - span, through: x + span, width: width, height: height, plot: plot)
    }
  }

  /// Visits the in-buffer samples of the parametric ellipse walk that
  /// `BrailleCanvas.strokeEllipse` and `CanvasGridBuffer.strokeEllipse` take
  /// below the switch-over, for an outline too large to walk whole. Returns
  /// `false`, having visited nothing, when that walk is not bounded by the
  /// buffer.
  ///
  /// The walk rounds `steps + 1` samples `(cx + round(rx * cos θᵢ), cy +
  /// round(ry * sin θᵢ))`, `θᵢ = 2π * i / steps` with
  /// `steps = max(minimumSteps, 4 * (rx + ry))`, and joins each sample to the
  /// one before it with `line`. Each sample lies within `1 + 1e-14 * r`
  /// (`r = max(rx, ry)`) of its true point: half a sample of rounding, plus a
  /// few units in the last place of the angle, `cos` and `sin`, the radius and
  /// the product. Consecutive true points are at most `π / 2` apart. A segment
  /// lights only samples in its endpoints' bounding box. So both true
  /// endpoints of a segment that lights a buffer sample lie within the margin
  /// `8 + 1e-13 * r` of the buffer. The indices whose true point lies there
  /// come from the angles where the curve meets the grown buffer, padded for
  /// the angle arithmetic. This evaluates the walk's own expressions for just
  /// those indices, so it lights exactly the samples the whole walk lights.
  ///
  /// Near the sharp ends of a flat ellipse the walk takes about
  /// `(rx + ry) / ry` samples per sample of arc, so the indices near the buffer
  /// can outnumber any bound on the buffer. When more than
  /// `16,384 + 16 * (width + height)` of them (the step count of the largest
  /// walk the switch-over admits) would be visited, or when `4 * (rx + ry)`
  /// overflows `Int`, where the whole walk traps, this returns `false`.
  package static func parametricOutline(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int,
    minimumSteps: Int,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) -> Bool {
    guard width > 0, height > 0, radiusX > 0, radiusY > 0 else {
      return false
    }
    let (sum, sumOverflow) = radiusX.addingReportingOverflow(radiusY)
    let (walkSteps, stepsOverflow) = sum.multipliedReportingOverflow(by: 4)
    guard !sumOverflow, !stepsOverflow else {
      return false
    }
    guard
      boundingBoxMeetsBuffer(
        centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, width: width,
        height: height)
    else {
      return true
    }
    let steps = max(minimumSteps, walkSteps)
    let radius = Double(max(radiusX, radiusY))
    let margin = Int128(8 + (radius * 1e-13).rounded(.up))
    // The buffer grown by the margin, relative to the center.
    let a = Int128(radiusX)
    let b = Int128(radiusY)
    let xLow = max(-margin - Int128(centerX), -a)
    let xHigh = min(Int128(width) - 1 + margin - Int128(centerX), a)
    let yLow = max(-margin - Int128(centerY), -b)
    let yHigh = min(Int128(height) - 1 + margin - Int128(centerY), b)
    guard xLow <= xHigh, yLow <= yHigh else {
      return true
    }
    // `acos(v / r)`, from the exact distances to both poles.
    func arccos(_ v: Int128, radius r: Int128) -> Double {
      2 * atan2(Double(r - v).squareRoot(), Double(r + v).squareRoot())
    }
    let twoPi = 2.0 * .pi
    let halfPi = Double.pi / 2
    // `rx * cos θ` in `xLow...xHigh`.
    let nearX = arccos(xHigh, radius: a)
    let farX = arccos(xLow, radius: a)
    let xArcs = [(nearX, farX), (twoPi - farX, twoPi - nearX)]
    // `ry * sin θ` in `yLow...yHigh`: `θ = π / 2 ± acos(sin θ)`.
    let nearY = arccos(yHigh, radius: b)
    let farY = arccos(yLow, radius: b)
    var yArcs = [(halfPi + nearY, halfPi + farY)]
    let lower = halfPi - farY
    let upper = halfPi - nearY
    if lower >= 0 {
      yArcs.append((lower, upper))
    } else if upper >= 0 {
      yArcs += [(0, upper), (lower + twoPi, twoPi)]
    } else {
      yArcs.append((lower + twoPi, upper + twoPi))
    }
    let indicesPerRadian = Double(steps) / twoPi
    let pad = 4 + Double(steps) * 1e-14
    var ranges: [(lower: Int128, upper: Int128)] = []
    for x in xArcs {
      for y in yArcs {
        let first = max(0, (max(x.0, y.0) * indicesPerRadian - pad).rounded(.down))
        let last = min(Double(steps), (min(x.1, y.1) * indicesPerRadian + pad).rounded(.up))
        if first <= last {
          ranges.append((Int128(first), min(Int128(last), Int128(steps))))
        }
      }
    }
    ranges.sort { $0.lower < $1.lower }
    var merged: [(lower: Int128, upper: Int128)] = []
    for range in ranges {
      if let last = merged.last, range.lower <= last.upper + 1 {
        merged[merged.count - 1].upper = max(last.upper, range.upper)
      } else {
        merged.append(range)
      }
    }
    let budget = 16_384 + 16 * (Int128(width) + Int128(height))
    guard merged.reduce(Int128(0), { $0 + $1.upper - $1.lower + 1 }) <= budget else {
      return false
    }
    // The walk's own expressions. Its samples fit `Int`: the radii sum to at
    // most `Int.max / 4` and the bounding box meets the buffer.
    let rx = Double(radiusX)
    let ry = Double(radiusY)
    let stepCount = Double(steps)
    func sample(_ i: Int) -> (x: Int, y: Int) {
      let angle = twoPi * Double(i) / stepCount
      return (
        centerX + Int((rx * cos(angle)).rounded()), centerY + Int((ry * sin(angle)).rounded())
      )
    }
    for range in merged {
      let first = Int(range.lower)
      var previous: (x: Int, y: Int)? = first > 0 ? sample(first - 1) : nil
      for i in first...Int(range.upper) {
        let point = sample(i)
        if let previous {
          line(from: previous, to: point, width: width, height: height, plot: plot)
        } else if point.x >= 0, point.x < width, point.y >= 0, point.y < height {
          plot(point.x, point.y)
        }
        previous = point
      }
    }
    return true
  }

  /// The outline of an ellipse too large for the parametric walk: in every
  /// buffer column and row the curve crosses, the crossing rounded to the
  /// nearest sample. Work is proportional to `width + height`. A zero radius
  /// draws the axis segment.
  ///
  /// With equal radii these are the midpoint circle's samples. The midpoint
  /// test picks `round(sqrt(r² - y²))` in each row of a steep octant and the
  /// column crossings in a flat octant. A crossing in the other direction lies
  /// within half a sample of one of those, so it repeats a sample already lit.
  /// This holds while each crossing rounds to its nearest sample, which
  /// `Double` guarantees below a radius of about 1.9e7 (no crossing lies
  /// exactly half-way). An ellipse's parametric walk rounds its samples along
  /// the curve instead and joins them with lines, so for an ellipse this
  /// outline can differ from that walk by a sample near each crossing.
  ///
  /// Each crossing is measured from the nearer pole, `r * t² / (1 + sqrt(1 -
  /// t²))`, which keeps its precision where the curve crosses the buffer.
  package static func ellipseOutline(
    centerX: Int,
    centerY: Int,
    radiusX: Int,
    radiusY: Int,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard radiusX > 0, radiusY > 0 else {
      fillEllipse(
        centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, width: width,
        height: height, plot: plot)
      return
    }
    let x = Int128(centerX)
    let y = Int128(centerY)
    let a = Int128(radiusX)
    let b = Int128(radiusY)
    func point(_ px: Int128, _ py: Int128) {
      if px >= 0, px < Int128(width), py >= 0, py < Int128(height) {
        plot(Int(px), Int(py))
      }
    }
    if let columns = clipped(x - a, x + a, limit: width) {
      for column in columns {
        let gap = poleGap(Double(Int128(column) - x) / Double(radiusX), radius: Double(radiusY))
        point(Int128(column), y - b + gap)
        point(Int128(column), y + b - gap)
      }
    }
    if let rows = clipped(y - b, y + b, limit: height) {
      for row in rows {
        let gap = poleGap(Double(Int128(row) - y) / Double(radiusY), radius: Double(radiusX))
        point(x - a + gap, Int128(row))
        point(x + a - gap, Int128(row))
      }
    }
  }

  /// `radius * (1 - sqrt(1 - t²))`, rounded, without cancellation.
  private static func poleGap(_ t: Double, radius: Double) -> Int128 {
    let s = min(1, abs(t))
    let root = ((1 - s) * (1 + s)).squareRoot()
    return Int128((radius * (s * s) / (1 + root)).rounded())
  }

  // MARK: - Spans

  /// `lower...upper` intersected with `0..<limit`.
  private static func clipped(_ lower: Int128, _ upper: Int128, limit: Int) -> ClosedRange<Int>? {
    let first = max(lower, 0)
    let last = min(upper, Int128(limit) - 1)
    return first <= last ? Int(first)...Int(last) : nil
  }

  private static func plotRow(
    _ y: Int128,
    from lower: Int128,
    through upper: Int128,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard y >= 0, y < Int128(height), let columns = clipped(lower, upper, limit: width) else {
      return
    }
    let row = Int(y)
    for column in columns {
      plot(column, row)
    }
  }

  private static func plotColumn(
    _ x: Int128,
    from lower: Int128,
    through upper: Int128,
    width: Int,
    height: Int,
    plot: (Int, Int) -> Void
  ) {
    guard x >= 0, x < Int128(width), let rows = clipped(lower, upper, limit: height) else {
      return
    }
    let column = Int(x)
    for row in rows {
      plot(column, row)
    }
  }
}
