import SwiftTUI
import Testing

@testable import SwiftTUITerminal

@Suite("TerminalEmulator wrapper")
struct EmulatorWrapperTests {
  @Test("emulator initializes at requested size")
  func initSize() async {
    let emulator = TerminalEmulator(size: CellSize(width: 80, height: 24))
    let snapshot = await emulator.snapshot()
    #expect(snapshot.size == CellSize(width: 80, height: 24))
  }

  @Test("feeding plain ASCII produces visible cells")
  func feedAscii() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    _ = await emulator.feed(Array("hello".utf8))
    let snapshot = await emulator.snapshot()
    let firstRow = snapshot.cells[0].prefix(5).map { $0.character }
    #expect(firstRow == ["h", "e", "l", "l", "o"])
  }

  @Test("OSC 0 title changes are reported as events")
  func titleEvent() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    let oscTitle = Array("\u{1B}]0;hello-world\u{07}".utf8)
    let events = await emulator.feed(oscTitle)
    #expect(events.contains(.titleChanged("hello-world")))
  }

  @Test("plain ASCII has nil style")
  func plainCharStyle() async {
    let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
    _ = await emulator.feed(Array("x".utf8))
    let cell = (await emulator.snapshot()).cells[0][0]
    #expect(cell.character == "x")
    #expect(cell.style == nil)
  }

  @Test("SGR red foreground produces a red cell")
  func sgrRedForeground() async {
    let emulator = TerminalEmulator(size: CellSize(width: 5, height: 1))
    _ = await emulator.feed(Array("\u{1B}[31mx\u{1B}[0m".utf8))
    let cell = (await emulator.snapshot()).cells[0][0]
    #expect(cell.style?.foregroundColor == .red)
  }
}
