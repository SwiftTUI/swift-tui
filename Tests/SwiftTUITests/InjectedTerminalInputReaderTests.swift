import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUI

@Suite
struct InjectedTerminalInputReaderTests {
  @Test("injected input reader routes resize control messages without leaking them as input")
  func injectedReaderRoutesResizeMessages() async {
    let receivedMessages = Mutex<[TerminalControlMessage]>([])
    let inputReader = InjectedTerminalInputReader(
      controlHandler: { message in
        receivedMessages.withLock { messages in
          messages.append(message)
        }
      }
    )

    let eventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    inputReader.send(Array("\u{001E}resize:120:40\nq".utf8))
    inputReader.finish()

    let events = await eventsTask.value

    #expect(receivedMessages.withLock { $0 } == [.resize(.init(width: 120, height: 40))])
    #expect(events == [.key(.character("q"))])
  }

  @Test("injected input reader routes style control messages without leaking them as input")
  func injectedReaderRoutesStyleMessages() async throws {
    let receivedMessages = Mutex<[TerminalControlMessage]>([])
    let inputReader = InjectedTerminalInputReader(
      controlHandler: { message in
        receivedMessages.withLock { messages in
          messages.append(message)
        }
      }
    )

    let eventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .white,
        backgroundColor: .black,
        tintColor: .cyan,
        source: .override
      ),
      theme: .init(
        foreground: .hex("#ECEFF4"),
        background: .hex("#1E222A"),
        tint: .hex("#56B6C2"),
        separator: .hex("#4C566A"),
        selection: .hex("#2E3440"),
        placeholder: .hex("#7F8794"),
        link: .hex("#5BA3FF"),
        fill: .hex("#2B303B"),
        windowBackground: .hex("#15181E"),
        success: .hex("#61C67B"),
        warning: .hex("#EBB33C"),
        danger: .hex("#E05757"),
        info: .hex("#56B6C2"),
        muted: .hex("#8C92AC")
      )
    )
    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))

    inputReader.send(Array("\u{001E}style:\(encoded)\nq".utf8))
    inputReader.finish()

    let events = await eventsTask.value

    #expect(receivedMessages.withLock { $0 } == [.style(style)])
    #expect(events == [.key(.character("q"))])
  }

  @Test("injected input reader flushes pointer bursts before later key input")
  func injectedReaderFlushesPointerBurstsBeforeLaterKeyInput() async {
    let inputReader = InjectedTerminalInputReader()

    let eventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    let scrollSequence: [UInt8] = [
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
    ]

    for _ in 0..<20 {
      inputReader.send(scrollSequence)
    }
    inputReader.send(Array("q".utf8))
    inputReader.finish()

    let events = await eventsTask.value

    let mouseEvents = Array(events.dropLast())

    #expect(!mouseEvents.isEmpty)
    #expect(events.last == .key(.character("q")))
    #expect(
      mouseEvents.allSatisfy { event in
        guard case .mouse(let mouseEvent) = event,
          case .scrolled(let deltaX, let deltaY) = mouseEvent.kind
        else {
          return false
        }
        return deltaX == 0
          && deltaY > 0
          && mouseEvent.location.cell == CellPoint(x: 4, y: 6)
          && mouseEvent.location.precision == .cell
      }
    )
    #expect(
      mouseEvents.reduce(0) { partial, event in
        guard case .mouse(let mouseEvent) = event,
          case .scrolled(_, let deltaY) = mouseEvent.kind
        else {
          return partial
        }
        return partial + deltaY
      } == 20
    )
  }

  @Test("injected input reader parses terminal-pixel mouse coordinates when configured")
  func injectedReaderParsesTerminalPixelMouseCoordinatesWhenConfigured() async {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let inputReader = InjectedTerminalInputReader(
      mouseCoordinateMode: .pixels(metrics: metrics, source: .terminalPixels)
    )

    let eventsTask = Task {
      var events: [InputEvent] = []
      for await event in inputReader.inputEvents() {
        events.append(event)
      }
      return events
    }

    inputReader.send(Array("\u{001B}[<0;17;33Mq".utf8))
    inputReader.finish()

    let events = await eventsTask.value

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
