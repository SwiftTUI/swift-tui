extension Path: Animatable {
  /// Anchor and control points in element order. Assignment preserves this
  /// path's element topology; a mismatched point count leaves it unchanged.
  public var animatableData: AnimatableArray<AnimatablePair<Double, Double>> {
    get {
      var points: [AnimatablePair<Double, Double>] = []
      func append(_ point: Point) { points.append(.init(point.x, point.y)) }
      for element in elements {
        switch element {
        case .move(let point), .line(let point): append(point)
        case .quadCurve(let point, let control):
          append(point)
          append(control)
        case .curve(let point, let a, let b):
          append(point)
          append(a)
          append(b)
        case .close: break
        }
      }
      return .init(points)
    }
    set {
      guard newValue.elements.count == animatableData.elements.count else { return }
      var index = 0
      self = mappingPoints { _ in
        defer { index += 1 }
        let point = newValue.elements[index]
        return Point(x: point.first, y: point.second)
      }
    }
  }

  /// Paths interpolate when their ordered element kinds match and all anchor
  /// and control coordinates are finite. Empty paths are compatible with each
  /// other; collapsed segments retain their authored topology.
  public func isInterpolable(to other: Path) -> Bool {
    guard elements.count == other.elements.count else { return false }
    for (lhs, rhs) in zip(elements, other.elements) {
      switch (lhs, rhs) {
      case (.move, .move), (.line, .line), (.quadCurve, .quadCurve), (.curve, .curve),
        (.close, .close):
        break
      default: return false
      }
    }
    return (animatableData.elements + other.animatableData.elements).allSatisfy {
      $0.first.isFinite && $0.second.isFinite
    }
  }

  /// Linearly interpolates every anchor/control point with progress clamped
  /// to 0...1. Compatible endpoints are returned exactly. Incompatible
  /// topology or nonfinite progress snaps immediately to `other`.
  public func interpolated(to other: Path, progress: Double) -> Path {
    guard isInterpolable(to: other), progress.isFinite else { return other }
    guard progress > 0 else { return self }
    guard progress < 1 else { return other }
    let target = other.animatableData.elements
    var index = 0
    return mappingPoints { point in
      defer { index += 1 }
      return Point(
        x: point.x * (1 - progress) + target[index].first * progress,
        y: point.y * (1 - progress) + target[index].second * progress)
    }
  }

  private func mappingPoints(_ transform: (Point) -> Point) -> Path {
    Path(
      elements.map { element in
        switch element {
        case .move(let point): return .move(to: transform(point))
        case .line(let point): return .line(to: transform(point))
        case .quadCurve(let point, let control):
          return .quadCurve(to: transform(point), control: transform(control))
        case .curve(let point, let a, let b):
          return .curve(to: transform(point), control1: transform(a), control2: transform(b))
        case .close: return .close
        }
      })
  }
}
