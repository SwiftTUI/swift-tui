import Synchronization
import Testing

@testable import TerminalUI

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
}
