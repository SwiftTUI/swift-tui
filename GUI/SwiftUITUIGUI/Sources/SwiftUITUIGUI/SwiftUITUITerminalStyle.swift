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
    configuration = configuration
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

  func terminalAppearance(
    colorScheme: TerminalUI.ColorScheme
  ) -> TerminalAppearance {
    let foregroundColor = color(from: foreground) ?? .white
    let backgroundColor = color(from: background) ?? .black
    let tintColor = color(from: cursor) ?? foregroundColor

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
        (index, color(from: value) ?? .white)
      }
    )
  }
}

public struct SwiftUITUITerminalStyle: Equatable, Sendable {
  public var fontSize: Float?
  public var fontFamily: String?
  public var cursorStyle: SwiftUITUICursorStyle
  public var cursorBlink: Bool
  public var backgroundOpacity: Float
  public var lightPalette: SwiftUITUITerminalPalette
  public var darkPalette: SwiftUITUITerminalPalette

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftUITUICursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    lightPalette: SwiftUITUITerminalPalette = .defaultLight,
    darkPalette: SwiftUITUITerminalPalette = .defaultDark
  ) {
    self.fontSize = fontSize
    self.fontFamily = fontFamily
    self.cursorStyle = cursorStyle
    self.cursorBlink = cursorBlink
    self.backgroundOpacity = backgroundOpacity
    self.lightPalette = lightPalette
    self.darkPalette = darkPalette
  }

  public static let `default` = Self()

  public var terminalConfiguration: TerminalConfiguration {
    var configuration = TerminalConfiguration()

    if let fontFamily {
      configuration = configuration.fontFamily(fontFamily)
    }
    if let fontSize {
      configuration = configuration.fontSize(fontSize)
    }

    configuration = configuration
      .cursorStyle(cursorStyle.terminalCursorStyle)
      .cursorStyleBlink(cursorBlink)
      .backgroundOpacity(Double(backgroundOpacity))

    return configuration
  }

  public var terminalTheme: TerminalTheme {
    TerminalTheme(
      light: lightPalette.terminalConfiguration(),
      dark: darkPalette.terminalConfiguration()
    )
  }

  func terminalAppearance(
    for colorScheme: TerminalUI.ColorScheme
  ) -> TerminalAppearance {
    switch colorScheme {
    case .light:
      lightPalette.terminalAppearance(colorScheme: .light)
    case .dark:
      darkPalette.terminalAppearance(colorScheme: .dark)
    }
  }
}

private extension SwiftUITUICursorStyle {
  var terminalCursorStyle: TerminalCursorStyle {
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

private func color(
  from hex: String
) -> TerminalUI.Color? {
  let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
  let valueString = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
  guard valueString.count == 6, let value = Int(valueString, radix: 16) else {
    return nil
  }
  return TerminalUI.Color(hex: value)
}
