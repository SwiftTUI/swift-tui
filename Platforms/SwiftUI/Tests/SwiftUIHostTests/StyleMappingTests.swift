import SwiftTUI
import Testing

@testable import SwiftUIHost

@Test
func terminal_style_maps_to_native_render_style() {
  let palette = SwiftUIHostTerminalPalette(
    foreground: try! .hex("#112233"),
    background: try! .hex("#445566"),
    cursor: try! .hex("#778899"),
    selectionBackground: try! .hex("#AABBCC"),
    selectionForeground: try! .hex("#DDEEFF"),
    ansi: .init(
      indexedColors: [
        0: try! .hex("#000000"),
        1: try! .hex("#111111"),
        2: try! .hex("#222222"),
        3: try! .hex("#333333"),
        4: try! .hex("#444444"),
        5: try! .hex("#555555"),
        6: try! .hex("#666666"),
        7: try! .hex("#777777"),
        8: try! .hex("#888888"),
        9: try! .hex("#999999"),
        10: try! .hex("#AAAAAA"),
        11: try! .hex("#BBBBBB"),
        12: try! .hex("#CCCCCC"),
        13: try! .hex("#DDDDDD"),
        14: try! .hex("#EEEEEE"),
        15: try! .hex("#FFFFFF"),
      ]
    )
  )
  let theme = Theme(
    foreground: try! .hex("#102030"),
    background: try! .hex("#203040"),
    tint: try! .hex("#304050"),
    separator: try! .hex("#405060"),
    selection: try! .hex("#506070"),
    placeholder: try! .hex("#607080"),
    link: try! .hex("#708090"),
    fill: try! .hex("#8090A0"),
    windowBackground: try! .hex("#90A0B0"),
    success: try! .hex("#A0B0C0"),
    warning: try! .hex("#B0C0D0"),
    danger: try! .hex("#C0D0E0"),
    info: try! .hex("#D0E0F0"),
    muted: try! .hex("#E0F0FF")
  )

  let style = SwiftUIHostTerminalStyle(
    fontSize: 13,
    fontFamily: "Iosevka",
    cursorStyle: .underline,
    cursorBlink: false,
    backgroundOpacity: 0.5,
    palette: palette,
    theme: theme
  )

  #expect(style.fontFamily == "Iosevka")
  #expect(style.fontSize == 13)
  #expect(style.cursorStyle == .underline)
  #expect(style.cursorBlink == false)
  #expect(style.backgroundOpacity == 0.5)
  #expect(style.palette.selectionBackground == (try! .hex("#AABBCC")))
  #expect(style.palette.selectionForeground == (try! .hex("#DDEEFF")))

  let renderStyle = style.renderStyle
  #expect(renderStyle.theme == theme)
  #expect(renderStyle.appearance.foregroundColor == (try! .hex("#112233")))
  #expect(renderStyle.appearance.backgroundColor == (try! .hex("#445566")))
  #expect(renderStyle.appearance.palette[15] == (try! .hex("#FFFFFF")))
}
