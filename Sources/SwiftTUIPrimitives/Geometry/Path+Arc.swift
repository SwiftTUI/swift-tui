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

extension Path {
  /// Adds a circular arc, approximated by cubic segments of at most 90°.
  ///
  /// Zero points along positive x. Positive angles point toward positive y.
  /// `clockwise` decreases the angle; in a terminal's downward-y coordinates
  /// this appears counterclockwise. Otherwise the angle increases. The sweep
  /// wraps in that direction to the endpoint, with at most one complete turn.
  /// Equal angles add nothing; an authored difference of at least one turn
  /// adds a complete circle in the requested direction without closing it.
  ///
  /// An empty path moves to the arc's start. An existing subpath connects to
  /// it with a line when needed. Nonpositive radii, nonfinite inputs and
  /// unrepresentable generated points leave the path unchanged.
  public mutating func addArc(
    center: Point, radius: Double, startAngle: Angle, endAngle: Angle, clockwise: Bool
  ) {
    let start = startAngle.radians
    let end = endAngle.radians
    guard center.x.isFinite, center.y.isFinite, radius.isFinite, radius > 0,
      start.isFinite, end.isFinite, start != end
    else { return }
    let turn = 2 * Double.pi
    let difference = end - start
    var sweep: Double
    if !difference.isFinite || abs(difference) >= turn {
      sweep = clockwise ? -turn : turn
    } else {
      sweep = difference.truncatingRemainder(dividingBy: turn)
      if clockwise && sweep > 0 { sweep -= turn }
      if !clockwise && sweep < 0 { sweep += turn }
    }
    let count = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
    let step = sweep / Double(count)
    let angle = start.truncatingRemainder(dividingBy: turn)
    func point(_ angle: Double) -> Point {
      Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    let first = point(angle)
    var additions: [Element] = []
    if let pen = constructionPoint {
      if pen != first { additions.append(.line(to: first)) }
    } else {
      additions.append(.move(to: first))
    }
    for index in 0..<count {
      let a = angle + Double(index) * step
      let b = a + step
      let p0 = point(a)
      let p3 = index == count - 1 && abs(sweep) == turn ? first : point(b)
      let factor = radius * (4 / 3.0) * tan(step / 4)
      let p1 = Point(x: p0.x - factor * sin(a), y: p0.y + factor * cos(a))
      let p2 = Point(x: p3.x + factor * sin(b), y: p3.y - factor * cos(b))
      guard [p0, p1, p2, p3].allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
      additions.append(.curve(to: p3, control1: p1, control2: p2))
    }
    self = Path(elements + additions)
  }

  private var constructionPoint: Point? {
    var pen: Point?
    var start: Point?
    for element in elements {
      switch element {
      case .move(let point):
        pen = point
        start = point
      case .line(let point), .quadCurve(let point, _), .curve(let point, _, _): pen = point
      case .close: pen = start
      }
    }
    return pen
  }
}
