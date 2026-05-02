import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct InputReaderControlMessageTests {
  @Test("input reader routes resize control messages without leaking them as key input")
  func inputReaderRoutesResizeControlMessages() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

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
      var events: [KeyPress] = []
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
    #expect(events == [KeyPress(.character("q"))])
  }

  @Test("input reader routes style control messages without leaking them as key input")
  func inputReaderRoutesStyleControlMessages() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

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
      var events: [KeyPress] = []
      for await event in inputReader.events() {
        events.append(event)
      }
      return events
    }

    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .black,
        backgroundColor: .white,
        tintColor: .blue,
        source: .override
      ),
      theme: .init(
        foreground: .hex("#101820"),
        background: .hex("#F5F5F5"),
        tint: .hex("#0F4C81"),
        separator: .hex("#C8CDD4"),
        selection: .hex("#DCE7F7"),
        placeholder: .hex("#8A94A6"),
        link: .hex("#0F4C81"),
        fill: .hex("#EEF2F6"),
        windowBackground: .hex("#E6EBF2"),
        success: .hex("#0F9D58"),
        warning: .hex("#F4B400"),
        danger: .hex("#DB4437"),
        info: .hex("#4285F4"),
        muted: .hex("#6B7280")
      )
    )
    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    let controlPayload = Array("\u{001E}style:\(encoded)\nq".utf8)
    try writeAllBytes(controlPayload, to: writeDescriptor)
    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true

    let events = await eventsTask.value

    _ = close(readDescriptor)
    didCloseReadDescriptor = true

    #expect(receivedMessages.withLock { $0 } == [.style(style)])
    #expect(events == [KeyPress(.character("q"))])
  }

  @Test("input reader applies resolved terminal-pixel mouse coordinates")
  func inputReaderAppliesResolvedTerminalPixelMouseCoordinates() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(unsafe pipe(&descriptors) == 0)

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

    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let inputReader = InputReader(
      fileDescriptor: readDescriptor
    )
    inputReader.updateInputCapabilities(
      ResolvedTerminalInputCapabilities(
        mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
      )
    )

    let eventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    try writeAllBytes(Array("\u{001B}[<0;17;33Mq".utf8), to: writeDescriptor)
    _ = close(writeDescriptor)
    didCloseWriteDescriptor = true

    let events = await eventsTask.value

    _ = close(readDescriptor)
    didCloseReadDescriptor = true

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
        ),
        .key(.character("q")),
      ])
  }
}

private func writeAllBytes(
  _ bytes: [UInt8],
  to fileDescriptor: Int32
) throws {
  var bytesWritten = 0
  while bytesWritten < bytes.count {
    let written = unsafe bytes.withUnsafeBytes { buffer -> Int in
      guard let baseAddress = buffer.baseAddress else {
        return 0
      }
      let nextAddress = unsafe baseAddress.advanced(by: bytesWritten)
      return unsafe write(
        fileDescriptor,
        nextAddress,
        bytes.count - bytesWritten
      )
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
