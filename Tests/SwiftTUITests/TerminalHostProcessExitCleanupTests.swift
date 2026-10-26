// Excluded from Windows builds (Windows plan, Stage 6 item 3): drives
// TerminalHost cleanup through POSIX pipe descriptors and child-process
// signal semantics with no Windows analogue in this shape.
#if !os(Windows)

  import Testing

  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUIRuntime

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  @MainActor
  @Suite
  struct TerminalHostProcessExitCleanupTests {
    @Test(
      "failed raw-mode entry restores output modes or retains exit cleanup",
      arguments: [false, true], [false, true])
    func failedEnableCleanup(reader: Bool, failCleanup: Bool) throws {
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        TerminalProcessExitCleanupRegistry.runForTesting()
        closePipe(&inputPipe)
        closePipe(&outputPipe)
      }
      let controller = ProcessExitCleanupController(failOnPaste: true, failCleanup: failCleanup)
      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd, outputFileDescriptor: outputPipe.writeEnd,
        fallbackSize: .init(width: 80, height: 24), controller: controller,
        capabilityProfile: .trueColor)
      host.readerMode = reader
      #expect(throws: CleanupWriteError.self) { try host.enableRawMode() }
      #expect(controller.restores.value == 1)
      let immediate = controller.writes.value.joined()
      if !failCleanup {
        // Failure cleanup must not clear the primary screen if alternate-screen
        // entry itself failed. Clearing belongs only to normal shutdown.
        #expect(
          controller.writes.value.last?.contains(TerminalHostEscapeSequences.clearScreen) == false)
        #expect(immediate.contains(TerminalHostEscapeSequences.disableBracketedPaste))
        #expect(immediate.contains(TerminalHostEscapeSequences.showCursor))
        #expect(immediate.contains(TerminalHostEscapeSequences.exitAlternateScreen) == !reader)
      }
      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)
      let fallback = try readUTF8(from: outputPipe.readEnd)
      #expect(fallback.isEmpty == !failCleanup)
      if failCleanup {
        #expect(fallback.contains(TerminalHostEscapeSequences.disableBracketedPaste))
        #expect(fallback.contains(TerminalHostEscapeSequences.showCursor))
        #expect(fallback.contains(TerminalHostEscapeSequences.exitAlternateScreen) == !reader)
      }
    }

    @Test("reader process-exit cleanup retains scrollback and resets raw input protocols")
    func readerProcessExitCleanup() throws {
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        closePipe(&inputPipe)
        closePipe(&outputPipe)
        TerminalProcessExitCleanupRegistry.runForTesting()
      }
      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd,
        outputFileDescriptor: outputPipe.writeEnd, fallbackSize: .init(width: 80, height: 24),
        controller: ProcessExitCleanupController(), capabilityProfile: .trueColor)
      host.readerMode = true
      try host.enableRawMode()
      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)
      #expect(try readUTF8(from: outputPipe.readEnd) == "\u{001B}[?2004l\u{001B}[?25h\u{001B}[0m")
    }
    @Test("process-exit cleanup restores the terminal for an active raw-mode host")
    func processExitCleanupRestoresActiveHost() throws {
      let controller = ProcessExitCleanupController()
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        closePipe(&inputPipe)
        closePipe(&outputPipe)
        TerminalProcessExitCleanupRegistry.runForTesting()
      }

      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd,
        outputFileDescriptor: outputPipe.writeEnd,
        fallbackSize: .init(width: 80, height: 24),
        controller: controller,
        capabilityProfile: .trueColor
      )

      try host.enableRawMode()
      // Leave raw mode before the pipes close: an enabled host keeps its
      // screen-ownership entry, whose captured pipe identity a later test's
      // pipe can reuse (macOS recycles pipe objects), refusing its writes.
      defer {
        do { try host.disableRawMode() } catch { Issue.record("fixture cleanup failed: \(error)") }
      }

      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)

      let output = try readUTF8(from: outputPipe.readEnd)
      #expect(
        output
          == "\u{001B}[?1002l\u{001B}[?1006l\u{001B}[?2004l\u{001B}[?25h\u{001B}[0m\u{001B}[?1049l"
      )
    }

    @Test("process-exit cleanup disables active terminal-pixel mouse mode")
    func processExitCleanupDisablesActiveTerminalPixelMouseMode() throws {
      let controller = ProcessExitCleanupController(cellPixelSize: .init(width: 8, height: 16))
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        closePipe(&inputPipe)
        closePipe(&outputPipe)
        TerminalProcessExitCleanupRegistry.runForTesting()
      }

      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd,
        outputFileDescriptor: outputPipe.writeEnd,
        fallbackSize: .init(width: 80, height: 24),
        controller: controller,
        capabilityProfile: .trueColor,
        pointerPrecisionPolicy: .forceTerminalPixels
      )

      try host.enableRawMode()
      // Leave raw mode before the pipes close: an enabled host keeps its
      // screen-ownership entry, whose captured pipe identity a later test's
      // pipe can reuse (macOS recycles pipe objects), refusing its writes.
      defer {
        do { try host.disableRawMode() } catch { Issue.record("fixture cleanup failed: \(error)") }
      }

      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)

      let output = try readUTF8(from: outputPipe.readEnd)
      #expect(
        output
          == "\u{001B}[?1002l\u{001B}[?1016l\u{001B}[?1006l\u{001B}[?2004l\u{001B}[?25h\u{001B}[0m\u{001B}[?1049l"
      )
    }

    @Test("process-exit cleanup disables hover mouse mode when it is active")
    func processExitCleanupDisablesActiveHoverMouseMode() throws {
      let controller = ProcessExitCleanupController()
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        closePipe(&inputPipe)
        closePipe(&outputPipe)
        TerminalProcessExitCleanupRegistry.runForTesting()
      }

      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd,
        outputFileDescriptor: outputPipe.writeEnd,
        fallbackSize: .init(width: 80, height: 24),
        controller: controller,
        capabilityProfile: .trueColor
      )

      try host.enableRawMode()
      // Leave raw mode before the pipes close: an enabled host keeps its
      // screen-ownership entry, whose captured pipe identity a later test's
      // pipe can reuse (macOS recycles pipe objects), refusing its writes.
      defer {
        do { try host.disableRawMode() } catch { Issue.record("fixture cleanup failed: \(error)") }
      }
      try host.setPointerHoverEnabled(true)

      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)

      let output = try readUTF8(from: outputPipe.readEnd)
      #expect(
        output
          == "\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1006l\u{001B}[?2004l\u{001B}[?25h\u{001B}[0m\u{001B}[?1049l"
      )
    }

    @Test("process-exit cleanup unregisters when raw mode is disabled normally")
    func processExitCleanupDoesNotDoubleRestoreAfterDisable() throws {
      let controller = ProcessExitCleanupController()
      var inputPipe = try makePipe()
      var outputPipe = try makePipe()
      defer {
        closePipe(&inputPipe)
        closePipe(&outputPipe)
        TerminalProcessExitCleanupRegistry.runForTesting()
      }

      let host = TerminalHost(
        inputFileDescriptor: inputPipe.readEnd,
        outputFileDescriptor: outputPipe.writeEnd,
        fallbackSize: .init(width: 80, height: 24),
        controller: controller,
        capabilityProfile: .trueColor
      )

      try host.enableRawMode()
      try host.disableRawMode()

      TerminalProcessExitCleanupRegistry.runForTesting()
      closeFileDescriptor(&outputPipe.writeEnd)

      let output = try readUTF8(from: outputPipe.readEnd)
      #expect(output.isEmpty)
    }
  }

  private struct PipeEnds {
    var readEnd: Int32
    var writeEnd: Int32
  }

  private final class ProcessExitCleanupController: TerminalControlling {
    private let cellPixelSizeValue: PixelSize?
    let writes = LockedBox<[String]>([])
    let restores = LockedBox(0)
    let failOnPaste: Bool
    let failCleanup: Bool

    init(cellPixelSize: PixelSize? = nil, failOnPaste: Bool = false, failCleanup: Bool = false) {
      cellPixelSizeValue = cellPixelSize
      self.failOnPaste = failOnPaste
      self.failCleanup = failCleanup
    }

    func isATTY(_: Int32) -> Bool {
      true
    }

    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      TerminalModeSnapshot()
    }

    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {
      restores.withLock { $0 += 1 }
    }

    func windowSize(of _: Int32) throws -> CellSize {
      .init(width: 80, height: 24)
    }

    func cellPixelSize(of _: Int32) throws -> PixelSize? {
      cellPixelSizeValue
    }

    func write(_ output: String, to _: Int32) throws {
      if failOnPaste && output == TerminalHostEscapeSequences.enableBracketedPaste {
        throw CleanupWriteError.failed
      }
      if failCleanup && output.contains(TerminalHostEscapeSequences.disableBracketedPaste) {
        throw CleanupWriteError.failed
      }
      writes.withLock { $0.append(output) }
    }

    func read(
      from _: Int32,
      maxBytes _: Int,
      timeoutMilliseconds _: Int
    ) throws -> [UInt8] {
      []
    }
  }

  private enum CleanupWriteError: Error { case failed }

  private func makePipe() throws -> PipeEnds {
    var fileDescriptors: [Int32] = [0, 0]
    guard openTestPipe(&fileDescriptors) == 0 else {
      throw PipeError.pipe(errno)
    }
    return .init(readEnd: fileDescriptors[0], writeEnd: fileDescriptors[1])
  }

  private func closePipe(
    _ pipe: inout PipeEnds
  ) {
    closeFileDescriptor(&pipe.readEnd)
    closeFileDescriptor(&pipe.writeEnd)
  }

  private func closeFileDescriptor(
    _ fileDescriptor: inout Int32
  ) {
    guard fileDescriptor >= 0 else {
      return
    }
    _ = close(fileDescriptor)
    fileDescriptor = -1
  }

  private func readUTF8(
    from fileDescriptor: Int32
  ) throws -> String {
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 256)

    while true {
      let count = buffer.withUnsafeMutableBytes { rawBuffer in
        unsafe read(
          fileDescriptor,
          rawBuffer.baseAddress,
          rawBuffer.count
        )
      }
      if count == 0 {
        break
      }
      guard count > 0 else {
        throw PipeError.read(errno)
      }
      bytes.append(contentsOf: buffer.prefix(count))
    }

    return String(decoding: bytes, as: UTF8.self)
  }

  private enum PipeError: Error {
    case pipe(Int32)
    case read(Int32)
  }

#endif
