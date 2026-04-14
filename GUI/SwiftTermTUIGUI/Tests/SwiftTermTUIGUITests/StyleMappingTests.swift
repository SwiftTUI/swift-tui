import SwiftTerm
import TerminalUI
import Testing

@testable import SwiftTermTUIGUI

@Test
func terminal_style_maps_to_swiftterm_configuration_and_render_style() {
  let palette = SwiftTermTUITerminalPalette(
    foreground: .hex("#112233"),
    background: .hex("#445566"),
    cursor: .hex("#778899"),
    selectionBackground: .hex("#AABBCC"),
    selectionForeground: .hex("#DDEEFF"),
    ansi: .init(
      indexedColors: [
        0: .hex("#000000"),
        1: .hex("#111111"),
        2: .hex("#222222"),
        3: .hex("#333333"),
        4: .hex("#444444"),
        5: .hex("#555555"),
        6: .hex("#666666"),
        7: .hex("#777777"),
        8: .hex("#888888"),
        9: .hex("#999999"),
        10: .hex("#AAAAAA"),
        11: .hex("#BBBBBB"),
        12: .hex("#CCCCCC"),
        13: .hex("#DDDDDD"),
        14: .hex("#EEEEEE"),
        15: .hex("#FFFFFF"),
      ]
    )
  )
  let theme = Theme(
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

  let style = SwiftTermTUITerminalStyle(
    fontSize: 13,
    fontFamily: "Iosevka",
    cursorStyle: .underline,
    cursorBlink: false,
    backgroundOpacity: 0.5,
    palette: palette,
    theme: theme
  )

  let configuration = style.swiftTermConfiguration
  #expect(configuration.fontFamily == "Iosevka")
  #expect(configuration.fontSize == 13)
  #expect(configuration.backgroundOpacity == 0.5)
  #expect(configuration.cursorStyle == .steadyUnderline)
  #expect(configuration.foreground == .hex("#112233"))
  #expect(
    configuration.background
      == .init(red: 68.0 / 255.0, green: 85.0 / 255.0, blue: 102.0 / 255.0, alpha: 0.5))
  #expect(configuration.selectionBackground == .hex("#AABBCC"))
  #expect(configuration.ansiColors.count == 16)
  #expect(configuration.ansiColors[0] == SwiftTerm.Color(red: 0, green: 0, blue: 0))
  #expect(configuration.ansiColors[15] == SwiftTerm.Color(red: 65_535, green: 65_535, blue: 65_535))

  let renderStyle = style.renderStyle
  #expect(renderStyle.theme == theme)
  #expect(renderStyle.appearance.foregroundColor == .hex("#112233"))
  #expect(renderStyle.appearance.backgroundColor == .hex("#445566"))
  #expect(renderStyle.appearance.palette[15] == .hex("#FFFFFF"))
}
