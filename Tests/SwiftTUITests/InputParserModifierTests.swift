import Testing

@testable import Core
@testable import SwiftTUI

@MainActor
@Suite
struct InputParserModifierTests {
  // MARK: - Ctrl+letter

  @Test("Ctrl+A emits character 'a' with control modifier")
  func ctrlA() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x01])
    #expect(events == [.key(KeyPress(.character("a"), modifiers: .ctrl))])
  }

  @Test("Ctrl+S emits character 's' with control modifier")
  func ctrlS() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x13])
    #expect(events == [.key(KeyPress(.character("s"), modifiers: .ctrl))])
  }

  @Test("Ctrl+Z emits character 'z' with control modifier")
  func ctrlZ() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1A])
    #expect(events == [.key(KeyPress(.character("z"), modifiers: .ctrl))])
  }

  @Test("Ctrl+C emits character 'c' with control modifier")
  func ctrlC() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x03])
    #expect(events == [.key(KeyPress(.character("c"), modifiers: .ctrl))])
  }

  @Test("Tab (0x09) emits tab without modifiers")
  func tab() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x09])
    #expect(events == [.key(KeyPress(.tab))])
  }

  @Test("Return (0x0D) emits return without modifiers")
  func `return`() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x0D])
    #expect(events == [.key(KeyPress(.return))])
  }

  // MARK: - Alt+letter

  @Test("Alt+x emits character 'x' with alt modifier")
  func altX() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x78])
    #expect(events == [.key(KeyPress(.character("x"), modifiers: .alt))])
  }

  @Test("Alt+Space emits space with alt modifier")
  func altSpace() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x20])
    #expect(events == [.key(KeyPress(.space, modifiers: .alt))])
  }

  @Test("Alt+punctuation and Alt+digit emit printable keys with alt modifier")
  func altPunctuationAndDigit() {
    var parser = TerminalInputParser()
    let events = parser.feed([
      0x1B, 0x2C,  // Alt+,
      0x1B, 0x2E,  // Alt+.
      0x1B, 0x2D,  // Alt+-
      0x1B, 0x3D,  // Alt+=
      0x1B, 0x30,  // Alt+0
    ])
    #expect(
      events == [
        .key(KeyPress(.character(","), modifiers: .alt)),
        .key(KeyPress(.character("."), modifiers: .alt)),
        .key(KeyPress(.character("-"), modifiers: .alt)),
        .key(KeyPress(.character("="), modifiers: .alt)),
        .key(KeyPress(.character("0"), modifiers: .alt)),
      ]
    )
  }

  // MARK: - CSI modifier sequences

  @Test("Ctrl+Up emits arrowUp with control modifier")
  func ctrlUp() {
    // ESC [ 1 ; 5 A = Ctrl+Up (modifier param 5 = 1 + ctrl bitmask 4)
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x41])
    #expect(events == [.key(KeyPress(.arrowUp, modifiers: .ctrl))])
  }

  @Test("Shift+Down emits arrowDown with shift modifier")
  func shiftDown() {
    // ESC [ 1 ; 2 B = Shift+Down (modifier param 2 = 1 + shift bitmask 1)
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x3B, 0x32, 0x42])
    #expect(events == [.key(KeyPress(.arrowDown, modifiers: .shift))])
  }

  @Test("Alt+Right emits arrowRight with alt modifier")
  func altRight() {
    // ESC [ 1 ; 3 C = Alt+Right (modifier param 3 = 1 + alt bitmask 2)
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x43])
    #expect(events == [.key(KeyPress(.arrowRight, modifiers: .alt))])
  }

  @Test("Ctrl+Shift+Left emits arrowLeft with control and shift modifiers")
  func ctrlShiftLeft() {
    // ESC [ 1 ; 6 D = Ctrl+Shift+Left (modifier param 6 = 1 + ctrl 4 + shift 1)
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x3B, 0x36, 0x44])
    #expect(events == [.key(KeyPress(.arrowLeft, modifiers: [.ctrl, .shift]))])
  }

  // MARK: - Shift+Tab

  @Test("Shift+Tab emits tab with shift modifier")
  func shiftTab() {
    // ESC [ Z = Shift+Tab
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x5A])
    #expect(events == [.key(KeyPress(.tab, modifiers: .shift))])
  }

  @Test("Home and End preserve their own key identities")
  func homeAndEnd() {
    var parser = TerminalInputParser()

    let homeEvents = parser.feed([0x1B, 0x5B, 0x48])
    let endEvents = parser.feed([0x1B, 0x5B, 0x46])

    #expect(homeEvents == [.key(KeyPress(.home))])
    #expect(endEvents == [.key(KeyPress(.end))])
  }

  // MARK: - Unmodified keys

  @Test("plain character emits without modifiers")
  func plainCharacter() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x71])  // 'q'
    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("arrow keys without modifiers")
  func plainArrows() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x41])
    #expect(events == [.key(KeyPress(.arrowUp))])
  }

  // MARK: - InputEvent convenience

  @Test("InputEvent.key convenience creates KeyPress without modifiers")
  func inputEventConvenience() {
    let event = InputEvent.key(.character("q"))
    #expect(event == .key(KeyPress(.character("q"))))
  }

  @Test("SGR 1006 mouse parser emits centered cell fallback")
  func sgrMouseParserEmitsCenteredCellFallback() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x35, 0x3B, 0x37, 0x4D])

    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .down(.primary),
            location: .cellFallback(CellPoint(x: 4, y: 6))
          )
        )
      ])

    guard case .mouse(let event)? = events.first else {
      Issue.record("expected mouse event")
      return
    }

    #expect(event.location.cell == CellPoint(x: 4, y: 6))
    #expect(event.location.location == Point(x: 4.5, y: 6.5))
    #expect(event.location.precision == .cell)
    #expect(event.location.rawPixel == nil)
  }

  @Test("SGR pixel-mode mouse parser emits terminal-pixel pointer locations")
  func sgrPixelModeMouseParserEmitsTerminalPixelLocations() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )

    let events = parser.feed(Array("\u{001B}[<0;17;33M".utf8))

    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .down(.primary),
            location: .subCell(
              location: Point(x: 2.0, y: 2.0),
              source: .terminalPixels,
              metrics: metrics,
              rawPixel: PixelPoint(x: 16, y: 32)
            )
          )
        )
      ])
  }

  @Test("SGR pixel-mode mouse parser preserves zero and negative coordinates")
  func sgrPixelModeMouseParserPreservesZeroAndNegativeCoordinates() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )

    let events = parser.feed(Array("\u{001B}[<32;0;-7M".utf8))

    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .dragged(.primary),
            location: .subCell(
              location: Point(x: -0.125, y: -0.5),
              source: .terminalPixels,
              metrics: metrics,
              rawPixel: PixelPoint(x: -1, y: -8)
            )
          )
        )
      ])
  }

  @Test("SGR pixel-mode wheel events preserve pointer precision metadata")
  func sgrPixelModeWheelEventsPreservePointerPrecisionMetadata() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    var parser = TerminalInputParser(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )

    let events = parser.feed(Array("\u{001B}[<64;17;33M".utf8))

    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .scrolled(deltaX: 0, deltaY: -1),
            location: .subCell(
              location: Point(x: 2.0, y: 2.0),
              source: .terminalPixels,
              metrics: metrics,
              rawPixel: PixelPoint(x: 16, y: 32)
            )
          )
        )
      ])
  }
}
