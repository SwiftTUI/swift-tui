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

/// An RGB color expressed in 8-bit components.
public struct Color: ShapeStyle, Hashable, Sendable {
  public var red: Int
  public var green: Int
  public var blue: Int

  public init(red: Int, green: Int, blue: Int) {
    self.red = Self.clamp(red)
    self.green = Self.clamp(green)
    self.blue = Self.clamp(blue)
  }

  public init(hex: Int) {
    self.init(
      red: (hex >> 16) & 0xFF,
      green: (hex >> 8) & 0xFF,
      blue: hex & 0xFF
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .color(self)
  }

  private static func clamp(_ component: Int) -> Int {
    min(255, max(0, component))
  }
}

extension Color {
  public static let black = Self(hex: 0x000000)
  public static let white = Self(hex: 0xFFFFFF)
  public static let red = Self(hex: 0xE05757)
  public static let green = Self(hex: 0x61C67B)
  public static let yellow = Self(hex: 0xEBB33C)
  public static let blue = Self(hex: 0x5BA3FF)
  public static let magenta = Self(hex: 0xB46EFF)
  public static let cyan = Self(hex: 0x56B6C2)
  public static let gray = Self(hex: 0x8C92AC)
}

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
  public var startPoint: Alignment
  public var endPoint: Alignment

  public init(
    gradient: Gradient,
    startPoint: Alignment,
    endPoint: Alignment
  ) {
    self.gradient = gradient
    self.startPoint = startPoint
    self.endPoint = endPoint
  }

  public init(
    colors: [Color],
    startPoint: Alignment,
    endPoint: Alignment
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

/// Type-erased wrapper for any supported shape style.
public enum AnyShapeStyle: Equatable, Sendable {
  case semantic(SemanticStyleRole)
  case color(Color)
  case linearGradient(LinearGradient)
  case terminalChrome(TerminalChromeStyle)

  public init(_ style: some ShapeStyle) {
    self = style.eraseToAnyShapeStyle()
  }
}

extension AnyShapeStyle: ShapeStyle {
  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    self
  }
}

/// The semantic color theme used to resolve terminal styles.
public struct Theme: Equatable, Sendable {
  public var foreground: AnyShapeStyle
  public var background: AnyShapeStyle
  public var tint: AnyShapeStyle
  public var separator: AnyShapeStyle
  public var selection: AnyShapeStyle
  public var placeholder: AnyShapeStyle
  public var link: AnyShapeStyle
  public var fill: AnyShapeStyle
  public var windowBackground: AnyShapeStyle
  public var success: AnyShapeStyle
  public var warning: AnyShapeStyle
  public var danger: AnyShapeStyle
  public var info: AnyShapeStyle
  public var muted: AnyShapeStyle

  public init(
    foreground: AnyShapeStyle = .color(.init(hex: 0xECEFF4)),
    background: AnyShapeStyle = .color(.init(hex: 0x1E222A)),
    tint: AnyShapeStyle = .color(.cyan),
    separator: AnyShapeStyle = .color(.init(hex: 0x4C566A)),
    selection: AnyShapeStyle = .color(.init(hex: 0x2E3440)),
    placeholder: AnyShapeStyle = .color(.gray),
    link: AnyShapeStyle = .color(.blue),
    fill: AnyShapeStyle = .color(.init(hex: 0x2B303B)),
    windowBackground: AnyShapeStyle = .color(.init(hex: 0x15181E)),
    success: AnyShapeStyle = .color(.green),
    warning: AnyShapeStyle = .color(.yellow),
    danger: AnyShapeStyle = .color(.red),
    info: AnyShapeStyle = .color(.cyan),
    muted: AnyShapeStyle = .color(.gray)
  ) {
    self.foreground = foreground
    self.background = background
    self.tint = tint
    self.separator = separator
    self.selection = selection
    self.placeholder = placeholder
    self.link = link
    self.fill = fill
    self.windowBackground = windowBackground
    self.success = success
    self.warning = warning
    self.danger = danger
    self.info = info
    self.muted = muted
  }

  public static let `default` = Self()

  public func style(for role: SemanticStyleRole) -> AnyShapeStyle {
    switch role {
    case .foreground:
      foreground
    case .background:
      background
    case .tint:
      tint
    case .separator:
      separator
    case .selection:
      selection
    case .placeholder:
      placeholder
    case .link:
      link
    case .fill:
      fill
    case .windowBackground:
      windowBackground
    case .success:
      success
    case .warning:
      warning
    case .danger:
      danger
    case .info:
      info
    case .muted:
      muted
    }
  }
}

/// Styling state captured from the environment during resolve.
public struct StyleEnvironmentSnapshot: Equatable, Sendable {
  public var appearance: TerminalAppearance
  public var theme: Theme
  public var themeOverride: Theme?
  public var foregroundStyle: AnyShapeStyle?
  public var tintStyle: AnyShapeStyle?
  public var preferredColorScheme: ColorScheme?
  public var colorScheme: ColorScheme
  public var colorSchemeContrast: ColorSchemeContrast
  public var isEnabled: Bool

  public init(
    appearance: TerminalAppearance = .fallback,
    theme: Theme? = nil,
    themeOverride: Theme? = nil,
    foregroundStyle: AnyShapeStyle? = nil,
    tintStyle: AnyShapeStyle? = nil,
    preferredColorScheme: ColorScheme? = nil,
    colorScheme: ColorScheme? = nil,
    colorSchemeContrast: ColorSchemeContrast? = nil,
    isEnabled: Bool = true
  ) {
    let effectiveAppearance = appearance.applyingPreferredColorScheme(
      preferredColorScheme
    )
    var effectiveTheme = (themeOverride ?? theme) ?? effectiveAppearance.semanticTheme()
    if let foregroundStyle {
      effectiveTheme.foreground = foregroundStyle
    }
    if let tintStyle {
      effectiveTheme.tint = tintStyle
    }
    self.appearance = effectiveAppearance
    self.themeOverride = themeOverride ?? theme
    self.theme = effectiveTheme
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.preferredColorScheme = preferredColorScheme
    self.colorScheme = colorScheme ?? effectiveAppearance.colorScheme
    self.colorSchemeContrast = colorSchemeContrast ?? effectiveAppearance.colorSchemeContrast
    self.isEnabled = isEnabled
  }
}

/// The border or rule glyph family used when stroking shapes.
public enum LineVariant: String, Equatable, Sendable {
  case automatic
  case ascii
  case single
  case rounded
  case double
  case heavy
  case block
  case outerHalfBlock
  case innerHalfBlock
  case hidden
  case markdown
}

extension LineVariant {
  public static var normal: Self { .single }
  public static var thick: Self { .heavy }
}

/// Stroke settings used when drawing outlines and rules.
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int
  public var lineVariant: LineVariant

  public init(
    lineWidth: Int = 1,
    lineVariant: LineVariant = .automatic
  ) {
    self.lineWidth = max(1, lineWidth)
    self.lineVariant = lineVariant
  }
}

extension StrokeStyle {
  public static var normal: Self { .init(lineVariant: .normal) }
  public static var rounded: Self { .init(lineVariant: .rounded) }
  public static var thick: Self { .init(lineVariant: .thick) }
  public static var double: Self { .init(lineVariant: .double) }
  public static var ascii: Self { .init(lineVariant: .ascii) }
  public static var block: Self { .init(lineVariant: .block) }
  public static var outerHalfBlock: Self { .init(lineVariant: .outerHalfBlock) }
  public static var innerHalfBlock: Self { .init(lineVariant: .innerHalfBlock) }
  public static var hidden: Self { .init(lineVariant: .hidden) }
  public static var markdown: Self { .init(lineVariant: .markdown) }
}

/// Per-edge background styling used behind stroked borders.
public struct BorderBackgroundStyle: Equatable, Sendable {
  public var top: AnyShapeStyle?
  public var right: AnyShapeStyle?
  public var bottom: AnyShapeStyle?
  public var left: AnyShapeStyle?

  public init(
    top: AnyShapeStyle? = nil,
    right: AnyShapeStyle? = nil,
    bottom: AnyShapeStyle? = nil,
    left: AnyShapeStyle? = nil
  ) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }

  public init<S: ShapeStyle>(
    _ style: S
  ) {
    let resolved = AnyShapeStyle(style)
    top = resolved
    right = resolved
    bottom = resolved
    left = resolved
  }

  public init<TB: ShapeStyle, LR: ShapeStyle>(
    topBottom: TB,
    leftRight: LR
  ) {
    top = AnyShapeStyle(topBottom)
    right = AnyShapeStyle(leftRight)
    bottom = AnyShapeStyle(topBottom)
    left = AnyShapeStyle(leftRight)
  }

  public init<T: ShapeStyle, LR: ShapeStyle, B: ShapeStyle>(
    top: T,
    leftRight: LR,
    bottom: B
  ) {
    self.top = AnyShapeStyle(top)
    right = AnyShapeStyle(leftRight)
    self.bottom = AnyShapeStyle(bottom)
    left = AnyShapeStyle(leftRight)
  }

  public init<T: ShapeStyle, R: ShapeStyle, B: ShapeStyle, L: ShapeStyle>(
    top: T,
    right: R,
    bottom: B,
    left: L
  ) {
    self.top = AnyShapeStyle(top)
    self.right = AnyShapeStyle(right)
    self.bottom = AnyShapeStyle(bottom)
    self.left = AnyShapeStyle(left)
  }

  package init(
    all style: AnyShapeStyle?
  ) {
    self.init(
      top: style,
      right: style,
      bottom: style,
      left: style
    )
  }
}

package enum BorderSide: Sendable {
  case top
  case right
  case bottom
  case left
}

extension BorderBackgroundStyle {
  package func backgroundStyle(
    for side: BorderSide
  ) -> AnyShapeStyle? {
    switch side {
    case .top:
      return top
    case .right:
      return right
    case .bottom:
      return bottom
    case .left:
      return left
    }
  }
}

/// Fill mode used when rendering shapes.
public enum ShapeFillMode: Equatable, Sendable {
  case full
  case interior(strokeWidth: Int)
}

/// Supported low-level shape geometries.
public enum ShapeGeometry: Equatable, Sendable {
  case rectangle
  case roundedRectangle(cornerRadius: Int)
}

/// The draw operation applied to a shape geometry.
public enum ShapeOperation: Equatable, Sendable {
  case fill(
    style: AnyShapeStyle?,
    mode: ShapeFillMode = .full
  )
  case stroke(
    style: AnyShapeStyle?,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle? = nil
  )
}

/// Low-level draw payload for a shape node.
public struct ShapePayload: Equatable, Sendable {
  public var geometry: ShapeGeometry
  public var operation: ShapeOperation

  public init(
    geometry: ShapeGeometry,
    operation: ShapeOperation
  ) {
    self.geometry = geometry
    self.operation = operation
  }
}

/// Underline or strikethrough styling for text.
public struct TextLineStyle: Equatable, Sendable {
  /// The pattern used when drawing a text line decoration.
  public enum Pattern: String, Equatable, Sendable {
    case solid
    case dot
    case dash
    case dashDot
    case dashDotDot
    case double
    case curly

    public static var single: Self { .solid }
    public static var dotted: Self { .dot }
    public static var dashed: Self { .dash }
  }

  public var pattern: Pattern
  public var color: Color?

  public init(
    pattern: Pattern = .solid,
    color: Color? = nil
  ) {
    self.pattern = pattern
    self.color = color
  }
}

/// A fully resolved text style with concrete colors.
public struct ResolvedTextStyle: Equatable, Sendable {
  public var foregroundColor: Color?
  public var backgroundColor: Color?
  public var emphasis: TextStyle.TextEmphasis
  public var underlineStyle: TextLineStyle?
  public var strikethroughStyle: TextLineStyle?
  public var opacity: Double

  public init(
    foregroundColor: Color? = nil,
    backgroundColor: Color? = nil,
    emphasis: TextStyle.TextEmphasis = [],
    underlineStyle: TextLineStyle? = nil,
    strikethroughStyle: TextLineStyle? = nil,
    opacity: Double = 1
  ) {
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.emphasis = emphasis
    self.underlineStyle = underlineStyle
    self.strikethroughStyle = strikethroughStyle
    self.opacity = opacity
  }

  public var isDefault: Bool {
    foregroundColor == nil
      && backgroundColor == nil
      && emphasis.isEmpty
      && underlineStyle == nil
      && strikethroughStyle == nil
      && opacity == 1
  }
}

extension ResolvedTextStyle {
  public func composited(
    over underlay: ResolvedTextStyle?
  ) -> ResolvedTextStyle {
    guard let underlay else {
      return self
    }

    return .init(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor ?? underlay.backgroundColor,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  public init(
    _ style: TextStyle,
    theme: Theme = .default
  ) {
    self.init(
      foregroundColor: style.foregroundStyle.flatMap {
        resolveStyleColor(style: $0, theme: theme)
      },
      backgroundColor: style.backgroundStyle.flatMap {
        resolveStyleColor(style: $0, theme: theme)
      },
      emphasis: style.emphasis,
      underlineStyle: style.underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      opacity: style.opacity
    )
  }
}

/// Errors thrown while resolving semantic or gradient-based colors.
public enum ColorResolutionError: Equatable, Error, Sendable {
  case recursionLimitExceeded(limit: Int, style: AnyShapeStyle)
  case emptyGradient
}

public func resolveStyleColorResult(
  style: AnyShapeStyle,
  theme: Theme,
  depthLimit: Int = 8
) -> Result<Color, ColorResolutionError> {
  resolveStyleColorResult(
    style: style,
    theme: theme,
    depth: 0,
    depthLimit: depthLimit
  )
}

func resolveStyleColor(
  style: AnyShapeStyle,
  theme: Theme,
  depth: Int = 0
) -> Color? {
  switch resolveStyleColorResult(
    style: style,
    theme: theme,
    depth: depth,
    depthLimit: 8
  ) {
  case .success(let color):
    return color
  case .failure(let error):
    assertionFailure("resolveStyleColor failed: \(error)")
    return nil
  }
}

private func resolveStyleColorResult(
  style: AnyShapeStyle,
  theme: Theme,
  depth: Int,
  depthLimit: Int
) -> Result<Color, ColorResolutionError> {
  guard depth < depthLimit else {
    return .failure(.recursionLimitExceeded(limit: depthLimit, style: style))
  }

  switch style {
  case .color(let color):
    return .success(color)
  case .linearGradient(let gradient):
    guard let firstColor = gradient.gradient.stops.first?.color else {
      return .failure(.emptyGradient)
    }
    return .success(firstColor)
  case .terminalChrome(let chromeStyle):
    let appearance = synthesizedAppearance(for: theme)
    return resolveStyleColorResult(
      style: appearance.resolvedStyle(for: chromeStyle),
      theme: theme,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  case .semantic(let role):
    return resolveStyleColorResult(
      style: theme.style(for: role),
      theme: theme,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  }
}
