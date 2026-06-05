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
/// are flattened to polylines on demand via ``flattened(tolerance:)``; there is
/// exactly one `Path` type so hit testing and rendering never diverge.
public struct Path: Equatable, Sendable {
  public enum Element: Equatable, Sendable {
    case move(to: Point)
    case line(to: Point)
    case quadCurve(to: Point, control: Point)
    case curve(to: Point, control1: Point, control2: Point)
    case close
  }

  public private(set) var elements: [Element]

  public init() {
    elements = []
  }

  public init(_ elements: [Element]) {
    self.elements = elements
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
    elements.append(.line(to: point))
  }

  public mutating func addQuadCurve(to point: Point, control: Point) {
    elements.append(.quadCurve(to: point, control: control))
  }

  public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
    elements.append(.curve(to: point, control1: control1, control2: control2))
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
    move(to: Point(x: minX + r, y: minY))
    addLine(to: Point(x: maxX - r, y: minY))
    addCurve(
      to: Point(x: maxX, y: minY + r),
      control1: Point(x: maxX - r + o, y: minY),
      control2: Point(x: maxX, y: minY + r - o))
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
    close()
  }

  public mutating func addEllipse(in rect: Rect) {
    let cx = rect.origin.x + rect.size.width / 2
    let cy = rect.origin.y + rect.size.height / 2
    let rx = rect.size.width / 2
    let ry = rect.size.height / 2
    let ox = rx * Self.kappa
    let oy = ry * Self.kappa
    move(to: Point(x: cx - rx, y: cy))
    addCurve(
      to: Point(x: cx, y: cy - ry),
      control1: Point(x: cx - rx, y: cy - oy),
      control2: Point(x: cx - ox, y: cy - ry))
    addCurve(
      to: Point(x: cx + rx, y: cy),
      control1: Point(x: cx + ox, y: cy - ry),
      control2: Point(x: cx + rx, y: cy - oy))
    addCurve(
      to: Point(x: cx, y: cy + ry),
      control1: Point(x: cx + rx, y: cy + oy),
      control2: Point(x: cx + ox, y: cy + ry))
    addCurve(
      to: Point(x: cx - rx, y: cy),
      control1: Point(x: cx - ox, y: cy + ry),
      control2: Point(x: cx - rx, y: cy + oy))
    close()
  }

  // MARK: - Queries

  /// Whether `point` lies inside (or on the boundary of) the filled path
  /// under the given `fillRule`. Defaults to `.evenOdd` to preserve the
  /// established pointer hit-test behavior.
  public func contains(_ point: Point, fillRule: FillRule = .evenOdd) -> Bool {
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

    for element in elements {
      switch element {
      case .move(let value), .line(let value):
        extend(value)
      case .quadCurve(let to, let control):
        extend(to)
        extend(control)
      case .curve(let to, let control1, let control2):
        extend(to)
        extend(control1)
        extend(control2)
      case .close:
        break
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

  /// Flattens the path to one polyline per subpath, subdividing curves until
  /// they are within `tolerance` (in this path's own coordinate units) of a
  /// straight segment. Explicitly-closed subpaths repeat their start point as
  /// the final point; open subpaths do not. Callers that fill close each
  /// subpath; callers that stroke honor open vs closed.
  public func flattened(tolerance: Double = 0.1) -> [[Point]] {
    let tol = max(0.000_1, tolerance)
    var subpaths: [[Point]] = []
    var current: [Point] = []
    var subpathStart: Point?
    var pen: Point?

    func ensurePen() -> Point {
      if current.isEmpty, let pen {
        current.append(pen)
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
}

extension Path {
  private struct Segment {
    var start: Point
    var end: Point
  }

  private func closedSegments() -> [Segment] {
    var segments: [Segment] = []
    for polyline in flattened() {
      guard polyline.count >= 2 else { continue }
      for index in 0..<(polyline.count - 1) {
        segments.append(Segment(start: polyline[index], end: polyline[index + 1]))
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
    if depth >= 18 || pointNearLine(p1, p0, p2, tolerance: tolerance) {
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
      || (pointNearLine(p1, p0, p3, tolerance: tolerance)
        && pointNearLine(p2, p0, p3, tolerance: tolerance))
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
    Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
  }

  /// Whether `point`'s perpendicular distance from the line through `a`–`b`
  /// is within `tolerance`. Uses squared distance to avoid `sqrt` (and any
  /// Foundation dependency).
  private func pointNearLine(
    _ point: Point,
    _ a: Point,
    _ b: Point,
    tolerance: Double
  ) -> Bool {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    let cross = (point.x - a.x) * dy - (point.y - a.y) * dx
    let tolSquared = tolerance * tolerance
    if lengthSquared <= 0.000_000_1 {
      let ddx = point.x - a.x
      let ddy = point.y - a.y
      return ddx * ddx + ddy * ddy <= tolSquared
    }
    return cross * cross <= tolSquared * lengthSquared
  }

  private func pointIsOnSegment(
    _ point: Point,
    _ segment: Segment
  ) -> Bool {
    let epsilon = 0.000_001
    let cross =
      (point.y - segment.start.y) * (segment.end.x - segment.start.x)
      - (point.x - segment.start.x) * (segment.end.y - segment.start.y)
    guard abs(cross) <= epsilon else {
      return false
    }

    let minX = min(segment.start.x, segment.end.x) - epsilon
    let maxX = max(segment.start.x, segment.end.x) + epsilon
    let minY = min(segment.start.y, segment.end.y) - epsilon
    let maxY = max(segment.start.y, segment.end.y) + epsilon
    return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
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
