/// Semantic color roles used by themes and environment styling.
public enum SemanticStyleRole: String, CaseIterable, Equatable, Sendable {
  case foreground
  case background
  case tint
  case separator
  case selection
  case placeholder
  case link
  case fill
  case windowBackground
  case success
  case warning
  case danger
  case info
  case muted
}

/// Protocol for values that can resolve into a drawable terminal style.
public protocol ShapeStyle: Sendable {
  func eraseToAnyShapeStyle() -> AnyShapeStyle
}

/// A shape style that resolves through the active semantic theme.
public struct SemanticShapeStyle: ShapeStyle, Equatable, Sendable {
  public var role: SemanticStyleRole

  public init(_ role: SemanticStyleRole) {
    self.role = role
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .semantic(role)
  }
}

extension ShapeStyle where Self == SemanticShapeStyle {
  public static var foreground: Self { .init(.foreground) }
  public static var background: Self { .init(.background) }
  public static var tint: Self { .init(.tint) }
  public static var separator: Self { .init(.separator) }
  public static var selection: Self { .init(.selection) }
  public static var placeholder: Self { .init(.placeholder) }
  public static var link: Self { .init(.link) }
  public static var fill: Self { .init(.fill) }
  public static var windowBackground: Self { .init(.windowBackground) }
  public static var success: Self { .init(.success) }
  public static var warning: Self { .init(.warning) }
  public static var danger: Self { .init(.danger) }
  public static var info: Self { .init(.info) }
  public static var muted: Self { .init(.muted) }
}

extension ShapeStyle where Self == Color {
  public static var clear: Color { Color(red: 0, green: 0, blue: 0, alpha: 0, profile: .sRGB) }
  public static var black: Color { Color(red: 0, green: 0, blue: 0, alpha: 1, profile: .sRGB) }
  public static var white: Color { Color(red: 1, green: 1, blue: 1, alpha: 1, profile: .sRGB) }
  public static var red: Color { try! Self(hex: "#E05757FF") }
  public static var green: Color { try! Self(hex: "#61C67BFF") }
  public static var blue: Color { try! Self(hex: "#5BA3FFFF") }
  public static var yellow: Color { try! Self(hex: "#EBB33CFF") }
  public static var magenta: Color { try! Self(hex: "#B46EFFFF") }
  public static var cyan: Color { try! Self(hex: "#56B6C2FF") }
  public static var gray: Color { try! Self(hex: "#8C92ACFF") }
}

extension Color: ShapeStyle {
  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .color(self)
  }

  public static func hex(
    _ hex: String,
    profile: RGBColorProfile = .sRGB
  ) throws -> Self {
    try .init(hex: hex, profile: profile)
  }

  public func opacity(_ opacity: Double) -> Color {
    var copy = self
    copy.alpha = self.alpha * min(1, max(0, opacity))
    return copy
  }
}

/// Type-erased wrapper for any supported shape style.
public enum AnyShapeStyle: Equatable, Sendable {
  case semantic(SemanticStyleRole)
  case color(Color)
  case linearGradient(LinearGradient)
  case radialGradient(RadialGradient)
  case meshGradient(MeshGradient)
  indirect case tileStyle(TileStyle)
  case terminalChrome(TerminalChromeStyle)
  indirect case opacity(AnyShapeStyle, Double)

  public init(_ style: some ShapeStyle) {
    self = style.eraseToAnyShapeStyle()
  }
}

extension AnyShapeStyle: ShapeStyle {
  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    self
  }
}

extension ShapeStyle {
  public func opacity(_ opacity: Double) -> AnyShapeStyle {
    let clamped = min(1, max(0, opacity))
    switch eraseToAnyShapeStyle() {
    case .color(let color):
      return .color(color.opacity(clamped))
    case .linearGradient(let gradient):
      let fadedStops = gradient.gradient.stops.map {
        Gradient.Stop(color: $0.color.opacity(clamped), location: $0.location)
      }
      return .linearGradient(
        .init(
          gradient: .init(stops: fadedStops),
          startPoint: gradient.startPoint,
          endPoint: gradient.endPoint
        ))
    case .radialGradient(let gradient):
      let fadedStops = gradient.gradient.stops.map {
        Gradient.Stop(color: $0.color.opacity(clamped), location: $0.location)
      }
      return .radialGradient(
        .init(
          gradient: .init(stops: fadedStops),
          center: gradient.center,
          startRadius: gradient.startRadius,
          endRadius: gradient.endRadius
        ))
    case .meshGradient(let gradient):
      return .meshGradient(
        .init(
          width: gradient.width,
          height: gradient.height,
          points: gradient.points,
          colors: gradient.colors.map { $0.opacity(clamped) },
          background: gradient.background.opacity(clamped),
          smoothsColors: gradient.smoothsColors,
          colorSpace: gradient.colorSpace
        ))
    case .tileStyle(let tile):
      return .tileStyle(tile.applyingOpacity(clamped))
    case let style:
      // Semantic/chrome styles can't carry alpha until resolved -
      // wrap for deferred resolution in the rasterizer.
      return .opacity(style, clamped)
    }
  }
}
