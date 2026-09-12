import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct DirectionalCommandRuntimeTests {
  @Test("an ignored exit command permits the enclosing sheet to dismiss")
  func ignoredExitDismissesSheet() throws {
    let log = CommandRouteLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SheetExitCommand"), size: .init(width: 40, height: 12)
    ) { CommandSheetFixture(log: log) }
    defer { harness.shutdown() }
    _ = try harness.clickText("Open sheet")
    _ = try harness.clickText("Sheet target")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(log.exits == ["sheet"])
    #expect(!harness.frame.contains("Sheet target"))
  }

  @Test("move commands bubble only after the focused handler declines")
  func directionalRouting() throws {
    let log = CommandRouteLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DirectionalCommands"), size: .init(width: 40, height: 12)
    ) { CommandRouteFixture(log: log) }
    defer { harness.shutdown() }
    _ = try harness.clickText("First target")
    for key in [KeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight] {
      _ = try harness.pressKey(KeyPress(key))
    }
    #expect(log.moves == [.up, .down, .left, .right])
    #expect(log.parentMoves == [.up])
    #expect(log.siblingMoves.isEmpty)
    _ = try harness.pressKey(KeyPress(.arrowUp, modifiers: .shift))
    #expect(log.moves.count == 4)
  }

  @Test("exit handling stays on the focused chain and propagates ignored Escape")
  func exitRouting() throws {
    let log = CommandRouteLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ExitCommands"), size: .init(width: 40, height: 12)
    ) { CommandRouteFixture(log: log) }
    defer { harness.shutdown() }
    _ = try harness.clickText("First target")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(log.exits == ["first", "parent"])
    _ = try harness.clickText("Second target")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(log.exits == ["first", "parent", "second"])
    _ = try harness.pressKey(KeyPress(.escape, modifiers: .shift))
    #expect(log.exits.count == 3)
  }
}

private struct CommandSheetFixture: View {
  let log: CommandRouteLog
  @State private var presented = false
  var body: some View {
    Button("Open sheet") { presented = true }
      .sheet(isPresented: $presented) {
        Text("Sheet target").focusable()
          .onExitCommand {
            log.exits.append("sheet")
            return .ignored
          }
      }
  }
}

@MainActor
private final class CommandRouteLog {
  var moves: [MoveCommandDirection] = []
  var parentMoves: [MoveCommandDirection] = []
  var siblingMoves: [MoveCommandDirection] = []
  var exits: [String] = []
}

private struct CommandRouteFixture: View {
  let log: CommandRouteLog
  var body: some View {
    VStack {
      VStack {
        Text("First target").focusable()
          .onMoveCommand { direction in
            log.moves.append(direction)
            return direction == .up ? .ignored : .handled
          }
          .onExitCommand {
            log.exits.append("first")
            return .ignored
          }
      }
      .onMoveCommand { direction in
        log.parentMoves.append(direction)
        return .handled
      }
      .onExitCommand {
        log.exits.append("parent")
        return .handled
      }
      VStack {
        Text("Second target").focusable()
          .onMoveCommand { direction in
            log.siblingMoves.append(direction)
            return .handled
          }
          .onExitCommand {
            log.exits.append("second")
            return .handled
          }
      }
    }
  }
}
