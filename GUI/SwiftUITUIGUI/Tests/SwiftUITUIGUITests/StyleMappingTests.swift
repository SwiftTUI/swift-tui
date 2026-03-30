import Testing
@testable import SwiftUITUIGUI

@Test
func terminal_style_maps_to_ghostty_configuration() {
  let palette = SwiftUITUITerminalPalette(
    foreground: "#112233",
    background: "#445566",
    cursor: "#778899",
    selectionBackground: "#AABBCC",
    selectionForeground: "#DDEEFF",
    ansiColors: [
      "#000000",
      "#111111",
      "#222222",
      "#333333",
      "#444444",
      "#555555",
      "#666666",
      "#777777",
      "#888888",
      "#999999",
      "#AAAAAA",
      "#BBBBBB",
      "#CCCCCC",
      "#DDDDDD",
      "#EEEEEE",
      "#FFFFFF",
    ]
  )

  let style = SwiftUITUITerminalStyle(
    fontSize: 13,
    fontFamily: "Iosevka",
    cursorStyle: .underline,
    cursorBlink: false,
    backgroundOpacity: 0.5,
    lightPalette: palette,
    darkPalette: palette
  )

  let configuration = style.terminalConfiguration
  let renderedConfiguration = configuration.rendered
  #expect(renderedConfiguration.contains("font-family = Iosevka"))
  #expect(renderedConfiguration.contains("font-size = 13"))
  #expect(renderedConfiguration.contains("cursor-style = underline"))
  #expect(renderedConfiguration.contains("cursor-style-blink = false"))
  #expect(renderedConfiguration.contains("background-opacity = 0.5"))

  let theme = style.terminalTheme
  #expect(theme.light.rendered.contains("background = #445566"))
  #expect(theme.light.rendered.contains("foreground = #112233"))
  #expect(theme.light.rendered.contains("palette = 15=#FFFFFF"))
}
