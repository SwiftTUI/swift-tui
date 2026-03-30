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
    foregroundColor: .init(hex: 0xECEFF4),
    backgroundColor: .init(hex: 0x1E222A),
    tintColor: .cyan,
    source: .fallback
  )

  public static let defaultPalette: [Int: Color] = [
    0: .init(hex: 0x20242C),
    1: .init(hex: 0xE05757),
    2: .init(hex: 0x61C67B),
    3: .init(hex: 0xEBB33C),
    4: .init(hex: 0x5BA3FF),
    5: .init(hex: 0xB46EFF),
    6: .init(hex: 0x56B6C2),
    7: .init(hex: 0xECEFF4),
    8: .init(hex: 0x8C92AC),
    9: .init(hex: 0xFF7B72),
    10: .init(hex: 0x7EE787),
    11: .init(hex: 0xF2CC60),
    12: .init(hex: 0x79C0FF),
    13: .init(hex: 0xD2A8FF),
    14: .init(hex: 0x7DE2D1),
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
        .init(hex: 0x15181E)
      case .light:
        .init(hex: 0xF6F7F9)
      }

    let overrideForeground: Color =
      switch preferredColorScheme {
      case .dark:
        .init(hex: 0xECEFF4)
      case .light:
        .init(hex: 0x161A20)
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
    let separator = mix(backgroundColor, foregroundColor, amount: separatorMixAmount)
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
    let muted = mix(backgroundColor, foregroundColor, amount: mutedMixAmount)
    let placeholder = mix(backgroundColor, foregroundColor, amount: placeholderMixAmount)
    let safeTint = contrastSafe(
      tintColor,
      against: backgroundColor,
      minimumContrast: 3,
      fallback: fallbackTint
    )
    let selection = contrastSafe(
      mix(backgroundColor, safeTint, amount: selectionMixAmount),
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

  public func controlChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let theme = semanticTheme()
    let accentStyle = buttonAccentStyle(theme: theme, role: role)
    let accentColor = parallelResolveColor(style: accentStyle, theme: theme) ?? tintColor
    let standardForegroundStyle = buttonForegroundStyle(theme: theme, role: role)
    let standardBorderColor =
      parallelResolveColor(style: buttonBorderStyle(theme: theme, role: role), theme: theme)
      ?? foregroundColor
    let standardBorderStyle = gleamBorderStyle(base: standardBorderColor)
    let idleSurfaceStyle = gleamSurfaceStyle(
      base: parallelResolveColor(style: theme.fill, theme: theme)
        ?? elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.08)
    )
    let focusedSurfaceStyle = gleamSurfaceStyle(
      base: mix(
        parallelResolveColor(style: theme.fill, theme: theme)
          ?? elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.08),
        accentColor,
        amount: colorScheme == .dark ? 0.08 : 0.05
      )
    )
    let selectedSurfaceStyle = gleamSurfaceStyle(
      base: mix(
        backgroundColor,
        accentColor,
        amount: colorScheme == .dark ? 0.16 : 0.11
      )
    )
    let accentFillStyle = gleamAccentStyle(base: accentColor)
    let accentBorderStyle = gleamBorderStyle(
      base: accentColor,
      highlightAmount: colorScheme == .dark ? 0.2 : 0.14,
      shadowAmount: colorScheme == .dark ? 0.1 : 0.06
    )

    if !isEnabled {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: gleamSurfaceStyle(
          base: parallelResolveColor(style: theme.windowBackground, theme: theme)
            ?? elevatedSurface(
              from: backgroundColor, scheme: colorScheme, amount: 0.04, invert: true)
        ),
        borderForegroundStyle: gleamBorderStyle(
          base: parallelResolveColor(style: theme.separator, theme: theme)
            ?? mix(backgroundColor, foregroundColor, amount: separatorMixAmount)
        ),
        opacity: 0.65
      )
    }

    if prominence == .increased {
      let pressedAccentFillStyle =
        isPressed
        ? gleamAccentStyle(
          base: elevatedSurface(
            from: accentColor,
            scheme: colorScheme,
            amount: colorScheme == .dark ? 0.12 : 0.08,
            invert: true
          )
        )
        : accentFillStyle
      let legibleForeground = legibleForegroundColor(on: accentColor)
      let contrastingForegroundStyle: AnyShapeStyle = .color(legibleForeground)
      let focusedProminentBorderColor = contrastSafe(
        colorScheme == .dark ? backgroundColor : foregroundColor,
        against: accentColor,
        minimumContrast: 3,
        fallback: legibleForeground
      )
      return .init(
        foregroundStyle: contrastingForegroundStyle,
        contentBackgroundStyle: pressedAccentFillStyle,
        borderForegroundStyle: gleamBorderStyle(
          base: isFocused ? focusedProminentBorderColor : legibleForeground
        )
      )
    }

    if isSelected {
      let selectedBackground =
        isPressed
        ? gleamSurfaceStyle(
          base: mix(
            backgroundColor,
            accentColor,
            amount: colorScheme == .dark ? 0.22 : 0.17
          )
        )
        : selectedSurfaceStyle
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: selectedBackground,
        borderForegroundStyle: accentBorderStyle
      )
    }

    if isPressed {
      return .init(
        foregroundStyle: standardForegroundStyle,
        contentBackgroundStyle: gleamSurfaceStyle(
          base: mix(
            parallelResolveColor(style: theme.fill, theme: theme)
              ?? elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.08),
            accentColor,
            amount: colorScheme == .dark ? 0.14 : 0.1
          )
        ),
        borderForegroundStyle: gleamBorderStyle(base: accentColor)
      )
    }

    if isFocused {
      return .init(
        foregroundStyle: standardForegroundStyle,
        contentBackgroundStyle: focusedSurfaceStyle,
        borderForegroundStyle: accentBorderStyle
      )
    }

    return .init(
      foregroundStyle: standardForegroundStyle,
      contentBackgroundStyle: idleSurfaceStyle,
      borderForegroundStyle: standardBorderStyle
    )
  }

  public func rowChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let theme = semanticTheme()
    let accentStyle = buttonAccentStyle(theme: theme, role: role)
    let accentColor = parallelResolveColor(style: accentStyle, theme: theme) ?? tintColor
    let neutralRowBase = mix(
      backgroundColor,
      foregroundColor,
      amount: colorScheme == .dark ? 0.02 : 0.015
    )
    let highlight = AnyShapeStyle.color(
      mix(
        backgroundColor,
        accentColor,
        amount: colorScheme == .dark ? 0.12 : 0.08
      )
    )

    if !isEnabled {
      return .init(
        foregroundStyle: theme.placeholder,
        contentBackgroundStyle: .color(backgroundColor),
        borderForegroundStyle: theme.separator,
        opacity: 0.65
      )
    }

    if isPressed {
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: .color(
          mix(
            backgroundColor,
            accentColor,
            amount: colorScheme == .dark ? 0.18 : 0.13
          )
        ),
        borderForegroundStyle: accentStyle
      )
    }

    if isFocused || isSelected {
      return .init(
        foregroundStyle: theme.foreground,
        contentBackgroundStyle: highlight,
        borderForegroundStyle: accentStyle
      )
    }

    return .init(
      foregroundStyle: theme.foreground,
      contentBackgroundStyle: .color(neutralRowBase),
      borderForegroundStyle: gleamBorderStyle(
        base: parallelResolveColor(style: theme.separator, theme: theme)
          ?? mix(backgroundColor, foregroundColor, amount: separatorMixAmount)
      )
    )
  }

  public func buttonChrome(
    buttonStyle: ButtonStyle,
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    let theme = semanticTheme()
    let effectiveProminence: ControlProminence =
      buttonStyle == .borderedProminent ? .increased : prominence

    switch buttonStyle {
    case .plain:
      if !isEnabled {
        return .init(
          foregroundStyle: theme.placeholder,
          contentBackgroundStyle: .color(backgroundColor),
          borderForegroundStyle: .color(backgroundColor),
          opacity: 0.65
        )
      }

      let foregroundStyle = buttonForegroundStyle(theme: theme, role: role)
      return .init(
        foregroundStyle: foregroundStyle,
        contentBackgroundStyle: .color(backgroundColor),
        borderForegroundStyle: .color(backgroundColor)
      )

    case .link:
      let foregroundStyle = buttonLinkForegroundStyle(theme: theme, role: role)
      let linkColor =
        parallelResolveColor(style: foregroundStyle, theme: theme)
        ?? parallelResolveColor(style: theme.link, theme: theme)
        ?? tintColor

      if !isEnabled {
        return .init(
          foregroundStyle: theme.placeholder,
          contentBackgroundStyle: .color(backgroundColor),
          borderForegroundStyle: .color(backgroundColor),
          opacity: 0.65
        )
      }

      let focusedBackgroundStyle: AnyShapeStyle =
        isFocused || isPressed
        ? .color(
          mix(
            backgroundColor,
            linkColor,
            amount: colorScheme == .dark ? 0.12 : 0.08
          )
        )
        : .color(backgroundColor)

      return .init(
        foregroundStyle: foregroundStyle,
        contentBackgroundStyle: focusedBackgroundStyle,
        borderForegroundStyle: .color(backgroundColor)
      )

    case .automatic, .bordered, .borderedProminent:
      return controlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        prominence: effectiveProminence,
        role: role
      )
    }
  }

  public func groupBoxChrome(
    prominence: ControlProminence = .standard
  ) -> ContainerChrome {
    let theme = semanticTheme()
    let backgroundBase =
      parallelResolveColor(style: theme.windowBackground, theme: theme)
      ?? elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.04, invert: true)
    let fillBase =
      parallelResolveColor(style: theme.fill, theme: theme)
      ?? elevatedSurface(from: backgroundColor, scheme: colorScheme, amount: 0.08)

    switch prominence {
    case .increased:
      return .init(
        foregroundStyle: theme.foreground,
        backgroundStyle: gleamSurfaceStyle(
          base: mix(fillBase, tintColor, amount: colorScheme == .dark ? 0.1 : 0.07)
        ),
        borderStyle: gleamBorderStyle(base: tintColor)
      )
    default:
      return .init(
        foregroundStyle: theme.foreground,
        backgroundStyle: gleamSurfaceStyle(base: backgroundBase),
        borderStyle: gleamBorderStyle(
          base: parallelResolveColor(style: theme.separator, theme: theme)
            ?? mix(backgroundColor, foregroundColor, amount: separatorMixAmount)
        )
      )
    }
  }
}

extension TerminalAppearance {
  public static func derivedColorScheme(
    backgroundColor: Color
  ) -> ColorScheme {
    relativeLuminance(backgroundColor) < 0.5 ? .dark : .light
  }

  public static func derivedColorSchemeContrast(
    foregroundColor: Color,
    backgroundColor: Color
  ) -> ColorSchemeContrast {
    contrastRatio(foregroundColor, backgroundColor) >= 7 ? .increased : .standard
  }
}

extension TerminalAppearance {
  private func buttonAccentStyle(
    theme: Theme,
    role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case let role? where role == .destructive:
      return theme.danger
    case let role? where role == .cancel || role == .close:
      return theme.muted
    case let role? where role == .confirm:
      return theme.tint
    case nil:
      return theme.tint
    default:
      return theme.tint
    }
  }

  private func buttonForegroundStyle(
    theme: Theme,
    role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case let role? where role == .destructive:
      return theme.danger
    case let role? where role == .cancel || role == .close:
      return theme.muted
    case let role? where role == .confirm:
      return theme.tint
    case nil:
      return theme.foreground
    default:
      return theme.foreground
    }
  }

  private func buttonLinkForegroundStyle(
    theme: Theme,
    role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case let role? where role == .destructive:
      return theme.danger
    case let role? where role == .cancel || role == .close:
      return theme.muted
    case let role? where role == .confirm:
      return theme.tint
    case nil:
      return theme.link
    default:
      return theme.link
    }
  }

  private func buttonBorderStyle(
    theme: Theme,
    role: ButtonRole?
  ) -> AnyShapeStyle {
    switch role {
    case let role? where role == .destructive || role == .confirm:
      return buttonAccentStyle(theme: theme, role: role)
    case let role? where role == .cancel || role == .close:
      return theme.separator
    case nil:
      return theme.separator
    default:
      return theme.separator
    }
  }

  private func legibleForegroundColor(
    on backgroundColor: Color
  ) -> Color {
    let whiteContrast = contrastRatio(.white, backgroundColor)
    let blackContrast = contrastRatio(.black, backgroundColor)
    return whiteContrast >= blackContrast ? .white : .black
  }

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
      return mix(base, .white, amount: amount)
    case (.dark, true), (.light, false):
      return mix(base, .black, amount: amount)
    }
  }

  private func gleamSurfaceStyle(
    base: Color,
    highlightAmount: Double? = nil,
    shadowAmount: Double? = nil
  ) -> AnyShapeStyle {
    let lifted = elevatedSurface(
      from: base,
      scheme: colorScheme,
      amount: highlightAmount ?? (colorScheme == .dark ? 0.12 : 0.06)
    )
    let grounded = elevatedSurface(
      from: base,
      scheme: colorScheme,
      amount: shadowAmount ?? (colorScheme == .dark ? 0.08 : 0.04),
      invert: true
    )
    return .linearGradient(
      .init(
        gradient: .init(
          stops: [
            .init(color: lifted, location: 0),
            .init(color: base, location: 0.45),
            .init(color: grounded, location: 1),
          ]
        ),
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func gleamAccentStyle(
    base: Color
  ) -> AnyShapeStyle {
    gleamSurfaceStyle(
      base: base,
      highlightAmount: colorScheme == .dark ? 0.2 : 0.14,
      shadowAmount: colorScheme == .dark ? 0.12 : 0.08
    )
  }

  private func gleamBorderStyle(
    base: Color,
    highlightAmount: Double? = nil,
    shadowAmount: Double? = nil
  ) -> AnyShapeStyle {
    let lifted = elevatedSurface(
      from: base,
      scheme: colorScheme,
      amount: highlightAmount ?? (colorScheme == .dark ? 0.16 : 0.1)
    )
    let grounded = elevatedSurface(
      from: base,
      scheme: colorScheme,
      amount: shadowAmount ?? (colorScheme == .dark ? 0.08 : 0.05),
      invert: true
    )
    return .linearGradient(
      .init(
        gradient: .init(
          stops: [
            .init(color: lifted, location: 0),
            .init(color: base, location: 0.4),
            .init(color: grounded, location: 1),
          ]
        ),
        startPoint: .top,
        endPoint: .bottom
      )
    )
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
    switch chromePreset {
    case .legacy:
      return appearance.controlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: isSelected,
        prominence: prominence,
        role: role
      )
    case .standard:
      return standardControlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: isSelected,
        prominence: prominence,
        role: role
      )
    }
  }

  package func rowChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    isSelected: Bool = false,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    switch chromePreset {
    case .legacy:
      return appearance.rowChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: isSelected,
        role: role
      )
    case .standard:
      return standardRowChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: isSelected,
        role: role
      )
    }
  }

  package func buttonChrome(
    buttonStyle: ButtonStyle,
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool = false,
    prominence: ControlProminence = .standard,
    role: ButtonRole? = nil
  ) -> ControlChrome {
    switch chromePreset {
    case .legacy:
      return appearance.buttonChrome(
        buttonStyle: buttonStyle,
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        prominence: prominence,
        role: role
      )
    case .standard:
      return standardButtonChrome(
        buttonStyle: buttonStyle,
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        prominence: prominence,
        role: role
      )
    }
  }

  package func groupBoxChrome(
    prominence: ControlProminence = .standard
  ) -> ContainerChrome {
    switch chromePreset {
    case .legacy:
      return appearance.groupBoxChrome(prominence: prominence)
    case .standard:
      return standardGroupBoxChrome(prominence: prominence)
    }
  }

  private func standardControlChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool,
    isSelected: Bool,
    prominence: ControlProminence,
    role: ButtonRole?
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let neutralSurface = AnyShapeStyle(.terminalSurface(.neutral))
    let focusedSurface = AnyShapeStyle(
      prominence == .increased ? .terminalAccent(tone) : .terminalSurface(tone)
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

  private func standardRowChrome(
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool,
    isSelected: Bool,
    role: ButtonRole?
  ) -> ControlChrome {
    let tone = chromeTone(for: role)
    let idleBackground = AnyShapeStyle(.terminalRow(.neutral))
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

  private func standardButtonChrome(
    buttonStyle: ButtonStyle,
    isEnabled: Bool,
    isFocused: Bool,
    isPressed: Bool,
    prominence: ControlProminence,
    role: ButtonRole?
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
      return standardControlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: false,
        prominence: .standard,
        role: role
      )
    case .automatic, .borderedProminent:
      return standardControlChrome(
        isEnabled: isEnabled,
        isFocused: isFocused,
        isPressed: isPressed,
        isSelected: false,
        prominence: .increased,
        role: role
      )
    }
  }

  private func standardGroupBoxChrome(
    prominence: ControlProminence
  ) -> ContainerChrome {
    let tone: TerminalTone = prominence == .increased ? .accent : .neutral
    return .init(
      foregroundStyle: theme.foreground,
      backgroundStyle: AnyShapeStyle(
        prominence == .increased ? .terminalSurface(.accent) : .terminalSurfaceBackground
      ),
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
    guard let backgroundColor = parallelResolveColor(style: style, theme: theme) else {
      return theme.foreground
    }

    let whiteContrast = contrastRatio(.white, backgroundColor)
    let blackContrast = contrastRatio(.black, backgroundColor)
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

func mix(
  _ lhs: Color,
  _ rhs: Color,
  amount: Double
) -> Color {
  let clampedAmount = min(1, max(0, amount))
  return .init(
    red: interpolatedComponent(lhs.red, rhs.red, amount: clampedAmount),
    green: interpolatedComponent(lhs.green, rhs.green, amount: clampedAmount),
    blue: interpolatedComponent(lhs.blue, rhs.blue, amount: clampedAmount)
  )
}

func contrastSafe(
  _ color: Color,
  against background: Color,
  minimumContrast: Double,
  fallback: Color
) -> Color {
  contrastRatio(color, background) >= minimumContrast ? color : fallback
}

func relativeLuminance(_ color: Color) -> Double {
  let red = linearComponent(color.red)
  let green = linearComponent(color.green)
  let blue = linearComponent(color.blue)
  return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
}

func contrastRatio(
  _ lhs: Color,
  _ rhs: Color
) -> Double {
  let lighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
  let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
  return (lighter + 0.05) / (darker + 0.05)
}

private func linearComponent(_ value: Int) -> Double {
  let normalized = Double(value) / 255
  if normalized <= 0.04045 {
    return normalized / 12.92
  }
  return powDouble((normalized + 0.055) / 1.055, 2.4)
}

private func interpolatedComponent(
  _ lhs: Int,
  _ rhs: Int,
  amount: Double
) -> Int {
  Int((Double(lhs) + ((Double(rhs) - Double(lhs)) * amount)).rounded())
}
