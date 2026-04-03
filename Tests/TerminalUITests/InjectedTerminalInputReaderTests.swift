import Synchronization
import Testing

@_spi(Runners) @testable import TerminalUI

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
}
