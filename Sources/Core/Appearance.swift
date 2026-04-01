/// The effective light or dark appearance category of the terminal.
public enum ColorScheme: String, Equatable, Sendable {
  case light
  case dark
}

/// The effective contrast level of the terminal appearance.
public enum ColorSchemeContrast: String, Equatable, Sendable {
  case standard
  case increased
}

/// How a terminal appearance value was determined.
public enum AppearanceSource: String, Equatable, Sendable {
  case activeQuery
  case environmentHeuristics
  case fallback
  case override
}

/// A semantic prominence hint for emphasized controls.
public enum ControlProminence: Hashable, Sendable {
  case standard
  case increased
}

/// A semantic role for buttons and other confirm or cancel actions.
public enum ButtonRole: Hashable, Sendable {
  case cancel
  case destructive
  case close
  case confirm
}

/// A high-level visual treatment for buttons.
public enum ButtonStyle: Hashable, Sendable {
  case automatic
  case plain
  case bordered
  case borderedProminent
  case link
}

/// The resolved chrome used to render a focused or interactive control.
public struct ControlChrome: Equatable, Sendable {
  public var foregroundStyle: AnyShapeStyle
  public var contentBackgroundStyle: AnyShapeStyle
  public var borderForegroundStyle: AnyShapeStyle
  public var borderBackgroundStyle: AnyShapeStyle?
  public var opacity: Double

  public init(
    foregroundStyle: AnyShapeStyle,
    contentBackgroundStyle: AnyShapeStyle,
    borderForegroundStyle: AnyShapeStyle,
    borderBackgroundStyle: AnyShapeStyle? = nil,
    opacity: Double = 1
  ) {
    self.foregroundStyle = foregroundStyle
    self.contentBackgroundStyle = contentBackgroundStyle
    self.borderForegroundStyle = borderForegroundStyle
    self.borderBackgroundStyle = borderBackgroundStyle
    self.opacity = opacity
  }

  public var backgroundStyle: AnyShapeStyle {
    contentBackgroundStyle
  }

  public var borderStyle: AnyShapeStyle {
    borderForegroundStyle
  }
}

/// The resolved chrome used to render a container such as a group box.
public struct ContainerChrome: Equatable, Sendable {
  public var foregroundStyle: AnyShapeStyle
  public var backgroundStyle: AnyShapeStyle
  public var borderStyle: AnyShapeStyle

  public init(
    foregroundStyle: AnyShapeStyle,
    backgroundStyle: AnyShapeStyle,
    borderStyle: AnyShapeStyle
  ) {
    self.foregroundStyle = foregroundStyle
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
  }
}

/// The resolved visual appearance of the current terminal session.
public struct TerminalAppearance: Equatable, Sendable {
  public var foregroundColor: Color
  public var backgroundColor: Color
  public var tintColor: Color
  public var palette: [Int: Color]
  public var colorScheme: ColorScheme
  public var colorSchemeContrast: ColorSchemeContrast
  public var source: AppearanceSource

  /// Creates a terminal appearance explicitly.
  public init(
    foregroundColor: Color,
    backgroundColor: Color,
    tintColor: Color,
    palette: [Int: Color] = TerminalAppearance.defaultPalette,
    colorScheme: ColorScheme? = nil,
    colorSchemeContrast: ColorSchemeContrast? = nil,
    source: AppearanceSource = .fallback
  ) {
    self.foregroundColor = foregroundColor
    self.backgroundColor = backgroundColor
    self.tintColor = tintColor
    self.palette = palette

    let resolvedColorScheme =
      colorScheme
      ?? TerminalAppearance.derivedColorScheme(
        backgroundColor: backgroundColor
      )
    self.colorScheme = resolvedColorScheme
    self.colorSchemeContrast =
      colorSchemeContrast
      ?? TerminalAppearance.derivedColorSchemeContrast(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor
      )
    self.source = source
  }

  public static let fallback = Self(
    foregroundColor: try! .init(hex: "#ECEFF4"),
    backgroundColor: try! .init(hex: "#1E222A"),
    tintColor: .cyan,
    source: .fallback
  )

  public static let defaultPalette: [Int: Color] = [
    0: try! .init(hex: "#20242C"),
    1: try! .init(hex: "#E05757"),
    2: try! .init(hex: "#61C67B"),
    3: try! .init(hex: "#EBB33C"),
    4: try! .init(hex: "#5BA3FF"),
    5: try! .init(hex: "#B46EFF"),
    6: try! .init(hex: "#56B6C2"),
    7: try! .init(hex: "#ECEFF4"),
    8: try! .init(hex: "#8C92AC"),
    9: try! .init(hex: "#FF7B72"),
    10: try! .init(hex: "#7EE787"),
    11: try! .init(hex: "#F2CC60"),
    12: try! .init(hex: "#79C0FF"),
    13: try! .init(hex: "#D2A8FF"),
    14: try! .init(hex: "#7DE2D1"),
    15: .white,
  ]

  /// Applies a preferred light or dark override while preserving other
  /// appearance inputs.
  public func applyingPreferredColorScheme(
    _ preferredColorScheme: ColorScheme?
  ) -> Self {
    guard let preferredColorScheme, preferredColorScheme != colorScheme else {
      return self
    }

    let overrideBackground: Color =
      switch preferredColorScheme {
      case .dark:
        try! .init(hex: "#15181E")
      case .light:
        try! .init(hex: "#F6F7F9")
      }

    let overrideForeground: Color =
      switch preferredColorScheme {
      case .dark:
        try! .init(hex: "#ECEFF4")
      case .light:
        try! .init(hex: "#161A20")
      }

    return .init(
      foregroundColor: overrideForeground,
      backgroundColor: overrideBackground,
      tintColor: tintColor,
      palette: palette,
      colorScheme: preferredColorScheme,
      colorSchemeContrast: Self.derivedColorSchemeContrast(
        foregroundColor: overrideForeground,
        backgroundColor: overrideBackground
      ),
      source: .override
    )
  }

  /// Derives the semantic theme exposed to higher-level styling APIs.
  public func semanticTheme() -> Theme {
    let separator = backgroundColor.mixed(with: foregroundColor, amount: separatorMixAmount)
    let fill = elevatedSurface(
      from: backgroundColor,
      scheme: colorScheme,
      amount: 0.08
    )
    let windowBackground = elevatedSurface(
      from: backgroundColor,
      scheme: colorScheme,
      amount: 0.04,
      invert: true
    )
    let muted = backgroundColor.mixed(with: foregroundColor, amount: mutedMixAmount)
    let placeholder = backgroundColor.mixed(with: foregroundColor, amount: placeholderMixAmount)
    let safeTint = contrastSafe(
      tintColor,
      against: backgroundColor,
      minimumContrast: 3,
      fallback: fallbackTint
    )
    let selection = contrastSafe(
      backgroundColor.mixed(with: safeTint, amount: selectionMixAmount),
      against: backgroundColor,
      minimumContrast: 1.35,
      fallback: elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.14)
    )

    return .init(
      foreground: .color(foregroundColor),
      background: .color(backgroundColor),
      tint: .color(safeTint),
      separator: .color(separator),
      selection: .color(selection),
      placeholder: .color(placeholder),
      link: .color(
        contrastSafe(
          roleColor(for: 4, fallback: safeTint), against: backgroundColor, minimumContrast: 3,
          fallback: safeTint)),
      fill: .color(fill),
      windowBackground: .color(windowBackground),
      success: .color(
        contrastSafe(
          roleColor(for: 2, fallback: .green), against: backgroundColor, minimumContrast: 2.5,
          fallback: .green)),
      warning: .color(
        contrastSafe(
          roleColor(for: 3, fallback: .yellow), against: backgroundColor, minimumContrast: 2.5,
          fallback: .yellow)),
      danger: .color(
        contrastSafe(
          roleColor(for: 1, fallback: .red), against: backgroundColor, minimumContrast: 2.5,
          fallback: .red)),
      info: .color(
        contrastSafe(
          roleColor(for: 6, fallback: .cyan), against: backgroundColor, minimumContrast: 2.5,
          fallback: .cyan)),
      muted: .color(muted)
    )
  }

}

extension TerminalAppearance {
  public static func derivedColorScheme(
    backgroundColor: Color
  ) -> ColorScheme {
    backgroundColor.relativeLuminance < 0.5 ? .dark : .light
  }

  public static func derivedColorSchemeContrast(
    foregroundColor: Color,
    backgroundColor: Color
  ) -> ColorSchemeContrast {
    foregroundColor.contrastRatio(to: backgroundColor) >= 7 ? .increased : .standard
  }
}

extension TerminalAppearance {
  private var separatorMixAmount: Double {
    colorScheme == .dark ? 0.22 : 0.28
  }

  private var mutedMixAmount: Double {
    colorScheme == .dark ? 0.52 : 0.6
  }

  private var placeholderMixAmount: Double {
    colorScheme == .dark ? 0.36 : 0.44
  }

  private var selectionMixAmount: Double {
    colorScheme == .dark ? 0.3 : 0.2
  }

  private var fallbackTint: Color {
    switch colorScheme {
    case .dark:
      return .cyan
    case .light:
      return .blue
    }
  }

  private func roleColor(
    for index: Int,
    fallback: Color
  ) -> Color {
    palette[index] ?? fallback
  }

  private func elevatedSurface(
    from base: Color,
    scheme: ColorScheme,
    amount: Double,
    invert: Bool = false
  ) -> Color {
    switch (scheme, invert) {
    case (.dark, false), (.light, true):
      return base.mixed(with: .white, amount: amount)
    case (.dark, true), (.light, false):
      return base.mixed(with: .black, amount: amount)
    }
  }

}

extension StyleEnvironmentSnapshot {
  package func controlChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let neutralSurface = theme.background
    let focusedSurface = AnyShapeStyle(
      prominence == .increased ? .terminalAccent(tone) : .terminalRow(tone, isSelected: true)
    )
    let selectedSurface = AnyShapeStyle(.terminalRow(tone, isSelected: true))
    let neutralBorder = AnyShapeStyle(.terminalBorder(.neutral))
    let focusedBorder = AnyShapeStyle(.terminalBorder(tone))

    if !isEnabled {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: neutralSurface,
        borderForegroundStyle: neutralBorder,
        opacity: 0.6
      )
    }

    if prominence == .increased {
      let idleFillStyle = AnyShapeStyle(.terminalAccent(tone))
      let focusedFillStyle = AnyShapeStyle(.terminalRow(tone, isSelected: true))
      let pressedFillStyle = AnyShapeStyle(.terminalSurface(tone))
      let fillStyle =
        if isPressed {
          pressedFillStyle
        } else if isFocused {
          focusedFillStyle
        } else {
          idleFillStyle
        }

      return .init(
        foregroundStyle: contrastingForegroundStyle(on: fillStyle),
        contentBackgroundStyle: fillStyle,
        borderForegroundStyle: focusedBorder
      )
    }

    if isSelected {
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: selectedSurface,
        borderForegroundStyle: focusedBorder
      )
    }

    if isFocused || isPressed {
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: focusedSurface,
        borderForegroundStyle: focusedBorder
      )
    }

    return .init(
      foregroundStyle: theme.foreground,
      contentBackgroundStyle: neutralSurface,
      borderForegroundStyle: neutralBorder
    )
  }

  package func rowChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let idleBackground = theme.background
    let activeBackground = AnyShapeStyle(.terminalRow(tone, isSelected: true))
    let activeBorder = AnyShapeStyle(.terminalBorder(tone))
    let idleBorder = AnyShapeStyle(.terminalBorder(.neutral))

    if !isEnabled {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: idleBackground,
        borderForegroundStyle: idleBorder,
        opacity: 0.6
      )
    }

    if isPressed || isFocused || isSelected {
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: activeBackground,
        borderForegroundStyle: activeBorder
      )
    }

    return .init(
      foregroundStyle: theme.foreground,
      contentBackgroundStyle: idleBackground,
      borderForegroundStyle: idleBorder
    )
  }

  package func buttonChrome(
    buttonStyle: ButtonStyle,
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    switch buttonStyle {
    case .plain:
      return standardPlainButtonChrome(isEnabled: isEnabled, role: role)
    case .link:
      return standardLinkButtonChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        role: role
      )
    case .bordered:
      return controlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: false,
        prominence: .standard,
        role: role
      )
    case .automatic, .borderedProminent:
      return controlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: false,
        prominence: .increased,
        role: role
      )
    }
  }

  package func groupBoxChrome(
    prominence: ControlProminence = .standard
  ) -> ContainerChrome {
    let tone: TerminalTone = prominence == .increased ? .accent : .neutral
    return .init(
      foregroundStyle: theme.foreground,
      backgroundStyle: theme.background,
      borderStyle: AnyShapeStyle(.terminalBorder(tone))
    )
  }

  private func standardPlainButtonChrome(
    isEnabled: Bool,
    role: ButtonRole?
  ) -> ControlChrome {
    guard isEnabled else {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: theme.background,
        borderForegroundStyle: theme.background,
        opacity: 0.6
      )
    }

    return .init(
      foregroundStyle: plainForegroundStyle(for: role),
      contentBackgroundStyle: theme.background,
      borderForegroundStyle: theme.background
    )
  }

  private func standardLinkButtonChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool,
    role: ButtonRole?
  ) -> ControlChrome {
    guard isEnabled else {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: theme.background,
        borderForegroundStyle: theme.background,
        opacity: 0.6
      )
    }

    let tone = chromeTone(for: role)
    let background =
      if isFocused || isPressed {
        AnyShapeStyle(.terminalRow(tone, isSelected: true))
      } else {
        theme.background
      }

    return .init(
      foregroundStyle: linkForegroundStyle(for: role),
      contentBackgroundStyle: background,
      borderForegroundStyle: theme.background
    )
  }

  private func plainForegroundStyle(
    for role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case .destructive:
      theme.danger
    case .cancel, .close:
      theme.muted
    case .confirm:
      theme.tint
    case nil:
      theme.foreground
    }
  }

  private func linkForegroundStyle(
    for role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case .destructive:
      theme.danger
    case .cancel, .close:
      theme.muted
    case .confirm:
      theme.tint
    case nil:
      theme.link
    }
  }

  private func contrastingForegroundStyle(
    on style: AnyShapeStyle
  ) -> AnyShapeStyle {
    guard let backgroundColor = resolveStyleColor(style: style, theme: theme) else {
      return theme.foreground
    }

    let whiteContrast = Color.white.contrastRatio(to: backgroundColor)
    let blackContrast = Color.black.contrastRatio(to: backgroundColor)
    return .color(whiteContrast >= blackContrast ? .white : .black)
  }

  private func chromeTone(
    for role: ButtonRole?
  ) -> TerminalTone {
    switch role {
    case .destructive:
      .danger
    case .cancel, .close:
      .neutral
    case .confirm, nil:
      .accent
    }
  }
}

func contrastSafe(
  _ color: Color,
  against background: Color,
  minimumContrast: Double,
  fallback: Color
) -> Color {
  color.contrastRatio(to: background) >= minimumContrast ? color : fallback
}
