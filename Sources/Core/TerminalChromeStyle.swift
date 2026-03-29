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
      return terminalAccentStyle(tone: tone)
    case .surface(let tone):
      return terminalSurfaceStyle(tone: tone)
    case .surfaceBackground:
      return .color(terminalSurfaceBase)
    case .border(let tone):
      return terminalBorderStyle(tone: tone)
    case .tile(let tone):
      return .color(
        mix(
          terminalToneColor(for: tone),
          colorScheme == .dark ? .white : .black,
          amount: colorScheme == .dark ? 0.42 : 0.22
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
        return terminalAccentStyle(tone: tone)
      }
      return .color(
        mix(
          terminalToneColor(for: tone),
          colorScheme == .dark ? .black : .white,
          amount: colorScheme == .dark ? 0.28 : 0.12
        )
      )
    case .keycap(let tone):
      return .color(
        mix(
          terminalToneColor(for: tone),
          colorScheme == .dark ? .black : .white,
          amount: colorScheme == .dark ? 0.22 : 0.08
        )
      )
    case .tab(let tone, let isSelected):
      if isSelected {
        return terminalAccentStyle(tone: tone)
      }
      return .color(
        mix(
          terminalTabBase,
          terminalToneColor(for: tone),
          amount: colorScheme == .dark ? 0.16 : 0.06
        )
      )
    }
  }

  private var terminalSurfaceBase: Color {
    terminalColorForScheme(
      dark: .init(hex: 0x1F2330),
      light: .init(hex: 0xF8F7FC)
    )
  }

  private var terminalTabBase: Color {
    terminalColorForScheme(
      dark: .init(hex: 0x1A1F2B),
      light: .init(hex: 0xF2F4F7)
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
      return terminalColorForScheme(
        dark: .init(hex: 0x7D56F4),
        light: .init(hex: 0x6941C6)
      )
    case .info:
      return terminalColorForScheme(
        dark: .init(hex: 0x4CC9F0),
        light: .init(hex: 0x1976D2)
      )
    case .success:
      return terminalColorForScheme(
        dark: .init(hex: 0x04B575),
        light: .init(hex: 0x0F8B63)
      )
    case .warning:
      return terminalColorForScheme(
        dark: .init(hex: 0xF2B94B),
        light: .init(hex: 0xB7791F)
      )
    case .danger:
      return terminalColorForScheme(
        dark: .init(hex: 0xF76E6E),
        light: .init(hex: 0xC24141)
      )
    case .neutral:
      return terminalColorForScheme(
        dark: .init(hex: 0x98A2B3),
        light: .init(hex: 0x667085)
      )
    }
  }

  private func terminalAccentHighlight(
    for tone: TerminalTone
  ) -> Color {
    mix(
      terminalToneColor(for: tone),
      colorScheme == .dark ? .white : .black,
      amount: colorScheme == .dark ? 0.18 : 0.1
    )
  }

  private func terminalAccentShadow(
    for tone: TerminalTone
  ) -> Color {
    mix(
      terminalToneColor(for: tone),
      colorScheme == .dark ? .black : .white,
      amount: colorScheme == .dark ? 0.24 : 0.12
    )
  }

  private func terminalAccentStyle(
    tone: TerminalTone
  ) -> AnyShapeStyle {
    .linearGradient(
      .init(
        colors: [
          terminalAccentHighlight(for: tone),
          terminalToneColor(for: tone),
          terminalAccentShadow(for: tone),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }

  private func terminalSurfaceStyle(
    tone: TerminalTone
  ) -> AnyShapeStyle {
    let accent = terminalToneColor(for: tone)
    let lifted = mix(
      terminalSurfaceBase,
      accent,
      amount: colorScheme == .dark ? 0.12 : 0.06
    )
    let grounded = mix(
      terminalSurfaceBase,
      colorScheme == .dark ? .black : .white,
      amount: colorScheme == .dark ? 0.18 : 0.08
    )

    return .linearGradient(
      .init(
        colors: [lifted, terminalSurfaceBase, grounded],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func terminalBorderStyle(
    tone: TerminalTone
  ) -> AnyShapeStyle {
    .linearGradient(
      .init(
        colors: [
          terminalAccentHighlight(for: tone),
          terminalToneColor(for: tone),
          terminalColorForScheme(
            dark: .init(hex: 0x4A5568),
            light: .init(hex: 0xD0D5DD)
          ),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func terminalRowStyle(
    tone: TerminalTone,
    isSelected: Bool,
    isOdd: Bool
  ) -> AnyShapeStyle {
    let neutralBase = terminalColorForScheme(
      dark: .init(hex: 0x171B26),
      light: .white
    )

    if isSelected {
      return .linearGradient(
        .init(
          colors: [
            mix(
              neutralBase,
              terminalToneColor(for: tone),
              amount: colorScheme == .dark ? 0.3 : 0.12
            ),
            mix(
              neutralBase,
              terminalToneColor(for: .accent),
              amount: colorScheme == .dark ? 0.22 : 0.08
            ),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
    }

    let overlayStrength =
      isOdd
      ? (colorScheme == .dark ? 0.08 : 0.04)
      : (colorScheme == .dark ? 0.03 : 0.01)

    return .color(
      mix(
        neutralBase,
        terminalToneColor(for: tone),
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
  }
}
