import SwiftTUI

public enum SwiftUIHostCursorStyle: String, Sendable, Hashable {
  case block
  case bar
  case underline
}

public struct SwiftUIHostTerminalPalette: Equatable, Sendable {
  public var foreground: SwiftTUI.Color
  public var background: SwiftTUI.Color
  public var cursor: SwiftTUI.Color
  public var selectionBackground: SwiftTUI.Color
  public var selectionForeground: SwiftTUI.Color
  public var ansi: TerminalPalette

  public init(
    foreground: SwiftTUI.Color,
    background: SwiftTUI.Color,
    cursor: SwiftTUI.Color,
    selectionBackground: SwiftTUI.Color,
    selectionForeground: SwiftTUI.Color,
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

public struct SwiftUIHostTerminalStyle: Equatable, Sendable {
  public var fontSize: Float?
  public var fontFamily: String?
  public var cursorStyle: SwiftUIHostCursorStyle
  public var cursorBlink: Bool
  public var backgroundOpacity: Float
  public var palette: SwiftUIHostTerminalPalette
  public var theme: Theme

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftUIHostCursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    palette: SwiftUIHostTerminalPalette = .default,
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
