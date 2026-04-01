/// Semantic tones used by terminal-native chrome styles.
public enum TerminalTone: String, CaseIterable, Hashable, Sendable {
  case accent
  case info
  case success
  case warning
  case danger
  case neutral
}

/// A shape style that resolves to terminal-native chrome colors.
public struct TerminalChromeStyle: ShapeStyle, Equatable, Sendable {
  /// The terminal-native surface or accent treatment to render.
  public enum Kind: Equatable, Sendable {
    case accent(tone: TerminalTone)
    case surface(tone: TerminalTone)
    case surfaceBackground
    case border(tone: TerminalTone)
    case tile(tone: TerminalTone)
    case row(tone: TerminalTone, isSelected: Bool, isOdd: Bool)
    case badge(tone: TerminalTone, emphasized: Bool)
    case keycap(tone: TerminalTone)
    case tab(tone: TerminalTone, isSelected: Bool)
  }

  public var kind: Kind

  public init(_ kind: Kind) {
    self.kind = kind
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .terminalChrome(self)
  }
}

extension ShapeStyle where Self == TerminalChromeStyle {
  public static func terminalAccent(
    _ tone: TerminalTone = .accent
  ) -> Self {
    .init(.accent(tone: tone))
  }

  public static func terminalSurface(
    _ tone: TerminalTone = .accent
  ) -> Self {
    .init(.surface(tone: tone))
  }

  public static var terminalSurfaceBackground: Self {
    .init(.surfaceBackground)
  }

  public static func terminalBorder(
    _ tone: TerminalTone = .accent
  ) -> Self {
    .init(.border(tone: tone))
  }

  public static func terminalTile(
    _ tone: TerminalTone = .accent
  ) -> Self {
    .init(.tile(tone: tone))
  }

  public static func terminalRow(
    _ tone: TerminalTone = .neutral,
    isSelected: Bool = false,
    isOdd: Bool = false
  ) -> Self {
    .init(.row(tone: tone, isSelected: isSelected, isOdd: isOdd))
  }

  public static func terminalBadge(
    _ tone: TerminalTone = .accent,
    emphasized: Bool = false
  ) -> Self {
    .init(.badge(tone: tone, emphasized: emphasized))
  }

  public static func terminalKeycap(
    _ tone: TerminalTone = .neutral
  ) -> Self {
    .init(.keycap(tone: tone))
  }

  public static func terminalTab(
    _ tone: TerminalTone = .accent,
    isSelected: Bool = false
  ) -> Self {
    .init(.tab(tone: tone, isSelected: isSelected))
  }
}

extension TerminalAppearance {
  package func resolvedStyle(
    for chromeStyle: TerminalChromeStyle
  ) -> AnyShapeStyle {
    switch chromeStyle.kind {
    case .accent(let tone):
      return .color(terminalToneColor(for: tone))
    case .surface(let tone):
      return terminalSurfaceStyle(tone: tone)
    case .surfaceBackground:
      return .color(backgroundColor)
    case .border(let tone):
      return terminalBorderStyle(tone: tone)
    case .tile(let tone):
      return .color(
        backgroundColor.mixed(with:
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.18 : 0.1
        )
      )
    case .row(let tone, let isSelected, let isOdd):
      return terminalRowStyle(
        tone: tone,
        isSelected: isSelected,
        isOdd: isOdd
      )
    case .badge(let tone, let emphasized):
      if emphasized {
        return .color(terminalToneColor(for: tone))
      }
      return .color(
        backgroundColor.mixed(with:
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.16 : 0.08
        )
      )
    case .keycap(let tone):
      return .color(
        backgroundColor.mixed(with:
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.1 : 0.05
        )
      )
    case .tab(let tone, let isSelected):
      if isSelected {
        return .color(
          backgroundColor.mixed(with:
            terminalToneColor(for: tone),
            amount: colorScheme == .dark ? 0.22 : 0.14
          )
        )
      }
      return .color(
        backgroundColor.mixed(with:
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.06 : 0.03
        )
      )
    }
  }

  private var terminalSurfaceBase: Color {
    terminalColorForScheme(
      dark: try! Color(hex:"#1F2330"),
      light: try! Color(hex:"#F8F7FC")
    )
  }

  private var terminalTabBase: Color {
    terminalColorForScheme(
      dark: try! Color(hex:"#1A1F2B"),
      light: try! Color(hex:"#F2F4F7")
    )
  }

  private func terminalColorForScheme(
    dark: Color,
    light: Color
  ) -> Color {
    colorScheme == .dark ? dark : light
  }

  private func terminalToneColor(
    for tone: TerminalTone
  ) -> Color {
    switch tone {
    case .accent:
      return contrastSafe(
        tintColor,
        against: backgroundColor,
        minimumContrast: 3,
        fallback: terminalColorForScheme(
          dark: try! Color(hex:"#7DE2D1"),
          light: try! Color(hex:"#1976D2")
        )
      )
    case .info:
      return terminalColorForScheme(
        dark: try! Color(hex:"#4CC9F0"),
        light: try! Color(hex:"#1976D2")
      )
    case .success:
      return terminalColorForScheme(
        dark: try! Color(hex:"#04B575"),
        light: try! Color(hex:"#0F8B63")
      )
    case .warning:
      return terminalColorForScheme(
        dark: try! Color(hex:"#F2B94B"),
        light: try! Color(hex:"#B7791F")
      )
    case .danger:
      return terminalColorForScheme(
        dark: try! Color(hex:"#F76E6E"),
        light: try! Color(hex:"#C24141")
      )
    case .neutral:
      return backgroundColor.mixed(with:
        foregroundColor,
        amount: colorScheme == .dark ? 0.54 : 0.44
      )
    }
  }

  private func terminalSurfaceStyle(
    tone: TerminalTone
  ) -> AnyShapeStyle {
    .color(
      backgroundColor.mixed(with:
        terminalToneColor(for: tone),
        amount: colorScheme == .dark ? 0.1 : 0.05
      )
    )
  }

  private func terminalBorderStyle(
    tone: TerminalTone
  ) -> AnyShapeStyle {
    .color(
      backgroundColor.mixed(with:
        terminalToneColor(for: tone),
        amount:
          tone == .neutral
          ? (colorScheme == .dark ? 0.24 : 0.18)
          : (colorScheme == .dark ? 0.52 : 0.36)
      )
    )
  }

  private func terminalRowStyle(
    tone: TerminalTone,
    isSelected: Bool,
    isOdd: Bool
  ) -> AnyShapeStyle {
    let neutralBase = backgroundColor

    if isSelected {
      return .color(
        neutralBase.mixed(with:
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.18 : 0.11
        )
      )
    }

    let overlayStrength =
      isOdd
      ? (colorScheme == .dark ? 0.04 : 0.02)
      : (colorScheme == .dark ? 0.03 : 0.01)

    return .color(
      neutralBase.mixed(with:
        foregroundColor,
        amount: overlayStrength
      )
    )
  }
}

package func synthesizedAppearance(
  for theme: Theme
) -> TerminalAppearance {
  let fallback = TerminalAppearance.fallback
  let foreground = synthesizedAppearanceColor(
    from: theme.foreground,
    theme: theme,
    fallback: fallback.foregroundColor
  )
  let background = synthesizedAppearanceColor(
    from: theme.background,
    theme: theme,
    fallback: fallback.backgroundColor
  )
  let tint = synthesizedAppearanceColor(
    from: theme.tint,
    theme: theme,
    fallback: fallback.tintColor
  )

  return .init(
    foregroundColor: foreground,
    backgroundColor: background,
    tintColor: tint,
    palette: fallback.palette,
    source: .fallback
  )
}

private func synthesizedAppearanceColor(
  from style: AnyShapeStyle,
  theme: Theme,
  fallback: Color,
  depth: Int = 0
) -> Color {
  guard depth < 8 else {
    return fallback
  }

  switch style {
  case .semantic(let role):
    return synthesizedAppearanceColor(
      from: theme.style(for: role),
      theme: theme,
      fallback: fallback,
      depth: depth + 1
    )
  case .color(let color):
    return color
  case .linearGradient(let gradient):
    return gradient.gradient.stops.first?.color ?? fallback
  case .terminalChrome:
    return fallback
  case .opacity(let inner, let amount):
    let resolved = synthesizedAppearanceColor(
      from: inner,
      theme: theme,
      fallback: fallback,
      depth: depth + 1
    )
    return resolved.opacity(amount)
  }
}
