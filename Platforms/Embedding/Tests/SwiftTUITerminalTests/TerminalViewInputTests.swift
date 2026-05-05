import SwiftTUICore
import Testing

@testable import SwiftTUITerminal

@Suite("TerminalView input")
struct TerminalViewInputTests {
  @Test("maps focused character key presses to emulator keys")
  func mapsCharacterKeyPresses() {
    #expect(
      TerminalEmulatorKey(keyPress: KeyPress(.character("a")))
        == TerminalEmulatorKey(code: .character("a"))
    )
    #expect(
      TerminalEmulatorKey(
        keyPress: KeyPress(
          .character("z"),
          modifiers: [.ctrl, .alt, .shift]
        )
      )
        == TerminalEmulatorKey(
          code: .character("z"),
          modifiers: [.control, .option, .shift]
        )
    )
  }

  @Test("maps focused navigation key presses to emulator keys")
  func mapsNavigationKeyPresses() {
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.return))?.code == .enter)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.space))?.code == .character(" "))
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.tab))?.code == .tab)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.escape))?.code == .escape)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.backspace))?.code == .backspace)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowUp))?.code == .arrowUp)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowDown))?.code == .arrowDown)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowLeft))?.code == .arrowLeft)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowRight))?.code == .arrowRight)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.home))?.code == .home)
    #expect(TerminalEmulatorKey(keyPress: KeyPress(.end))?.code == .end)
  }
}
