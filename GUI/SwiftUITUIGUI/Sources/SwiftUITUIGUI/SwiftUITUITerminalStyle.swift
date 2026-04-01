import GhosttyTerminal
import SwiftUI
import TerminalUI

public enum SwiftUITUICursorStyle: String, Sendable, Hashable {
  case block
  case bar
  case underline
}

public struct SwiftUITUITerminalPalette: Equatable, Sendable {
  public var foreground: String
  public var background: String
  public var cursor: String
  public var selectionBackground: String
  public var selectionForeground: String
  public var ansiColors: [String]

  public init(
    foreground: String,
    background: String,
    cursor: String,
    selectionBackground: String,
    selectionForeground: String,
    ansiColors: [String]
  ) {
    self.foreground = foreground
    self.background = background
    self.cursor = cursor
    self.selectionBackground = selectionBackground
    self.selectionForeground = selectionForeground
    self.ansiColors = ansiColors
  }

  static let defaultANSIColors: [String] = [
    "#20242C",
    "#E05757",
    "#61C67B",
    "#EBB33C",
    "#5BA3FF",
    "#B46EFF",
    "#56B6C2",
    "#ECEFF4",
    "#8C92AC",
    "#FF7B72",
    "#7EE787",
    "#F2CC60",
    "#79C0FF",
    "#D2A8FF",
    "#7DE2D1",
    "#FFFFFF",
  ]

  public static let defaultLight = Self(
    foreground: "#161A20",
    background: "#F6F7F9",
    cursor: "#1976D2",
    selectionBackground: "#D7DCE3",
    selectionForeground: "#161A20",
    ansiColors: defaultANSIColors
  )

  public static let defaultDark = Self(
    foreground: "#ECEFF4",
    background: "#1E222A",
    cursor: "#56B6C2",
    selectionBackground: "#2E3440",
    selectionForeground: "#ECEFF4",
    ansiColors: defaultANSIColors
  )

  fileprivate func terminalConfiguration() -> TerminalConfiguration {
    var configuration = TerminalConfiguration()
    configuration =
      configuration
      .background(background)
      .foreground(foreground)
      .cursorColor(cursor)
      .selectionBackground(selectionBackground)
      .selectionForeground(selectionForeground)

    for (index, color) in normalizedANSIColors.enumerated() {
      configuration = configuration.palette(index, color: color)
    }

    return configuration
  }

  fileprivate func terminalAppearance(
    colorScheme: TerminalUI.ColorScheme
  ) -> TerminalAppearance {
    let foregroundColor = (try? TerminalUI.Color(hex: foreground)) ?? .white
    let backgroundColor = (try? TerminalUI.Color(hex: background)) ?? .black
    let tintColor = (try? TerminalUI.Color(hex: cursor)) ?? foregroundColor

    return TerminalAppearance(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      tintColor: tintColor,
      palette: paletteDictionary,
      colorScheme: colorScheme,
      source: .override
    )
  }

  private var normalizedANSIColors: [String] {
    if ansiColors.isEmpty {
      return Self.defaultANSIColors
    }

    if ansiColors.count >= Self.defaultANSIColors.count {
      return Array(ansiColors.prefix(Self.defaultANSIColors.count))
    }

    return ansiColors + Self.defaultANSIColors.dropFirst(ansiColors.count)
  }

  private var paletteDictionary: [Int: TerminalUI.Color] {
    Dictionary(
      uniqueKeysWithValues: normalizedANSIColors.enumerated().map { index, value in
        (index, (try? TerminalUI.Color(hex: value)) ?? .white)
      }
    )
  }
}

public struct SwiftUITUITerminalThemeVariant: Equatable, Sendable {
  public var palette: SwiftUITUITerminalPalette
  public var theme: ThemeColors

  public init(
    palette: SwiftUITUITerminalPalette,
    theme: ThemeColors
  ) {
    self.palette = palette
    self.theme = theme
  }

  public static let defaultLight = Self(
    palette: SwiftUITUITerminalPalette.defaultLight,
    theme: .init(
      appearance: SwiftUITUITerminalPalette.defaultLight.terminalAppearance(
        colorScheme: TerminalUI.ColorScheme.light
      )
    )
  )

  public static let defaultDark = Self(
    palette: SwiftUITUITerminalPalette.defaultDark,
    theme: .init(
      appearance: SwiftUITUITerminalPalette.defaultDark.terminalAppearance(
        colorScheme: TerminalUI.ColorScheme.dark
      )
    )
  )

  fileprivate func terminalConfiguration() -> TerminalConfiguration {
    palette.terminalConfiguration()
  }

  fileprivate func terminalAppearance(
    colorScheme: TerminalUI.ColorScheme
  ) -> TerminalAppearance {
    palette.terminalAppearance(colorScheme: colorScheme)
  }

  fileprivate func renderStyle(
    colorScheme: TerminalUI.ColorScheme
  ) -> TerminalRenderStyle {
    .init(
      appearance: terminalAppearance(colorScheme: colorScheme),
      theme: theme
    )
  }
}

public struct SwiftUITUITerminalStyle: Equatable, Sendable {
  public var fontSize: Float?
  public var fontFamily: String?
  public var cursorStyle: SwiftUITUICursorStyle
  public var cursorBlink: Bool
  public var backgroundOpacity: Float
  public var lightVariant: SwiftUITUITerminalThemeVariant
  public var darkVariant: SwiftUITUITerminalThemeVariant

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftUITUICursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    lightVariant: SwiftUITUITerminalThemeVariant = .defaultLight,
    darkVariant: SwiftUITUITerminalThemeVariant = .defaultDark
  ) {
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.cursorStyle = cursorStyle
    self.cursorBlink = cursorBlink
    self.backgroundOpacity = backgroundOpacity
    self.lightVariant = lightVariant
    self.darkVariant = darkVariant
  }

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftUITUICursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    lightPalette: SwiftUITUITerminalPalette = .defaultLight,
    darkPalette: SwiftUITUITerminalPalette = .defaultDark
  ) {
    self.init(
      fontSize: fontSize,
      fontFamily: fontFamily,
      cursorStyle: cursorStyle,
      cursorBlink: cursorBlink,
      backgroundOpacity: backgroundOpacity,
      lightVariant: .init(
        palette: lightPalette,
        theme: .init(appearance: lightPalette.terminalAppearance(colorScheme: .light))
      ),
      darkVariant: .init(
        palette: darkPalette,
        theme: .init(appearance: darkPalette.terminalAppearance(colorScheme: .dark))
      )
    )
  }

  public static let `default` = Self(
    fontSize: nil,
    fontFamily: nil,
    cursorStyle: .block,
    cursorBlink: true,
    backgroundOpacity: 1,
    lightVariant: SwiftUITUITerminalThemeVariant.defaultLight,
    darkVariant: SwiftUITUITerminalThemeVariant.defaultDark
  )

  public var terminalConfiguration: TerminalConfiguration {
    var configuration = TerminalConfiguration()

    if let fontFamily {
      configuration = configuration.fontFamily(fontFamily)
    }
    if let fontSize {
      configuration = configuration.fontSize(fontSize)
    }

    configuration =
      configuration
      .cursorStyle(cursorStyle.terminalCursorStyle)
      .cursorStyleBlink(cursorBlink)
      .backgroundOpacity(Double(backgroundOpacity))

    return configuration
  }

  public var terminalTheme: TerminalTheme {
    TerminalTheme(
      light: lightVariant.terminalConfiguration(),
      dark: darkVariant.terminalConfiguration()
    )
  }

  public func renderStyle(
    for colorScheme: TerminalUI.ColorScheme
  ) -> TerminalRenderStyle {
    variant(for: colorScheme).renderStyle(colorScheme: colorScheme)
  }

  public func terminalAppearance(
    for colorScheme: TerminalUI.ColorScheme
  ) -> TerminalAppearance {
    renderStyle(for: colorScheme).appearance
  }

  public func theme(
    for colorScheme: TerminalUI.ColorScheme
  ) -> ThemeColors {
    variant(for: colorScheme).theme
  }

  fileprivate func variant(
    for colorScheme: TerminalUI.ColorScheme
  ) -> SwiftUITUITerminalThemeVariant {
    switch colorScheme {
    case .light:
      lightVariant
    case .dark:
      darkVariant
    }
  }
}

extension ThemeColors {
  public init(
    appearance: TerminalAppearance
  ) {
    self.init(theme: appearance.semanticTheme())
  }

  public init(
    theme: Theme
  ) {
    self.init(
      foreground: resolvedColor(
        theme.style(for: .foreground),
        theme: theme,
        fallback: TerminalUI.Color.hex("#ECEFF4")
      ),
      background: resolvedColor(
        theme.style(for: .background),
        theme: theme,
        fallback: TerminalUI.Color.hex("#1E222A")
      ),
      tint: resolvedColor(
        theme.style(for: .tint),
        theme: theme,
        fallback: TerminalUI.Color.cyan
      ),
      separator: resolvedColor(
        theme.style(for: .separator),
        theme: theme,
        fallback: TerminalUI.Color.hex("#4C566A")
      ),
      selection: resolvedColor(
        theme.style(for: .selection),
        theme: theme,
        fallback: TerminalUI.Color.hex("#2E3440")
      ),
      placeholder: resolvedColor(
        theme.style(for: .placeholder),
        theme: theme,
        fallback: TerminalUI.Color.gray
      ),
      link: resolvedColor(
        theme.style(for: .link),
        theme: theme,
        fallback: TerminalUI.Color.blue
      ),
      fill: resolvedColor(
        theme.style(for: .fill),
        theme: theme,
        fallback: TerminalUI.Color.hex("#2B303B")
      ),
      windowBackground: resolvedColor(
        theme.style(for: .windowBackground),
        theme: theme,
        fallback: TerminalUI.Color.hex("#15181E")
      ),
      success: resolvedColor(
        theme.style(for: .success),
        theme: theme,
        fallback: TerminalUI.Color.green
      ),
      warning: resolvedColor(
        theme.style(for: .warning),
        theme: theme,
        fallback: TerminalUI.Color.yellow
      ),
      danger: resolvedColor(
        theme.style(for: .danger),
        theme: theme,
        fallback: TerminalUI.Color.red
      ),
      info: resolvedColor(
        theme.style(for: .info),
        theme: theme,
        fallback: TerminalUI.Color.cyan
      ),
      muted: resolvedColor(
        theme.style(for: .muted),
        theme: theme,
        fallback: TerminalUI.Color.gray
      )
    )
  }
}

private func resolvedColor(
  _ style: TerminalUI.AnyShapeStyle,
  theme: Theme,
  fallback: TerminalUI.Color
) -> TerminalUI.Color {
  switch resolveStyleColorResult(style: style, theme: theme) {
  case .success(let color):
    return color
  case .failure:
    return fallback
  }
}

extension SwiftUITUICursorStyle {
  fileprivate var terminalCursorStyle: TerminalCursorStyle {
    switch self {
    case .block:
      return .block
    case .bar:
      return .bar
    case .underline:
      return .underline
    }
  }
}
