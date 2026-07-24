/// A gradient defined by color stops.
public struct Gradient: Equatable, Sendable {
  /// The working space used while interpolating gradient colors.
  public enum ColorSpace: Equatable, Sendable {
    /// Interpolates encoded components in the first control color's profile.
    case device
    /// Interpolates perceptually in Oklab, then maps back to the first profile.
    case perceptual
  }

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

/// A two-dimensional grid of colors whose control points can deform the
/// resulting surface.
///
/// Points use normalized coordinates in the painted shape's bounds and are
/// stored in row-major order. The number of points and colors must equal
/// `width * height`.
public struct MeshGradient: ShapeStyle, Equatable, Sendable {
  private struct Storage: Equatable, Sendable {
    var width: Int
    var height: Int
    var points: [SIMD2<Float>]
    var colors: [Color]
    var background: Color
    var smoothsColors: Bool
    var colorSpace: Gradient.ColorSpace
  }

  private var storage: Boxed<Storage>

  public var width: Int { storage.value.width }
  public var height: Int { storage.value.height }
  public var points: [SIMD2<Float>] { storage.value.points }
  public var colors: [Color] { storage.value.colors }
  public var background: Color { storage.value.background }
  public var smoothsColors: Bool { storage.value.smoothsColors }
  public var colorSpace: Gradient.ColorSpace { storage.value.colorSpace }

  public init(
    width: Int,
    height: Int,
    points: [SIMD2<Float>],
    colors: [Color],
    background: Color = .clear,
    smoothsColors: Bool = true,
    colorSpace: Gradient.ColorSpace = .device
  ) {
    precondition(width >= 2, "MeshGradient width must be at least 2")
    precondition(height >= 2, "MeshGradient height must be at least 2")
    let (controlCount, overflow) = width.multipliedReportingOverflow(by: height)
    precondition(!overflow, "MeshGradient dimensions overflow Int")
    precondition(
      points.count == controlCount && colors.count == controlCount,
      "MeshGradient requires width * height points and colors"
    )
    precondition(
      points.allSatisfy { $0.x.isFinite && $0.y.isFinite },
      "MeshGradient points must be finite"
    )
    self.storage = Boxed(
      Storage(
        width: width,
        height: height,
        points: points,
        colors: colors,
        background: background,
        smoothsColors: smoothsColors,
        colorSpace: colorSpace
      )
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .meshGradient(self)
  }

  package mutating func replaceAnimatedValues(
    points: [SIMD2<Float>],
    colors: [Color],
    background: Color
  ) {
    var value = storage.value
    value.points = points
    value.colors = colors
    value.background = background
    storage.value = value
  }
}
