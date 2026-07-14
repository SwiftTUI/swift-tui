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

/// Errors thrown while resolving semantic or gradient-based colors.
public enum ColorResolutionError: Error, Equatable, Sendable, CustomStringConvertible {
  case recursionLimitExceeded(limit: Int, style: AnyShapeStyle)
  case emptyGradient

  public var description: String {
    switch self {
    case .recursionLimitExceeded(let limit, _):
      "shape-style color resolution exceeded the recursion limit of \(limit)."
    case .emptyGradient:
      "cannot resolve a color from an empty gradient."
    }
  }
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

package func resolveStyleColor(
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
  case .opacity(let inner, let amount):
    // Apply the wrap's amount to the resolved color, matching the
    // rasterizer's resolver. Color/Gradient fold `.opacity()` eagerly at
    // construction, so the live inputs here are the residual style shapes
    // (`.semantic`, `.terminalChrome`, `.tileStyle` wrapped in opacity).
    return resolveStyleColorResult(
      style: inner,
      theme: theme,
      appearance: appearance,
      depth: depth + 1,
      depthLimit: depthLimit
    ).map { $0.opacity(amount) }
  }
}
