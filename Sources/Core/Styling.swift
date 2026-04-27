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

/// Type-erased wrapper for any supported shape style.
public enum AnyShapeStyle: Equatable, Sendable {
  case semantic(SemanticStyleRole)
  case color(Color)
  case linearGradient(LinearGradient)
  case radialGradient(RadialGradient)
  case patternFill(PatternFill)
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
    case .patternFill(let pattern):
      return .patternFill(
        PatternFill(
          glyph: pattern.glyph,
          foreground: pattern.foreground.opacity(clamped),
          background: pattern.background?.opacity(clamped)
        ))
    case let style:
      // Semantic/chrome styles can't carry alpha until resolved —
      // wrap for deferred resolution in the rasterizer.
      return .opacity(style, clamped)
    }
  }
}

/// Concrete semantic token colors suitable for host-supplied themes, wrapper
/// transport, and local semantic style resolution.
public struct Theme: Equatable, Sendable, Codable {
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

  public func color(for role: SemanticStyleRole) -> Color {
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

  public func style(for role: SemanticStyleRole) -> AnyShapeStyle {
    .color(color(for: role))
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
  public var theme: Theme?

  public init(
    appearance: TerminalAppearance,
    theme: Theme? = nil
  ) {
    self.appearance = appearance
    self.theme = theme
  }

  public var resolvedTheme: Theme {
    theme ?? appearance.synthesizedTheme()
  }
}

/// Heap-allocated storage for the large ``TerminalAppearance`` and ``Theme``
/// value types.  Keeping them behind a reference avoids ~5 KB of stack copies
/// at every level of view-tree resolution.
package final class StyleHeavyFieldsStorage: Sendable {
  package let appearance: TerminalAppearance
  package let theme: Theme

  package init(appearance: TerminalAppearance, theme: Theme) {
    self.appearance = appearance
    self.theme = theme
  }
}

/// Styling state captured from the environment during resolve.
public struct StyleEnvironmentSnapshot: Equatable, Sendable {
  /// Boxed storage for the heavy value-type fields (~5 KB → 8 bytes).
  package var heavyFields: StyleHeavyFieldsStorage

  public var appearance: TerminalAppearance { heavyFields.appearance }
  public var theme: Theme { heavyFields.theme }
  public var foregroundStyle: AnyShapeStyle?
  public var tintStyle: AnyShapeStyle?
  public var isEnabled: Bool
  /// Display metrics for the current terminal surface.
  public var cellPixelMetrics: CellPixelMetrics

  public init(
    appearance: TerminalAppearance = .fallback,
    theme: Theme? = nil,
    foregroundStyle: AnyShapeStyle? = nil,
    tintStyle: AnyShapeStyle? = nil,
    isEnabled: Bool = true,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.heavyFields = StyleHeavyFieldsStorage(
      appearance: appearance,
      theme: theme ?? appearance.synthesizedTheme()
    )
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }

  /// Creates a snapshot reusing existing heavy-field storage (no copy).
  package init(
    heavyFields: StyleHeavyFieldsStorage,
    foregroundStyle: AnyShapeStyle?,
    tintStyle: AnyShapeStyle?,
    isEnabled: Bool,
    cellPixelMetrics: CellPixelMetrics = .estimated
  ) {
    self.heavyFields = heavyFields
    self.foregroundStyle = foregroundStyle
    self.tintStyle = tintStyle
    self.isEnabled = isEnabled
    self.cellPixelMetrics = cellPixelMetrics
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.heavyFields === rhs.heavyFields
      || (lhs.appearance == rhs.appearance
        && lhs.theme == rhs.theme
        && lhs.foregroundStyle == rhs.foregroundStyle
        && lhs.tintStyle == rhs.tintStyle
        && lhs.isEnabled == rhs.isEnabled
        && lhs.cellPixelMetrics == rhs.cellPixelMetrics)
  }
}

/// Stroke settings used when drawing outlines and rules.
///
/// `StrokeStyle` pairs a numeric line width with a ``BorderSet`` whose glyph
/// table drives the rasterizer. The default (``single``) produces
/// single-line box-drawing glyphs. When the default is used against a
/// shape with a positive corner radius the rasterizer upgrades it to
/// ``BorderSet/rounded`` so container chrome keeps its curved corners
/// without callers having to pass `.rounded` explicitly.
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int
  public var borderSet: BorderSet
  public var placement: Placement

  public enum Placement: Equatable, Sendable {
    case outset
    case inset
  }

  public init(
    lineWidth: Int = 1,
    borderSet: BorderSet = .single,
    placement: Placement = .outset
  ) {
    self.lineWidth = max(1, lineWidth)
    self.borderSet = borderSet
    self.placement = placement
  }
}

extension StrokeStyle {
  public static let normal = StrokeStyle(borderSet: .single)
  public static let rounded = StrokeStyle(borderSet: .rounded)
  public static let thick = StrokeStyle(borderSet: .heavy)
  public static let double = StrokeStyle(borderSet: .double)
  public static let ascii = StrokeStyle(borderSet: .ascii)
  public static let block = StrokeStyle(borderSet: .block)
  public static let outerHalfBlock = StrokeStyle(borderSet: .outerHalfBlock)
  public static let innerHalfBlock = StrokeStyle(borderSet: .innerHalfBlock)
  public static let hidden = StrokeStyle(borderSet: .hidden)
  public static let markdown = StrokeStyle(borderSet: .markdown)
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
  case circle
  case ellipse
  case capsule
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
  public var insetAmount: Int
  public var operation: ShapeOperation

  public init(
    geometry: ShapeGeometry,
    insetAmount: Int = 0,
    operation: ShapeOperation
  ) {
    self.geometry = geometry
    self.insetAmount = max(0, insetAmount)
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
        under.mixed(
          with: Color(red: overlay.red, green: overlay.green, blue: overlay.blue),
          amount: overlay.alpha)
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
      backgroundColor: (backgroundColor ?? Color.black).mixed(with: opaque, amount: amount),
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
  appearance: TerminalAppearance? = nil,
  depthLimit: Int = 8
) -> Result<Color, ColorResolutionError> {
  resolveStyleColorResult(
    style: style,
    theme: theme,
    appearance: appearance,
    depth: 0,
    depthLimit: depthLimit
  )
}

func resolveStyleColor(
  style: AnyShapeStyle,
  theme: Theme,
  appearance: TerminalAppearance? = nil,
  depth: Int = 0
) -> Color? {
  switch resolveStyleColorResult(
    style: style,
    theme: theme,
    appearance: appearance,
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
  appearance: TerminalAppearance?,
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
  case .radialGradient(let gradient):
    guard let firstColor = gradient.gradient.stops.first?.color else {
      return .failure(.emptyGradient)
    }
    return .success(firstColor)
  case .patternFill(let pattern):
    // A pattern fill reduces to the representative color of its
    // foreground paint (its flat color, or the gradient's first
    // stop).  The rasterizer handles the glyph and optional
    // background separately when painting.
    guard let fg = pattern.foreground.representativeColor else {
      return .failure(.emptyGradient)
    }
    return .success(fg)
  case .terminalChrome(let chromeStyle):
    return resolveStyleColorResult(
      style: theme.resolvedStyle(
        for: chromeStyle,
        appearance: appearance ?? synthesizedAppearance(for: theme)
      ),
      theme: theme,
      appearance: appearance,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  case .semantic(let role):
    return resolveStyleColorResult(
      style: theme.style(for: role),
      theme: theme,
      appearance: appearance,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  case .opacity(let inner, _):
    return resolveStyleColorResult(
      style: inner,
      theme: theme,
      appearance: appearance,
      depth: depth + 1,
      depthLimit: depthLimit
    )
  }
}
