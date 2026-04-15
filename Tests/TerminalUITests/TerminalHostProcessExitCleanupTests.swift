import Testing

@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalHostProcessExitCleanupTests {
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

    TerminalProcessExitCleanupRegistry.runForTesting()
    closeFileDescriptor(&outputPipe.writeEnd)

    let output = try readUTF8(from: outputPipe.readEnd)
    #expect(output == "\u{001B}[?1002l\u{001B}[?1006l\u{001B}[?25h\u{001B}[0m\u{001B}[?1049l")
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
  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    var attributes = termios()
    attributes.c_iflag = tcflag_t(ICRNL | IXON)
    attributes.c_oflag = tcflag_t(OPOST)
    attributes.c_cflag = tcflag_t(CS8)
    attributes.c_lflag = tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
    return attributes
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> Size? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_: String, to _: Int32) throws {}

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}

private func makePipe() throws -> PipeEnds {
  var fileDescriptors: [Int32] = [0, 0]
  guard unsafe pipe(&fileDescriptors) == 0 else {
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
    let count = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
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
