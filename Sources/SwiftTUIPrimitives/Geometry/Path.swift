/// The winding rule used to decide a path's filled interior.
public enum FillRule: Equatable, Sendable {
  /// A point is inside when a ray to infinity crosses the path an odd
  /// number of times (ignores edge direction).
  case evenOdd
  /// A point is inside when the signed crossing total is non-zero
  /// (accounts for edge direction).
  case nonZero
}

/// A continuous geometric path in cell-space coordinates.
///
/// Used both for pointer hit testing (``contains(_:fillRule:)``) and, when
/// carried by ``ShapeGeometry/path(_:_:)``, for rendering. Curves
/// (``Element/quadCurve(to:control:)`` and ``Element/curve(to:control1:control2:)``)
/// become polylines on demand through ``flattened(tolerance:)``.
/// One `Path` type prevents differences between hit testing and rendering.
public struct Path: Equatable, Sendable {
  public enum Element: Equatable, Sendable {
    case move(to: Point)
    case line(to: Point)
    case quadCurve(to: Point, control: Point)
    case curve(to: Point, control1: Point, control2: Point)
    case close
  }

  /// Authored elements, including an explicit origin move for a leading segment.
  public private(set) var elements: [Element]

  public init() {
    elements = []
  }

  public init(_ elements: [Element]) {
    self.elements = elements
    for (index, element) in elements.enumerated() {
      switch element {
      case .close: continue
      case .move: return
      case .line, .quadCurve, .curve:
        self.elements.insert(.move(to: .zero), at: index)
        return
      }
    }
  }

  /// Builds a path imperatively, SwiftUI-style.
  public init(_ build: (inout Path) -> Void) {
    self.init()
    build(&self)
  }

  /// A rectangular path.
  public init(_ rect: Rect) {
    self.init()
    addRect(rect)
  }

  /// A rounded-rectangle path with the given corner radius.
  public init(roundedRect rect: Rect, cornerRadius: Double) {
    self.init()
    addRoundedRect(in: rect, cornerRadius: cornerRadius)
  }

  /// An ellipse inscribed in the given rect.
  public init(ellipseIn rect: Rect) {
    self.init()
    addEllipse(in: rect)
  }

  // MARK: - Construction

  public mutating func move(to point: Point) {
    elements.append(.move(to: point))
  }

  public mutating func addLine(to point: Point) {
    ensureInitialMove()
    elements.append(.line(to: point))
  }

  public mutating func addQuadCurve(to point: Point, control: Point) {
    ensureInitialMove()
    elements.append(.quadCurve(to: point, control: control))
  }

  public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
    ensureInitialMove()
    elements.append(.curve(to: point, control1: control1, control2: control2))
  }

  private mutating func ensureInitialMove() {
    // Leading closes do not establish a pen. Materialize its implicit origin
    // so translation and animation transform every point in the path.
    for element in elements {
      if case .close = element { continue }
      return
    }
    move(to: .zero)
  }

  public mutating func close() {
    elements.append(.close)
  }

  /// SwiftUI-named alias for ``close()``.
  public mutating func closeSubpath() {
    elements.append(.close)
  }

  public mutating func addRect(_ rect: Rect) {
    let minX = rect.origin.x
    let minY = rect.origin.y
    move(to: Point(x: minX, y: minY))
    addLine(to: Point(x: rect.maxX, y: minY))
    addLine(to: Point(x: rect.maxX, y: rect.maxY))
    addLine(to: Point(x: minX, y: rect.maxY))
    close()
  }

  public mutating func addRoundedRect(in rect: Rect, cornerRadius: Double) {
    let minX = rect.origin.x
    let minY = rect.origin.y
    let maxX = rect.maxX
    let maxY = rect.maxY
    let r = min(max(0, cornerRadius), min(rect.size.width, rect.size.height) / 2)
    if r <= 0 {
      addRect(rect)
      return
    }
    let o = r * Self.kappa
    move(to: Point(x: maxX, y: (minY + maxY) / 2))
    addLine(to: Point(x: maxX, y: maxY - r))
    addCurve(
      to: Point(x: maxX - r, y: maxY),
      control1: Point(x: maxX, y: maxY - r + o),
      control2: Point(x: maxX - r + o, y: maxY))
    addLine(to: Point(x: minX + r, y: maxY))
    addCurve(
      to: Point(x: minX, y: maxY - r),
      control1: Point(x: minX + r - o, y: maxY),
      control2: Point(x: minX, y: maxY - r + o))
    addLine(to: Point(x: minX, y: minY + r))
    addCurve(
      to: Point(x: minX + r, y: minY),
      control1: Point(x: minX, y: minY + r - o),
      control2: Point(x: minX + r - o, y: minY))
    addLine(to: Point(x: maxX - r, y: minY))
    addCurve(
      to: Point(x: maxX, y: minY + r),
      control1: Point(x: maxX - r + o, y: minY),
      control2: Point(x: maxX, y: minY + r - o))
    close()
  }

  public mutating func addEllipse(in rect: Rect) {
    let cx = rect.origin.x + rect.size.width / 2
    let cy = rect.origin.y + rect.size.height / 2
    let rx = rect.size.width / 2
    let ry = rect.size.height / 2
    let ox = rx * Self.kappa
    let oy = ry * Self.kappa
    move(to: Point(x: cx + rx, y: cy))
    addCurve(
      to: Point(x: cx, y: cy + ry),
      control1: Point(x: cx + rx, y: cy + oy),
      control2: Point(x: cx + ox, y: cy + ry))
    addCurve(
      to: Point(x: cx - rx, y: cy),
      control1: Point(x: cx - ox, y: cy + ry),
      control2: Point(x: cx - rx, y: cy + oy))
    addCurve(
      to: Point(x: cx, y: cy - ry),
      control1: Point(x: cx - rx, y: cy - oy),
      control2: Point(x: cx - ox, y: cy - ry))
    addCurve(
      to: Point(x: cx + rx, y: cy),
      control1: Point(x: cx + ox, y: cy - ry),
      control2: Point(x: cx + rx, y: cy - oy))
    close()
  }

  // MARK: - Queries

  /// Whether `point` lies inside (or on the boundary of) the filled path
  /// under the given `fillRule`. The default matches shape rendering's
  /// non-zero winding rule; pass `.evenOdd` for an explicit parity fill.
  /// Like a fill, the test closes each open subpath with a straight edge back
  /// to its start.
  public func contains(_ point: Point, fillRule: FillRule = .nonZero) -> Bool {
    guard point.x.isFinite, point.y.isFinite else { return false }
    var crossings = 0
    var winding = 0
    for segment in closedSegments() {
      if pointIsOnSegment(point, segment) {
        return true
      }
      let direction = rayCrossingDirection(from: point, segment: segment)
      if direction != 0 {
        crossings += 1
        winding += direction
      }
    }
    switch fillRule {
    case .evenOdd:
      return crossings % 2 != 0
    case .nonZero:
      return winding != 0
    }
  }

  /// The axis-aligned bounding rect over all anchor and control points
  /// (a conservative superset of the curve hull), or `nil` when empty.
  public var boundingRect: Rect? {
    guard hasFiniteCoordinates else { return nil }
    var minX: Double?
    var minY: Double?
    var maxX: Double?
    var maxY: Double?

    func extend(_ point: Point) {
      minX = min(minX ?? point.x, point.x)
      minY = min(minY ?? point.y, point.y)
      maxX = max(maxX ?? point.x, point.x)
      maxY = max(maxY ?? point.y, point.y)
    }

    var current = Point.zero
    var subpathStart = Point.zero
    for element in elements {
      switch element {
      case .move(let value):
        extend(value)
        current = value
        subpathStart = value
      case .line(let value):
        extend(current)
        extend(value)
        current = value
      case .quadCurve(let to, let control):
        extend(current)
        current = to
        extend(to)
        extend(control)
      case .curve(let to, let control1, let control2):
        extend(current)
        current = to
        extend(to)
        extend(control1)
        extend(control2)
      case .close:
        current = subpathStart
      }
    }

    guard let minX, let minY, let maxX, let maxY else {
      return nil
    }

    return Rect(
      origin: Point(x: minX, y: minY),
      size: Size(width: maxX - minX, height: maxY - minY)
    )
  }

  /// Returns the part of the path between two fractions of its length.
  ///
  /// The fractions are of the path's whole length, measured along its
  /// subpaths in the order they were added, as in SwiftUI. Both are clamped to
  /// `0...1`. The result is empty when `from` is not less than `to` or when
  /// either is NaN. Infinite fractions clamp to their respective endpoints.
  /// Curves are flattened first, so the result is made of
  /// straight segments, and a closed subpath that is cut comes back open.
  ///
  /// Lengths are in this path's own coordinate units. A trimmed shape is
  /// measured in cell widths instead, so that a fraction is the same physical
  /// share of the outline; see `Shape.trim(from:to:)`.
  public func trimmedPath(from: Double, to: Double, tolerance: Double = 0.01) -> Path {
    var result = Path()
    let trim = StrokeTrim(from: from, to: to)
    let lower = trim.from
    let upper = trim.to
    guard lower < upper else {
      return result
    }

    let subpaths = flattened(tolerance: tolerance)
    // Fractions need relative lengths, not absolute lengths. Normalize all
    // coordinates by one scale before accumulating so neither squared norms
    // nor the sum of individually representable segments can overflow.
    var magnitude = 0.0
    for points in subpaths {
      guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return result }
      for (a, b) in zip(points, points.dropFirst()) {
        magnitude = max(magnitude, abs(b.x - a.x), abs(b.y - a.y))
      }
    }
    guard magnitude > 0 else { return result }
    if !magnitude.isFinite { magnitude = .greatestFiniteMagnitude }
    // A power-of-two scale changes only the exponent. Arbitrary divisors
    // introduce rounding even for short, exactly representable line lengths.
    let scale = Double(sign: .plus, exponent: magnitude.exponent, significand: 1)
    func delta(_ a: Double, _ b: Double) -> Double {
      let difference = b - a
      return difference.isFinite ? difference / scale : b / scale - a / scale
    }
    func distance(_ a: Point, _ b: Point) -> Double {
      Self.norm(delta(a.x, b.x), delta(a.y, b.y))
    }
    func interpolate(_ a: Point, _ b: Point, _ t: Double) -> Point {
      Point(x: (1 - t) * a.x + t * b.x, y: (1 - t) * a.y + t * b.y)
    }
    var total = 0.0
    for points in subpaths {
      for index in points.indices.dropFirst() {
        total += distance(points[index - 1], points[index])
      }
    }
    guard total > 0 else {
      return result
    }

    let start = lower * total
    let end = upper * total
    var travelled = 0.0
    for points in subpaths {
      var penDown = false
      for index in points.indices.dropFirst() {
        let a = points[index - 1]
        let b = points[index]
        let length = distance(a, b)
        defer { travelled += length }
        guard length > 0, travelled + length > start, travelled < end else {
          continue
        }
        let t0 = max(0, (start - travelled) / length)
        let t1 = min(1, (end - travelled) / length)
        if !penDown {
          result.move(to: interpolate(a, b, t0))
          penDown = true
        }
        result.addLine(to: interpolate(a, b, t1))
      }
    }
    return result
  }

  /// Flattens the path to one polyline per subpath, subdividing curves until
  /// they are within `tolerance` (in this path's own coordinate units) of a
  /// straight segment. Explicitly-closed subpaths repeat their start point as
  /// the final point. Open subpaths do not repeat the start point.
  /// Fill operations close each subpath. Stroke operations keep the authored open or closed state.
  public func flattened(tolerance: Double = 0.1) -> [[Point]] {
    guard hasFiniteCoordinates else { return [] }
    let tol = max(0.000_1, tolerance)
    var subpaths: [[Point]] = []
    var current: [Point] = []
    var subpathStart: Point?
    var pen: Point?

    func ensurePen() -> Point {
      if current.isEmpty {
        current.append(pen ?? .zero)
      }
      return current.last ?? pen ?? Point(x: 0, y: 0)
    }

    for element in elements {
      switch element {
      case .move(let point):
        if current.count > 1 {
          subpaths.append(current)
        }
        current = [point]
        subpathStart = point
        pen = point
      case .line(let point):
        _ = ensurePen()
        current.append(point)
        pen = point
        if subpathStart == nil {
          subpathStart = current.first
        }
      case .quadCurve(let to, let control):
        let from = ensurePen()
        appendQuad(from: from, control: control, to: to, tolerance: tol, into: &current)
        pen = to
        if subpathStart == nil {
          subpathStart = current.first
        }
      case .curve(let to, let control1, let control2):
        let from = ensurePen()
        appendCubic(
          from: from, control1: control1, control2: control2, to: to,
          tolerance: tol, into: &current)
        pen = to
        if subpathStart == nil {
          subpathStart = current.first
        }
      case .close:
        if let subpathStart, current.last != subpathStart {
          current.append(subpathStart)
        }
        if current.count > 1 {
          subpaths.append(current)
        }
        current = []
        pen = subpathStart
      }
    }
    if current.count > 1 {
      subpaths.append(current)
    }
    return subpaths
  }

  public func scaledBy(sx: Double, sy: Double) -> Path {
    Path(
      elements.map { element in
        switch element {
        case .move(let point):
          return .move(to: Point(x: point.x * sx, y: point.y * sy))
        case .line(let point):
          return .line(to: Point(x: point.x * sx, y: point.y * sy))
        case .quadCurve(let to, let control):
          return .quadCurve(
            to: Point(x: to.x * sx, y: to.y * sy),
            control: Point(x: control.x * sx, y: control.y * sy))
        case .curve(let to, let control1, let control2):
          return .curve(
            to: Point(x: to.x * sx, y: to.y * sy),
            control1: Point(x: control1.x * sx, y: control1.y * sy),
            control2: Point(x: control2.x * sx, y: control2.y * sy))
        case .close:
          return .close
        }
      }
    )
  }

  public func translatedBy(dx: Double, dy: Double) -> Path {
    Path(
      elements.map { element in
        switch element {
        case .move(let point):
          return .move(to: Point(x: point.x + dx, y: point.y + dy))
        case .line(let point):
          return .line(to: Point(x: point.x + dx, y: point.y + dy))
        case .quadCurve(let to, let control):
          return .quadCurve(
            to: Point(x: to.x + dx, y: to.y + dy),
            control: Point(x: control.x + dx, y: control.y + dy))
        case .curve(let to, let control1, let control2):
          return .curve(
            to: Point(x: to.x + dx, y: to.y + dy),
            control1: Point(x: control1.x + dx, y: control1.y + dy),
            control2: Point(x: control2.x + dx, y: control2.y + dy))
        case .close:
          return .close
        }
      }
    )
  }

  /// The cubic-Bézier control-point offset that best approximates a quarter
  /// circle (the classic kappa constant).
  private static let kappa = 0.552_284_749_830_793_4

  // Invalid control points cannot define a finite outline. Reject the whole
  // path consistently for rendering, bounds and hit testing, before subdivision.
  package var hasFiniteCoordinates: Bool {
    func finite(_ point: Point) -> Bool { point.x.isFinite && point.y.isFinite }
    return elements.allSatisfy { element in
      switch element {
      case .move(let point), .line(let point): finite(point)
      case .quadCurve(let to, let control): finite(to) && finite(control)
      case .curve(let to, let control1, let control2):
        finite(to) && finite(control1) && finite(control2)
      case .close: true
      }
    }
  }
}

extension Path {
  private struct Segment {
    var start: Point
    var end: Point
  }

  /// The edges of the filled region. A fill closes every subpath, so an open
  /// subpath gets the edge from its last point back to its first.
  private func closedSegments() -> [Segment] {
    var segments: [Segment] = []
    for polyline in flattened() {
      guard let first = polyline.first, let last = polyline.last, polyline.count >= 2 else {
        continue
      }
      for index in 0..<(polyline.count - 1) {
        segments.append(Segment(start: polyline[index], end: polyline[index + 1]))
      }
      if first != last {
        segments.append(Segment(start: last, end: first))
      }
    }
    return segments
  }

  private func appendQuad(
    from p0: Point,
    control p1: Point,
    to p2: Point,
    tolerance: Double,
    into points: inout [Point]
  ) {
    if points.isEmpty {
      points.append(p0)
    }
    subdivideQuad(p0, p1, p2, tolerance: tolerance, depth: 0, into: &points)
  }

  private func subdivideQuad(
    _ p0: Point,
    _ p1: Point,
    _ p2: Point,
    tolerance: Double,
    depth: Int,
    into points: inout [Point]
  ) {
    if depth >= 18 || pointNearSegment(p1, p0, p2, tolerance: tolerance) {
      points.append(p2)
      return
    }
    let p01 = midpoint(p0, p1)
    let p12 = midpoint(p1, p2)
    let p012 = midpoint(p01, p12)
    subdivideQuad(p0, p01, p012, tolerance: tolerance, depth: depth + 1, into: &points)
    subdivideQuad(p012, p12, p2, tolerance: tolerance, depth: depth + 1, into: &points)
  }

  private func appendCubic(
    from p0: Point,
    control1 p1: Point,
    control2 p2: Point,
    to p3: Point,
    tolerance: Double,
    into points: inout [Point]
  ) {
    if points.isEmpty {
      points.append(p0)
    }
    subdivideCubic(p0, p1, p2, p3, tolerance: tolerance, depth: 0, into: &points)
  }

  private func subdivideCubic(
    _ p0: Point,
    _ p1: Point,
    _ p2: Point,
    _ p3: Point,
    tolerance: Double,
    depth: Int,
    into points: inout [Point]
  ) {
    if depth >= 18
      || (pointNearSegment(p1, p0, p3, tolerance: tolerance)
        && pointNearSegment(p2, p0, p3, tolerance: tolerance))
    {
      points.append(p3)
      return
    }
    let p01 = midpoint(p0, p1)
    let p12 = midpoint(p1, p2)
    let p23 = midpoint(p2, p3)
    let p012 = midpoint(p01, p12)
    let p123 = midpoint(p12, p23)
    let p0123 = midpoint(p012, p123)
    subdivideCubic(p0, p01, p012, p0123, tolerance: tolerance, depth: depth + 1, into: &points)
    subdivideCubic(p0123, p123, p23, p3, tolerance: tolerance, depth: depth + 1, into: &points)
  }

  private func midpoint(_ a: Point, _ b: Point) -> Point {
    Point(x: a.x / 2 + b.x / 2, y: a.y / 2 + b.y / 2)
  }

  /// A control hull near the finite endpoint segment bounds the entire
  /// curve's approximation error. Distance to the infinite line would discard
  /// collinear reversals and excursions beyond either endpoint.
  private func pointNearSegment(
    _ point: Point, _ a: Point, _ b: Point, tolerance: Double
  ) -> Bool {
    Self.distance(point, toSegmentFrom: a, to: b) <= tolerance
  }

  private static func norm(_ x: Double, _ y: Double) -> Double {
    guard x.isFinite, y.isFinite else { return .infinity }
    let scale = max(abs(x), abs(y))
    guard scale > 0 else { return 0 }
    guard scale.isFinite else { return .infinity }
    let nx = x / scale
    let ny = y / scale
    return scale * (nx * nx + ny * ny).squareRoot()
  }

  private static func distance(_ point: Point, toSegmentFrom a: Point, to b: Point) -> Double {
    guard [point.x, point.y, a.x, a.y, b.x, b.y].allSatisfy({ $0.isFinite }) else {
      return .infinity
    }
    let dx = b.x - a.x
    let dy = b.y - a.y
    let px = point.x - a.x
    let py = point.y - a.y
    let scale = max(abs(dx), abs(dy), abs(px), abs(py))
    guard scale > 0 else { return 0 }
    if !scale.isFinite {
      // Opposite finite endpoints can have an unrepresentable difference.
      // Divide first in that case; scale the resulting distance back once.
      let divisor = Double(sign: .plus, exponent: 1023, significand: 1)
      func scaled(_ p: Point) -> Point { Point(x: p.x / divisor, y: p.y / divisor) }
      return distance(scaled(point), toSegmentFrom: scaled(a), to: scaled(b)) * divisor
    }
    let x = dx / scale
    let y = dy / scale
    let qx = px / scale
    let qy = py / scale
    let lengthSquared = x * x + y * y
    let fraction = lengthSquared > 0 ? min(max((qx * x + qy * y) / lengthSquared, 0), 1) : 0
    return scale * norm(qx - fraction * x, qy - fraction * y)
  }

  private func pointIsOnSegment(_ point: Point, _ segment: Segment) -> Bool {
    Self.distance(point, toSegmentFrom: segment.start, to: segment.end) <= 0.000_001
  }

  /// Returns +1 if the segment crosses the rightward ray from `point` going
  /// upward, -1 if downward, 0 if it does not cross. The non-zero magnitude
  /// matches the legacy even-odd crossing test exactly, so the default
  /// `.evenOdd` behavior is preserved.
  private func rayCrossingDirection(
    from point: Point,
    segment: Segment
  ) -> Int {
    let y1 = segment.start.y
    let y2 = segment.end.y
    guard (y1 > point.y) != (y2 > point.y) else {
      return 0
    }

    let x1 = segment.start.x
    let x2 = segment.end.x
    let intersectionX = x1 + (point.y - y1) * (x2 - x1) / (y2 - y1)
    guard intersectionX > point.x else {
      return 0
    }
    return y2 > y1 ? 1 : -1
  }
}
