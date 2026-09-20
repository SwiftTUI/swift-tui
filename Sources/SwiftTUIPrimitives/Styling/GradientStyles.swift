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

/// A gradient that sweeps round a center point, by angle.
///
/// Angles follow SwiftUI as measured. An angle of zero points along the
/// trailing `x` axis, at three o'clock, and angles increase clockwise on
/// screen. They are geometric: measured in aspect-corrected cell space, so a
/// quarter turn is a quarter turn on screen whatever the shape's proportions in
/// cells.
///
/// On a stroke this paints a color by where each cell sits round the center,
/// which is how a chasing-light border is built: animate ``startAngle`` and
/// ``endAngle`` together, or use ``init(gradient:center:angle:)`` and animate
/// the angle.
public struct AngularGradient: ShapeStyle, Equatable, Sendable {
  public var gradient: Gradient
  public var center: UnitPoint
  public var startAngle: Angle
  public var endAngle: Angle

  public init(
    gradient: Gradient,
    center: UnitPoint = .center,
    startAngle: Angle,
    endAngle: Angle
  ) {
    self.gradient = gradient
    self.center = center
    self.startAngle = startAngle
    self.endAngle = endAngle
  }

  /// A conic gradient: one full turn, starting at `angle`.
  public init(gradient: Gradient, center: UnitPoint = .center, angle: Angle = .radians(0)) {
    self.init(
      gradient: gradient,
      center: center,
      startAngle: angle,
      endAngle: .radians(angle.radians + 2 * .pi)
    )
  }

  public init(
    colors: [Color],
    center: UnitPoint = .center,
    startAngle: Angle,
    endAngle: Angle
  ) {
    self.init(
      gradient: Gradient(colors: colors), center: center,
      startAngle: startAngle, endAngle: endAngle)
  }

  public init(colors: [Color], center: UnitPoint = .center, angle: Angle = .radians(0)) {
    self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
  }

  public init(
    stops: [Gradient.Stop],
    center: UnitPoint = .center,
    startAngle: Angle,
    endAngle: Angle
  ) {
    self.init(
      gradient: Gradient(stops: stops), center: center,
      startAngle: startAngle, endAngle: endAngle)
  }

  public init(stops: [Gradient.Stop], center: UnitPoint = .center, angle: Angle = .radians(0)) {
    self.init(gradient: Gradient(stops: stops), center: center, angle: angle)
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .angularGradient(self)
  }

  /// The gradient location, from `0` to `1`, at a screen angle in radians.
  ///
  /// The three rules were measured against SwiftUI:
  /// - A span of one turn or more draws its last complete turn, and location is
  ///   still the angle's share of the whole span.
  /// - A span of less than one turn leaves a missing area, which splits at its
  ///   midpoint: the half next to the end angle takes the last color and the
  ///   half next to the start angle takes the first.
  /// - A negative span runs the gradient counter-clockwise.
  package func location(atAngle angle: Double) -> Double {
    let turn = 2 * Double.pi
    let start = startAngle.radians
    let span = endAngle.radians - start
    guard angle.isFinite, span.isFinite, start.isFinite else {
      return 0
    }
    let magnitude = abs(span)
    let direction: Double = span < 0 ? -1 : 1
    func sweep(from origin: Double) -> Double {
      // How far round from `origin` to `angle`, in the gradient's direction.
      let remainder = ((angle - origin) * direction).truncatingRemainder(dividingBy: turn)
      return remainder < 0 ? remainder + turn : remainder
    }
    if magnitude >= turn {
      let lastTurnStart = endAngle.radians - direction * turn
      return min(1, (abs(lastTurnStart - start) + sweep(from: lastTurnStart)) / magnitude)
    }
    let swept = sweep(from: start)
    if magnitude > 0, swept <= magnitude {
      return swept / magnitude
    }
    return swept - magnitude < (turn - magnitude) / 2 ? 1 : 0
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
