import Synchronization
import Testing

@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite
struct InputReaderControlMessageTests {
  @Test("input reader routes resize control messages without leaking them as key input")
  func inputReaderRoutesResizeControlMessages() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(pipe(&descriptors) == 0)

    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    var didCloseReadDescriptor = false
    var didCloseWriteDescriptor = false
    defer {
      if !didCloseReadDescriptor {
        _ = close(readDescriptor)
      }
      if !didCloseWriteDescriptor {
        _ = close(writeDescriptor)
      }
    }

    let currentFlags = fcntl(readDescriptor, F_GETFL)
    #expect(currentFlags >= 0)
    #expect(fcntl(readDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0)

    let receivedMessages = Mutex<[TerminalControlMessage]>([])
    let inputReader = InputReader(
      fileDescriptor: readDescriptor,
      controlHandler: { message in
        receivedMessages.withLock { messages in
          messages.append(message)
        }
      }
    )

    let eventsTask = Task {
      var events: [KeyEvent] = []
      for await event in inputReader.events() {
        events.append(event)
      }
      return events
    }

    let controlPayload = Array("\u{001E}resize:120:40\nq".utf8)
    try writeAllBytes(controlPayload, to: writeDescriptor)
    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true

    let events = await eventsTask.value

    _ = close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(receivedMessages.withLock { $0 } == [.resize(.init(width: 120, height: 40))])
    #expect(events == [.character("q")])
  }
}

private func writeAllBytes(
  _ bytes: [UInt8],
  to fileDescriptor: Int32
) throws {
  var bytesWritten = 0
  while bytesWritten < bytes.count {
    let written = bytes.withUnsafeBytes { buffer -> Int in
      guard let baseAddress = buffer.baseAddress else {
        return 0
      }
      #if canImport(Darwin)
        return Darwin.write(
          fileDescriptor,
          baseAddress.advanced(by: bytesWritten),
          bytes.count - bytesWritten
        )
      #elseif canImport(Glibc)
        return Glibc.write(
          fileDescriptor,
          baseAddress.advanced(by: bytesWritten),
          bytes.count - bytesWritten
        )
      #endif
    }

    if written > 0 {
      bytesWritten += written
      continue
    }

    throw InputReaderControlMessageTestError.writeFailed
  }
}

private enum InputReaderControlMessageTestError: Error {
  case writeFailed
}
