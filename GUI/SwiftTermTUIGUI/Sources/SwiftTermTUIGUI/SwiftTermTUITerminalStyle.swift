import SwiftTerm
import TerminalUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  typealias NativeColor = NSColor
  typealias NativeFont = NSFont
#elseif canImport(UIKit)
  import UIKit
  typealias NativeColor = UIColor
  typealias NativeFont = UIFont
#endif

public enum SwiftTermTUICursorStyle: String, Sendable, Hashable {
  case block
  case bar
  case underline
}

public struct SwiftTermTUITerminalPalette: Equatable, Sendable {
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

struct SwiftTermStyleConfiguration {
  let fontFamily: String?
  let fontSize: Float?
  let backgroundOpacity: Double
  let cursorStyle: CursorStyle
  let foreground: TerminalUI.Color
  let background: TerminalUI.Color
  let caret: TerminalUI.Color
  let caretText: TerminalUI.Color
  let selectionBackground: TerminalUI.Color
  let ansiColors: [SwiftTerm.Color]
}

public struct SwiftTermTUITerminalStyle: Equatable, Sendable {
  public var fontSize: Float?
  public var fontFamily: String?
  public var cursorStyle: SwiftTermTUICursorStyle
  public var cursorBlink: Bool
  public var backgroundOpacity: Float
  public var palette: SwiftTermTUITerminalPalette
  public var theme: Theme

  public init(
    fontSize: Float? = nil,
    fontFamily: String? = nil,
    cursorStyle: SwiftTermTUICursorStyle = .block,
    cursorBlink: Bool = true,
    backgroundOpacity: Float = 1,
    palette: SwiftTermTUITerminalPalette = .default,
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

  var swiftTermConfiguration: SwiftTermStyleConfiguration {
    let opacity = max(0, min(1, Double(backgroundOpacity)))
    let effectiveBackground = palette.background.withAlpha(palette.background.alpha * opacity)

    return SwiftTermStyleConfiguration(
      fontFamily: fontFamily,
      fontSize: fontSize,
      backgroundOpacity: opacity,
      cursorStyle: cursorStyle.swiftTermCursorStyle(blinking: cursorBlink),
      foreground: palette.foreground,
      background: effectiveBackground,
      caret: palette.cursor,
      caretText: palette.selectionForeground,
      selectionBackground: palette.selectionBackground,
      ansiColors: (0..<16).compactMap { index in
        palette.ansi[index]?.swiftTermColor
      }
    )
  }

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

extension SwiftTermTUITerminalStyle {
  var nativeFont: NativeFont {
    let resolvedSize = CGFloat(fontSize ?? defaultFontSize)

    if let fontFamily,
      let font = NativeFont(name: fontFamily, size: resolvedSize)
    {
      return font
    }

    return defaultMonospacedFont(size: resolvedSize)
  }
}

extension SwiftTermTUICursorStyle {
  fileprivate func swiftTermCursorStyle(
    blinking: Bool
  ) -> CursorStyle {
    switch (self, blinking) {
    case (.block, true):
      .blinkBlock
    case (.block, false):
      .steadyBlock
    case (.bar, true):
      .blinkBar
    case (.bar, false):
      .steadyBar
    case (.underline, true):
      .blinkUnderline
    case (.underline, false):
      .steadyUnderline
    }
  }
}

extension TerminalUI.Color {
  var swiftTermColor: SwiftTerm.Color {
    SwiftTerm.Color(
      red: UInt16((red * 65_535).rounded()),
      green: UInt16((green * 65_535).rounded()),
      blue: UInt16((blue * 65_535).rounded())
    )
  }

  var nativeColor: NativeColor {
    NativeColor(
      red: CGFloat(red),
      green: CGFloat(green),
      blue: CGFloat(blue),
      alpha: CGFloat(alpha)
    )
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  private let defaultFontSize = Float(NSFont.systemFontSize)

  private func defaultMonospacedFont(
    size: CGFloat
  ) -> NativeFont {
    NativeFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }
#elseif canImport(UIKit)
  private let defaultFontSize = Float(UIFont.systemFontSize)

  private func defaultMonospacedFont(
    size: CGFloat
  ) -> NativeFont {
    NativeFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }
#endif
