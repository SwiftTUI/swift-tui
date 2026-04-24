import TerminalUI

public enum SwiftUITUICursorStyle: String, Sendable, Hashable {
  case block
  case bar
  case underline
}

public struct SwiftUITUITerminalPalette: Equatable, Sendable {
  public var foreground: TerminalUI.Color
  public var background: TerminalUI.Color
  public var cursor: TerminalUI.Color
  public var selectionBackground: TerminalUI.Color
  public var selectionForeground: TerminalUI.Color
  public var ansi: TerminalPalette

  public init(
    foreground: TerminalUI.Color,
    background: TerminalUI.Color,
    cursor: TerminalUI.Color,
    selectionBackground: TerminalUI.Color,
    selectionForeground: TerminalUI.Color,
    ansi: TerminalPalette = .default
  ) {
    self.foreground = foreground
    self.background = background
    self.cursor = cursor
    self.selectionBackground = selectionBackground
    self.selectionForeground = selectionForeground
    self.ansi = ansi
  }

  public static let `default` = Self(
    foreground: .hex("#ECEFF4"),
    background: .hex("#1E222A"),
    cursor: .hex("#56B6C2"),
    selectionBackground: .hex("#2E3440"),
    selectionForeground: .hex("#ECEFF4"),
    ansi: .default
  )

  fileprivate var terminalAppearance: TerminalAppearance {
    TerminalAppearance(
      foregroundColor: foreground,
      backgroundColor: background,
      tintColor: cursor,
      palette: ansi,
      source: .override
    )
  }
}

public struct SwiftUITUITerminalStyle: Equatable, Sendable {
  public var fontSize: Float?
  public var fontFamily: String?
  public var cursorStyle: SwiftUITUICursorStyle
  public var cursorBlink: Bool
  public var backgroundOpacity: Float
  public var palette: SwiftUITUITerminalPalette
  public var theme: Theme

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftUITUICursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    palette: SwiftUITUITerminalPalette = .default,
    theme: Theme? = nil
  ) {
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.cursorStyle = cursorStyle
    self.cursorBlink = cursorBlink
    self.backgroundOpacity = backgroundOpacity
    self.palette = palette
    self.theme = theme ?? palette.terminalAppearance.synthesizedTheme()
  }

  public static let `default` = Self()

  public var renderStyle: TerminalRenderStyle {
    .init(
      appearance: palette.terminalAppearance,
      theme: theme
    )
  }

  public var terminalAppearance: TerminalAppearance {
    renderStyle.appearance
  }
}
