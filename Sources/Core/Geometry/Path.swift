/// A minimal continuous path used for pointer hit testing.
public struct Path: Equatable, Sendable {
  public enum Element: Equatable, Sendable {
    case move(to: Point)
    case line(to: Point)
    case close
  }

  public private(set) var elements: [Element]

  public init() {
    elements = []
  }

  public init(_ elements: [Element]) {
    self.elements = elements
  }

  public mutating func move(to point: Point) {
    elements.append(.move(to: point))
  }

  public mutating func addLine(to point: Point) {
    elements.append(.line(to: point))
  }

  public mutating func close() {
    elements.append(.close)
  }

  public func contains(_ point: Point) -> Bool {
    var contains = false
    for segment in closedSegments() {
      if pointIsOnSegment(point, segment) {
        return true
      }
      if rayCrossesSegment(from: point, segment: segment) {
        contains.toggle()
      }
    }
    return contains
  }

  public var boundingRect: Rect? {
    var minX: Double?
    var minY: Double?
    var maxX: Double?
    var maxY: Double?

    for element in elements {
      let point: Point?
      switch element {
      case .move(let value), .line(let value):
        point = value
      case .close:
        point = nil
      }

      guard let point else { continue }
      minX = min(minX ?? point.x, point.x)
      minY = min(minY ?? point.y, point.y)
      maxX = max(maxX ?? point.x, point.x)
      maxY = max(maxY ?? point.y, point.y)
    }

    guard let minX, let minY, let maxX, let maxY else {
      return nil
    }

    return Rect(
      origin: Point(x: minX, y: minY),
      size: Size(width: maxX - minX, height: maxY - minY)
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
        case .close:
          return .close
        }
      }
    )
  }
}

extension Path {
  private struct Segment {
    var start: Point
    var end: Point
  }

  private func closedSegments() -> [Segment] {
    var segments: [Segment] = []
    var subpathStart: Point?
    var current: Point?

    for element in elements {
      switch element {
      case .move(let point):
        subpathStart = point
        current = point
      case .line(let point):
        if let current {
          segments.append(Segment(start: current, end: point))
        }
        current = point
      case .close:
        if let current, let subpathStart, current != subpathStart {
          segments.append(Segment(start: current, end: subpathStart))
        }
        current = subpathStart
      }
    }

    return segments
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

  private func rayCrossesSegment(
    from point: Point,
    segment: Segment
  ) -> Bool {
    let y1 = segment.start.y
    let y2 = segment.end.y
    guard (y1 > point.y) != (y2 > point.y) else {
      return false
    }

    let x1 = segment.start.x
    let x2 = segment.end.x
    let intersectionX = x1 + (point.y - y1) * (x2 - x1) / (y2 - y1)
    return intersectionX > point.x
  }
}
