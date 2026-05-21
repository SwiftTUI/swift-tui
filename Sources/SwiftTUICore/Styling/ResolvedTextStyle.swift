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
    composited(over: underlay, blendMode: nil)
  }

  internal func composited(
    over underlay: ResolvedTextStyle?,
    blendMode: BlendMode?
  ) -> ResolvedTextStyle {
    guard let underlay else {
      return self
    }

    let blendedBackground: Color? =
      if let blendMode {
        compositedColor(
          source: backgroundColor,
          over: underlay.backgroundColor,
          blendMode: blendMode
        )
      } else {
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
      }

    return .init(
      foregroundColor: compositedColor(
        source: foregroundColor,
        over: underlay.foregroundColor,
        blendMode: blendMode
      ),
      backgroundColor: blendedBackground,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  private func compositedColor(
    source: Color?,
    over backdrop: Color?,
    blendMode: BlendMode?
  ) -> Color? {
    guard let source else {
      return backdrop
    }
    guard let blendMode, let backdrop else {
      return source
    }
    return source.composited(over: backdrop, mode: blendMode)
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
  case .tileStyle(let tile):
    return resolveStyleColorResult(
      style: tile.foreground.style,
      theme: theme,
      appearance: appearance,
      depth: depth + 1,
      depthLimit: depthLimit
    )
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
