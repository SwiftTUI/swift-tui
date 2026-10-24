#if canImport(Darwin) || canImport(Glibc) || canImport(Android)
  import Foundation
  import Synchronization
  import Testing

  @testable import SwiftTUICore
  @testable import SwiftTUIRuntime

  @MainActor
  @Suite("Campaign F3 terminal session cleanup", .serialized)
  struct AdversarialSetETerminalLifetimeTests {
    @Test(arguments: Array(51...70))
    func terminalLifetime(id: Int) throws {
      let sink = try FileHandle(forUpdating: URL(fileURLWithPath: "/dev/null"))
      let controller = SetETerminalController()
      let host = TerminalHost(
        inputFileDescriptor: sink.fileDescriptor, outputFileDescriptor: sink.fileDescriptor,
        fallbackSize: .init(width: 20, height: 4), controller: controller,
        capabilityProfile: .trueColor, environment: [:])
      defer {
        controller.clearErrors()
        do { try host.disableRawMode() } catch { Issue.record("fixture cleanup failed: \(error)") }
        do { try sink.close() } catch { Issue.record("fixture descriptor close failed: \(error)") }
      }
      host.readerMode = [59, 60, 62, 64, 67].contains(id)
      switch id {
      case 51:
        controller.state.withLock { $0.tty = false }
        #expect(throws: TerminalHostError.self) { try host.enableRawMode() }
        #expect(controller.snapshot.enters == 0)
        #expect(controller.snapshot.restores == 0)
        controller.state.withLock { $0.tty = true }
      case 52:
        controller.state.withLock { $0.enterErrors = 1 }
        #expect(throws: SetETerminalError.entry) { try host.enableRawMode() }
        #expect(controller.snapshot.enters == 1)
        #expect(controller.snapshot.restores == 0)
      case 53...60:
        let command: String
        switch id {
        case 53: command = TerminalHostEscapeSequences.enterAlternateScreen
        case 54: command = TerminalHostEscapeSequences.clearScreen
        case 55: command = TerminalHostEscapeSequences.cursor(to: .zero)
        case 56: command = TerminalHostEscapeSequences.hideCursor
        case 57:
          command = TerminalHostEscapeSequences.enableMouseReporting(
            mouseCoordinateMode: .cells, hoverEnabled: false)
        case 59: command = TerminalHostEscapeSequences.showCursor
        default: command = TerminalHostEscapeSequences.enableBracketedPaste
        }
        controller.failWrite(command)
        #expect(throws: SetETerminalError.write) { try host.enableRawMode() }
        #expect(controller.snapshot.enters == 1)
        #expect(controller.snapshot.restores == 1)
        let reset = try #require(controller.snapshot.writes.last)
        #expect(reset.contains(TerminalHostEscapeSequences.disableBracketedPaste))
        #expect(reset.contains(TerminalHostEscapeSequences.showCursor))
        #expect(reset.contains(TerminalHostEscapeSequences.exitAlternateScreen) == !host.readerMode)
        try host.disableRawMode()
        #expect(controller.snapshot.restores == 1)
      case 61, 62:
        try host.enableRawMode()
        controller.state.withLock { $0.restoreErrors = 1 }
        #expect(throws: SetETerminalError.restore) { try host.disableRawMode() }
        try host.enableRawMode()
        #expect(controller.snapshot.enters == 1)
        try host.disableRawMode()
        #expect(controller.snapshot.restores == 2)
      case 63, 64:
        try host.enableRawMode()
        controller.failWrite(TerminalHostEscapeSequences.disableBracketedPaste)
        #expect(throws: SetETerminalError.write) { try host.disableRawMode() }
        #expect(controller.snapshot.restores == 1)
        let count = controller.snapshot.writes.count
        try host.disableRawMode()
        #expect(controller.snapshot.writes.count == count)
        #expect(controller.snapshot.restores == 1)
      case 65:
        try host.enableRawMode()
        controller.failWrite(TerminalHostEscapeSequences.disableBracketedPaste)
        controller.state.withLock { $0.restoreErrors = 1 }
        #expect(throws: SetETerminalError.restore) { try host.disableRawMode() }
        try host.disableRawMode()
        #expect(controller.snapshot.restores == 2)
      case 66, 67:
        try host.enableRawMode()
        let writes = controller.snapshot.writes.count
        try host.enableRawMode()
        #expect(controller.snapshot.enters == 1)
        #expect(controller.snapshot.writes.count == writes)
        try host.disableRawMode()
        try host.disableRawMode()
        #expect(controller.snapshot.restores == 1)
      case 68:
        try host.enableRawMode()
        controller.state.withLock { $0.restoreErrors = 1 }
        #expect(throws: SetETerminalError.restore) { try host.setReaderMode(true) }
        #expect(!host.readerMode)
        try host.setReaderMode(true)
        #expect(host.readerMode)
        #expect(controller.snapshot.enters == 2)
        #expect(controller.snapshot.restores == 2)
        try host.setReaderMode(true)
        #expect(controller.snapshot.enters == 2)
      case 69:
        try host.enableRawMode()
        let command = TerminalHostEscapeSequences.enableMouseReporting(
          mouseCoordinateMode: .cells, hoverEnabled: true)
        controller.failWrite(command)
        #expect(throws: SetETerminalError.write) { try host.setPointerHoverEnabled(true) }
        let beforeRetry = controller.snapshot.writes.count
        try host.setPointerHoverEnabled(true)
        #expect(controller.snapshot.writes.count == beforeRetry + 1)
        try host.setPointerHoverEnabled(true)
        #expect(controller.snapshot.writes.count == beforeRetry + 1)
      default:
        try host.disableRawMode()
        #expect(controller.snapshot.enters == 0)
        #expect(controller.snapshot.restores == 0)
        #expect(controller.snapshot.writes.isEmpty)
      }
      controller.clearErrors()
      try host.disableRawMode()
      let before = controller.snapshot
      try host.enableRawMode()
      try host.disableRawMode()
      #expect(controller.snapshot.enters == before.enters + 1)
      #expect(controller.snapshot.restores == before.restores + 1)
    }
  }

  private enum SetETerminalError: Error, Equatable { case entry, write, restore }

  private final class SetETerminalController: TerminalControlling {
    struct State: Sendable {
      var tty = true
      var enters = 0
      var restores = 0
      var writes: [String] = []
      var enterErrors = 0
      var restoreErrors = 0
      var writeErrors = 0
      var writeNeedle = ""
    }
    let state = Mutex(State())
    var snapshot: State { state.withLock { $0 } }
    func clearErrors() {
      state.withLock {
        $0.tty = true
        $0.enterErrors = 0
        $0.restoreErrors = 0
        $0.writeErrors = 0
      }
    }
    func failWrite(_ needle: String) {
      state.withLock {
        $0.writeNeedle = needle
        $0.writeErrors = 1
      }
    }
    func isATTY(_: Int32) -> Bool { snapshot.tty }
    func windowSize(of _: Int32) throws -> CellSize { .init(width: 20, height: 4) }
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      let fails = state.withLock { value in
        value.enters += 1
        if value.enterErrors > 0 {
          value.enterErrors -= 1
          return true
        }
        return false
      }
      if fails { throw SetETerminalError.entry }
      return .init()
    }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {
      let fails = state.withLock { value in
        value.restores += 1
        if value.restoreErrors > 0 {
          value.restoreErrors -= 1
          return true
        }
        return false
      }
      if fails { throw SetETerminalError.restore }
    }
    func write(_ output: String, to _: Int32) throws {
      let fails = state.withLock { value in
        value.writes.append(output)
        if value.writeErrors > 0 && output.contains(value.writeNeedle) {
          value.writeErrors -= 1
          return true
        }
        return false
      }
      if fails { throw SetETerminalError.write }
    }
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }
#endif
