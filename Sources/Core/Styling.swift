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

extension Color: ShapeStyle {
  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .color(self)
  }

  public static func hex(
    _ hex: String,
    profile: RGBColorProfile = .sRGB
  ) -> Self {
    try! .init(hex: hex, profile: profile)
  }

  public func opacity(_ opacity: Double) -> Color {
    var copy = self
    copy.alpha = self.alpha * min(1, max(0, opacity))
    return copy
  }
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
      return .linearGradient(.init(
        gradient: .init(stops: fadedStops),
        startPoint: gradient.startPoint,
        endPoint: gradient.endPoint
      ))
    case let style:
      // Semantic/chrome styles can't carry alpha until resolved —
      // wrap for deferred resolution in the rasterizer.
      return .opacity(style, clamped)
    }
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
    foreground: AnyShapeStyle = .color(.hex("#ECEFF4")),
    background: AnyShapeStyle = .color(try! .init(hex: "#1E222A")),
    tint: AnyShapeStyle = .color(.cyan),
    separator: AnyShapeStyle = .color(.hex("#4C566A")),
    selection: AnyShapeStyle = .color(.hex("#2E3440")),
    placeholder: AnyShapeStyle = .color(.gray),
    link: AnyShapeStyle = .color(.blue),
    fill: AnyShapeStyle = .color(.hex("#2B303B")),
    windowBackground: AnyShapeStyle = .color(.hex("#15181E")),
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

  public init(
    colors: ThemeColors
  ) {
    self.init(
      foreground: .color(colors.foreground),
      background: .color(colors.background),
      tint: .color(colors.tint),
      separator: .color(colors.separator),
      selection: .color(colors.selection),
      placeholder: .color(colors.placeholder),
      link: .color(colors.link),
      fill: .color(colors.fill),
      windowBackground: .color(colors.windowBackground),
      success: .color(colors.success),
      warning: .color(colors.warning),
      danger: .color(colors.danger),
      info: .color(colors.info),
      muted: .color(colors.muted)
    )
  }

  public static let `default` = Self(colors: .default)

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

/// Concrete semantic token colors suitable for host-supplied themes and wrapper
/// transport.
public struct ThemeColors: Equatable, Sendable, Codable {
  public var foreground: Color
  public var background: Color
  public var tint: Color
  public var separator: Color
  public var selection: Color
  public var placeholder: Color
  public var link: Color
  public var fill: Color
  public var windowBackground: Color
  public var success: Color
  public var warning: Color
  public var danger: Color
  public var info: Color
  public var muted: Color

  public init(
    foreground: Color = .hex("#ECEFF4"),
    background: Color = .hex("#1E222A"),
    tint: Color = .cyan,
    separator: Color = .hex("#4C566A"),
    selection: Color = .hex("#2E3440"),
    placeholder: Color = .gray,
    link: Color = .blue,
    fill: Color = .hex("#2B303B"),
    windowBackground: Color = .hex("#15181E"),
    success: Color = .green,
    warning: Color = .yellow,
    danger: Color = .red,
    info: Color = .cyan,
    muted: Color = .gray
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

  public var theme: Theme {
    Theme(colors: self)
  }

  private enum CodingKeys: String, CodingKey {
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

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    foreground = try Self.decodeColor(for: .foreground, from: container)
    background = try Self.decodeColor(for: .background, from: container)
    tint = try Self.decodeColor(for: .tint, from: container)
    separator = try Self.decodeColor(for: .separator, from: container)
    selection = try Self.decodeColor(for: .selection, from: container)
    placeholder = try Self.decodeColor(for: .placeholder, from: container)
    link = try Self.decodeColor(for: .link, from: container)
    fill = try Self.decodeColor(for: .fill, from: container)
    windowBackground = try Self.decodeColor(for: .windowBackground, from: container)
    success = try Self.decodeColor(for: .success, from: container)
    warning = try Self.decodeColor(for: .warning, from: container)
    danger = try Self.decodeColor(for: .danger, from: container)
    info = try Self.decodeColor(for: .info, from: container)
    muted = try Self.decodeColor(for: .muted, from: container)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try Self.encodeColor(foreground, for: .foreground, into: &container)
    try Self.encodeColor(background, for: .background, into: &container)
    try Self.encodeColor(tint, for: .tint, into: &container)
    try Self.encodeColor(separator, for: .separator, into: &container)
    try Self.encodeColor(selection, for: .selection, into: &container)
    try Self.encodeColor(placeholder, for: .placeholder, into: &container)
    try Self.encodeColor(link, for: .link, into: &container)
    try Self.encodeColor(fill, for: .fill, into: &container)
    try Self.encodeColor(windowBackground, for: .windowBackground, into: &container)
    try Self.encodeColor(success, for: .success, into: &container)
    try Self.encodeColor(warning, for: .warning, into: &container)
    try Self.encodeColor(danger, for: .danger, into: &container)
    try Self.encodeColor(info, for: .info, into: &container)
    try Self.encodeColor(muted, for: .muted, into: &container)
  }

  private static func decodeColor(
    for key: CodingKeys,
    from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Color {
    let value = try container.decode(String.self, forKey: key)
    return try Color(hex: value)
  }

  private static func encodeColor(
    _ color: Color,
    for key: CodingKeys,
    into container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    try container.encode(color.hexString(), forKey: key)
  }
}

/// The host-owned styling payload that pairs terminal appearance metadata with
/// an optional semantic theme override.
public struct TerminalRenderStyle: Equatable, Sendable, Codable {
  public var appearance: TerminalAppearance
  public var theme: ThemeColors?

  public init(
    appearance: TerminalAppearance,
    theme: ThemeColors? = nil
  ) {
    self.appearance = appearance
    self.theme = theme
  }

  public var resolvedTheme: Theme {
    theme?.theme ?? appearance.semanticTheme()
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
    let explicitTheme = themeOverride ?? theme
    var effectiveTheme = explicitTheme ?? appearance.semanticTheme()
    if let foregroundStyle,
      foregroundStyle != .semantic(.foreground)
    {
      effectiveTheme.foreground = foregroundStyle
    }
    if let tintStyle,
      tintStyle != .semantic(.tint)
    {
      effectiveTheme.tint = tintStyle
    }
    self.appearance = appearance
    self.themeOverride = explicitTheme
    self.theme = effectiveTheme
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.preferredColorScheme = preferredColorScheme
    self.colorScheme = colorScheme ?? preferredColorScheme ?? appearance.colorScheme
    self.colorSchemeContrast = colorSchemeContrast ?? appearance.colorSchemeContrast
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

    let blendedBackground: Color? =
      switch (backgroundColor, underlay.backgroundColor) {
      case (let overlay?, let under?) where overlay.alpha < 1:
          under.mixed(with: Color(red: overlay.red, green: overlay.green, blue: overlay.blue), amount: overlay.alpha)
      case (let overlay?, _):
        overlay
      case (nil, let under?):
        under
      case (nil, nil):
        Color?.none
      }

    return .init(
      foregroundColor: foregroundColor ?? underlay.foregroundColor,
      backgroundColor: blendedBackground,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  public func tinted(with overlay: Color) -> ResolvedTextStyle {
    let amount = overlay.alpha
    let opaque = Color(red: overlay.red, green: overlay.green, blue: overlay.blue)
    return .init(
      foregroundColor: foregroundColor.map { $0.mixed(with: opaque, amount: amount) },
      backgroundColor: 
        (backgroundColor ?? Color.black).mixed(with: opaque, amount: amount),
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
    return resolveStyleColorResult(
      style: theme.resolvedStyle(for: chromeStyle),
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
  case .opacity(let inner, _):
    return resolveStyleColorResult(
      style: inner,
      theme: theme,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  }
}
