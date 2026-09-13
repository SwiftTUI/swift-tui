import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

/// The default palette's twelve-row window through the fixture path: the
/// selected row stays inside the window at every index while moving down
/// through twenty commands and back up, and the window never shows more
/// than twelve rows.
@MainActor
struct DefaultPaletteVisibleWindowTests {
  @Test("the twelve-row window keeps the selection visible moving down and back up")
  func selectionStaysVisibleInBothDirections() throws {
    let names = (0..<20).map { "Command \($0 < 10 ? "0" : "")\($0)" }
    let commands = names.enumerated().map { pair in
      PaletteStyleConfiguration.Command(id: pair.offset, name: pair.element)
    }
    let configuration = PaletteStyleConfiguration(
      title: "Commands", commands: commands, terminalSize: .init(width: 60, height: 30),
      controlProminence: .standard, styleEnvironment: .init())
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteWindowFixture"), size: .init(width: 60, height: 30)
    ) { DefaultPaletteStyle().makeBody(configuration: configuration) }
    defer { harness.shutdown() }
    func visibleNames() -> [String] { names.filter { harness.frame.contains($0) } }

    #expect(visibleNames() == Array(names[0..<12]))
    #expect(harness.frame.contains("> Command 00"))
    for index in 1..<20 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      #expect(harness.frame.contains("> \(names[index])"), "index \(index):\n\(harness.frame)")
      #expect(visibleNames().count == 12, "index \(index):\n\(harness.frame)")
    }
    #expect(visibleNames() == Array(names[8..<20]))
    for index in (0..<19).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      #expect(harness.frame.contains("> \(names[index])"), "index \(index):\n\(harness.frame)")
      #expect(visibleNames().count == 12, "index \(index):\n\(harness.frame)")
      let start = min(index, 8)
      #expect(visibleNames() == Array(names[start..<(start + 12)]))
    }
    #expect(visibleNames() == Array(names[0..<12]))
  }
}
