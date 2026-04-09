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
    for chromeStyle: TerminalChromeStyle,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    switch chromeStyle.kind {
    case .accent(let tone):
      return .color(terminalToneColor(for: tone, appearance: appearance))
    case .surface(let tone):
      return terminalSurfaceStyle(tone: tone, appearance: appearance)
    case .surfaceBackground:
      return .color(background)
    case .border(let tone):
      return terminalBorderStyle(tone: tone, appearance: appearance)
    case .tile(let tone):
      return .color(
        appearance.backgroundColor.mixed(
          with:
            terminalToneColor(for: tone, appearance: appearance),
          amount: interpolatedAmount(dark: 0.18, light: 0.1, appearance: appearance)
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
        appearance.backgroundColor.mixed(
          with:
            terminalToneColor(for: tone, appearance: appearance),
          amount: interpolatedAmount(dark: 0.16, light: 0.08, appearance: appearance)
        )
      )
    case .keycap(let tone):
      return .color(
        appearance.backgroundColor.mixed(
          with:
            terminalToneColor(for: tone, appearance: appearance),
          amount: interpolatedAmount(dark: 0.1, light: 0.05, appearance: appearance)
        )
      )
    case .tab(let tone, let isSelected):
      if isSelected {
        return .color(
          appearance.backgroundColor.mixed(
            with:
              terminalToneColor(for: tone, appearance: appearance),
            amount: interpolatedAmount(dark: 0.22, light: 0.14, appearance: appearance)
          )
        )
      }
      return .color(
        appearance.backgroundColor.mixed(
          with:
            terminalToneColor(for: tone, appearance: appearance),
          amount: interpolatedAmount(dark: 0.06, light: 0.03, appearance: appearance)
        )
      )
    }
  }

  private func terminalToneColor(
    for tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> Color {
    switch tone {
    case .accent:
      return tint
    case .info:
      return info
    case .success:
      return success
    case .warning:
      return warning
    case .danger:
      return danger
    case .neutral:
      return appearance.backgroundColor.mixed(
        with:
          appearance.foregroundColor,
        amount: interpolatedAmount(dark: 0.54, light: 0.44, appearance: appearance)
      )
    }
  }

  private func terminalSurfaceStyle(
    tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    .color(
      appearance.backgroundColor.mixed(
        with:
          terminalToneColor(for: tone, appearance: appearance),
        amount: interpolatedAmount(dark: 0.1, light: 0.05, appearance: appearance)
      )
    )
  }

  private func terminalBorderStyle(
    tone: TerminalTone,
    appearance: TerminalAppearance
  ) -> AnyShapeStyle {
    .color(
      appearance.backgroundColor.mixed(
        with:
          terminalToneColor(for: tone, appearance: appearance),
        amount:
          tone == .neutral
          ? interpolatedAmount(dark: 0.24, light: 0.18, appearance: appearance)
          : interpolatedAmount(dark: 0.52, light: 0.36, appearance: appearance)
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
        neutralBase.mixed(
          with:
            terminalToneColor(for: tone, appearance: appearance),
          amount: interpolatedAmount(dark: 0.18, light: 0.11, appearance: appearance)
        )
      )
    }

    let overlayStrength =
      isOdd
      ? interpolatedAmount(dark: 0.04, light: 0.02, appearance: appearance)
      : interpolatedAmount(dark: 0.03, light: 0.01, appearance: appearance)

    return .color(
      neutralBase.mixed(
        with:
          appearance.foregroundColor,
        amount: overlayStrength
      )
    )
  }

  private func interpolatedAmount(
    dark: Double,
    light: Double,
    appearance: TerminalAppearance
  ) -> Double {
    let darkness = min(1, max(0, 1 - appearance.backgroundColor.relativeLuminance))
    return light + ((dark - light) * darkness)
  }
}

package func synthesizedAppearance(
  for theme: Theme
) -> TerminalAppearance {
  let fallback = TerminalAppearance.fallback
  return .init(
    foregroundColor: theme.foreground,
    backgroundColor: theme.background,
    tintColor: theme.tint,
    palette: fallback.palette,
    source: .fallback
  )
}
