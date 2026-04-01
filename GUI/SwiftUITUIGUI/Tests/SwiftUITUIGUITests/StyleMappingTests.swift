import Testing

@testable import SwiftUITUIGUI

@Test
func terminal_style_maps_to_ghostty_configuration_and_theme_variants() {
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
  let lightTheme = ThemeColors(
    foreground: .hex("#102030"),
    background: .hex("#203040"),
    tint: .hex("#304050"),
    separator: .hex("#405060"),
    selection: .hex("#506070"),
    placeholder: .hex("#607080"),
    link: .hex("#708090"),
    fill: .hex("#8090A0"),
    windowBackground: .hex("#90A0B0"),
    success: .hex("#A0B0C0"),
    warning: .hex("#B0C0D0"),
    danger: .hex("#C0D0E0"),
    info: .hex("#D0E0F0"),
    muted: .hex("#E0F0FF")
  )
  let darkTheme = ThemeColors(
    foreground: .hex("#F0E0D0"),
    background: .hex("#E0D0C0"),
    tint: .hex("#D0C0B0"),
    separator: .hex("#C0B0A0"),
    selection: .hex("#B0A090"),
    placeholder: .hex("#A09080"),
    link: .hex("#908070"),
    fill: .hex("#807060"),
    windowBackground: .hex("#706050"),
    success: .hex("#605040"),
    warning: .hex("#504030"),
    danger: .hex("#403020"),
    info: .hex("#302010"),
    muted: .hex("#201000")
  )

  let style = SwiftUITUITerminalStyle(
    fontSize: 13,
    fontFamily: "Iosevka",
    cursorStyle: .underline,
    cursorBlink: false,
    backgroundOpacity: 0.5,
    lightVariant: .init(
      palette: palette,
      theme: lightTheme
    ),
    darkVariant: .init(
      palette: palette,
      theme: darkTheme
    )
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

  let lightRenderStyle = style.renderStyle(for: .light)
  #expect(lightRenderStyle.appearance.colorScheme == .light)
  #expect(lightRenderStyle.theme == lightTheme)
  #expect(lightRenderStyle.appearance.foregroundColor == .hex("#112233"))
  #expect(lightRenderStyle.appearance.backgroundColor == .hex("#445566"))

  let darkRenderStyle = style.renderStyle(for: .dark)
  #expect(darkRenderStyle.appearance.colorScheme == .dark)
  #expect(darkRenderStyle.theme == darkTheme)
  #expect(darkRenderStyle.appearance.foregroundColor == .hex("#112233"))
  #expect(darkRenderStyle.appearance.backgroundColor == .hex("#445566"))
}
