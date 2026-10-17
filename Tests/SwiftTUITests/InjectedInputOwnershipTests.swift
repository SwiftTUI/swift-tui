import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite struct InjectedInputOwnershipTests {
  @Test func reentrantSendAndEOFFollowAlreadyAcceptedEvents() {
    let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    reader.send([.key(.init(.character("a"))), .key(.init(.character("b")))])
    let log = Mutex<[String]>([])
    reader.installDirectHandler { event in
      if case .key(let press) = event, case .character(let character) = press.key {
        log.withLock { $0.append(String(character)) }
        if character == "a" {
          reader.send(.key(.init(.character("c"))))
          reader.finish()
          reader.send(.key(.init(.character("d"))))
        }
      }
    } onFinish: {
      log.withLock { $0.append("end") }
    }
    #expect(log.withLock { $0 } == ["a", "b", "c", "end"])
  }

  @Test func detachingDuringDrainPreservesTheUnclaimedTail() async {
    let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    reader.send([.key(.init(.character("a"))), .key(.init(.character("b")))])
    let direct = Mutex<[InputEvent]>([])
    reader.installDirectHandler { event in
      direct.withLock { $0.append(event) }
      reader.clearDirectHandler()
    } onFinish: {
      Issue.record("Detached handler received EOF")
    }
    let stream = reader.inputEvents()
    reader.finish()
    var events: [InputEvent] = []
    for await event in stream { events.append(event) }
    #expect(direct.withLock { $0 } == [.key(.init(.character("a")))])
    #expect(events == [.key(.init(.character("b")))])
  }

  @Test func expiredPasteResetsTheEmbeddedControlObserver() async {
    let controls = Mutex<[TerminalControlMessage]>([])
    let reader = InjectedTerminalInputReader(mouseFlushScheduling: .manual) { message in
      controls.withLock { $0.append(message) }
    }
    let stream = reader.inputEvents()
    reader.send(Array("\u{1B}[200~text".utf8))
    reader.flushPendingEscapeDisambiguation()
    reader.send(Array("\u{1E}resize:80:24\nx".utf8))
    reader.finish()
    var events: [InputEvent] = []
    for await event in stream { events.append(event) }
    #expect(events == [.paste(.init(content: "text")), .key(.init(.character("x")))])
    #expect(controls.withLock { $0 } == [.resize(.init(width: 80, height: 24))])
  }
}
