/// A gradient defined by color stops.
public struct Gradient: Equatable, Sendable {
  /// A single stop in a gradient.
  public struct Stop: Equatable, Sendable {
    public var color: Color
    public var location: Double

    public init(color: Color, location: Double) {
      self.color = color
      self.location = min(1, max(0, location))
    }
  }

  public var stops: [Stop]

  public init(stops: [Stop]) {
    self.stops = stops.sorted { $0.location < $1.location }
  }

  public init(colors: [Color]) {
    guard !colors.isEmpty else {
      self.stops = []
      return
    }

    if colors.count == 1 {
      self.stops = [.init(color: colors[0], location: 0)]
      return
    }

    let denominator = Double(colors.count - 1)
    self.stops = colors.enumerated().map { index, color in
      .init(color: color, location: Double(index) / denominator)
    }
  }
}

/// A linear gradient between two unit points.
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
  public var gradient: Gradient
  public var startPoint: UnitPoint
  public var endPoint: UnitPoint

  public init(
    gradient: Gradient,
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) {
    self.gradient = gradient
    self.startPoint = startPoint
    self.endPoint = endPoint
  }

  public init(
    colors: [Color],
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) {
    self.init(
      gradient: Gradient(colors: colors),
      startPoint: startPoint,
      endPoint: endPoint
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .linearGradient(self)
  }
}

/// A radial gradient between a start and end radius, centered at a unit
/// point in the shape's bounds.
public struct RadialGradient: ShapeStyle, Equatable, Sendable {
  public var gradient: Gradient
  public var center: UnitPoint
  public var startRadius: Double
  public var endRadius: Double

  public init(
    gradient: Gradient,
    center: UnitPoint,
    startRadius: Double,
    endRadius: Double
  ) {
    self.gradient = gradient
    self.center = center
    self.startRadius = startRadius
    self.endRadius = endRadius
  }

  public init(
    colors: [Color],
    center: UnitPoint = .center,
    startRadius: Double = 0,
    endRadius: Double
  ) {
    self.init(
      gradient: Gradient(colors: colors),
      center: center,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .radialGradient(self)
  }
}
