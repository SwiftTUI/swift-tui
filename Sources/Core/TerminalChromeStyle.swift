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

extension Theme {
  package func resolvedStyle(
    for chromeStyle: TerminalChromeStyle
  ) -> AnyShapeStyle {
    let appearance = synthesizedAppearance(for: self)

    switch chromeStyle.kind {
    case .accent(let tone):
      return .color(terminalToneColor(for: tone, appearance: appearance))
    case .surface(let tone):
      return terminalSurfaceStyle(tone: tone, appearance: appearance)
    case .surfaceBackground:
      return background
    case .border(let tone):
      return terminalBorderStyle(tone: tone, appearance: appearance)
    case .tile(let tone):
      return .color(
        appearance.backgroundColor.mixed(with:
          terminalToneColor(for: tone, appearance: appearance),
          amount: appearance.colorScheme == .dark ? 0.18 : 0.1
        )
      )
    case .row(let tone, let isSelected, let isOdd):
      return terminalRowStyle(
        tone: tone,
        isSelected: isSelected,
        isOdd: isOdd,
        appearance: appearance
      )
    case .badge(let tone, let emphasized):
      if emphasized {
        return .color(terminalToneColor(for: tone, appearance: appearance))
      }
      return .color(
        appearance.backgroundColor.mixed(with:
          terminalToneColor(for: tone, appearance: appearance),
          amount: appearance.colorScheme == .dark ? 0.16 : 0.08
        )
      )
    case .keycap(let tone):
      return .color(
        appearance.backgroundColor.mixed(with:
          terminalToneColor(for: tone, appearance: appearance),
          amount: appearance.colorScheme == .dark ? 0.1 : 0.05
        )
      )
    case .tab(let tone, let isSelected):
      if isSelected {
        return .color(
          appearance.backgroundColor.mixed(with:
            terminalToneColor(for: tone, appearance: appearance),
            amount: appearance.colorScheme == .dark ? 0.22 : 0.14
          )
        )
      }
      return .color(
        appearance.backgroundColor.mixed(with:
          terminalToneColor(for: tone, appearance: appearance),
          amount: appearance.colorScheme == .dark ? 0.06 : 0.03
        )
      )
    }
  }

  private func resolvedThemeColor(
    _ style: AnyShapeStyle,
    fallback: Color
  ) -> Color {
    resolveStyleColor(style: style, theme: self) ?? fallback
  }

  private func terminalToneColor(
    for tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> Color {
    switch tone {
    case .accent:
      return resolvedThemeColor(tint, fallback: appearance.tintColor)
    case .info:
      return resolvedThemeColor(info, fallback: .hex("#4CC9F0"))
    case .success:
      return resolvedThemeColor(success, fallback: .hex("#04B575"))
    case .warning:
      return resolvedThemeColor(warning, fallback: .hex("#F2B94B"))
    case .danger:
      return resolvedThemeColor(danger, fallback: .hex("#F76E6E"))
    case .neutral:
      return appearance.backgroundColor.mixed(with:
        appearance.foregroundColor,
        amount: appearance.colorScheme == .dark ? 0.54 : 0.44
      )
    }
  }

  private func terminalSurfaceStyle(
    tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    .color(
      appearance.backgroundColor.mixed(with:
        terminalToneColor(for: tone, appearance: appearance),
        amount: appearance.colorScheme == .dark ? 0.1 : 0.05
      )
    )
  }

  private func terminalBorderStyle(
    tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    .color(
      appearance.backgroundColor.mixed(with:
        terminalToneColor(for: tone, appearance: appearance),
        amount:
          tone == .neutral
          ? (appearance.colorScheme == .dark ? 0.24 : 0.18)
          : (appearance.colorScheme == .dark ? 0.52 : 0.36)
      )
    )
  }

  private func terminalRowStyle(
    tone: TerminalTone,
    isSelected: Bool,
    isOdd: Bool,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    let neutralBase = appearance.backgroundColor

    if isSelected {
      return .color(
        neutralBase.mixed(with:
          terminalToneColor(for: tone, appearance: appearance),
          amount: appearance.colorScheme == .dark ? 0.18 : 0.11
        )
      )
    }

    let overlayStrength =
      isOdd
      ? (appearance.colorScheme == .dark ? 0.04 : 0.02)
      : (appearance.colorScheme == .dark ? 0.03 : 0.01)

    return .color(
      neutralBase.mixed(with:
        appearance.foregroundColor,
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
