import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite(.serialized)
struct AdversarialSetCIngressTests {
  @Test(arguments: [61, 62, 63, 64])
  func finiteStreamStartupAndEOF(id: Int) async throws {
    let root = testIdentity("setC\(id)")
    let ledger = SetCIngressLedger()
    let input: [InputEvent] =
      id == 64 ? [] : [.key(.character("a")), .key(.character("b")), .key(.character("c"))]
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 30, height: 4))
    let state = StateContainer(initialState: 0, invalidationIdentities: [root])
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetCFiniteInput(input), signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: state,
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      keyHandler: { key, _, state in
        guard case .character(let character) = key.key else { return .ignored }
        ledger.keys.append(character)
        ledger.readiness.append(ledger.ready)
        ledger.presentedAtInput.append(surface.frames.last ?? "")
        state.mutate { $0 += 1 }
        return .handled
      }, proposal: .init(width: 30, height: 4),
      viewBuilder: { value, _ in
        Text("input \(value)").onAppear {
          ledger.ready = 10
          ledger.appearances += 1
          if id == 62 { _ = state.replace(with: 10) }
        }
      })
    loop.renderMode = id == 63 ? .asyncNoCancel : .sync
    let result = try await loop.run()
    #expect(result.exitReason == .inputEnded)
    #expect(ledger.keys == (id == 64 ? [] : ["a", "b", "c"]))
    let expected = input.count + (id == 62 ? 10 : 0)
    #expect(result.finalState == expected)
    #expect(ledger.appearances == 1)
    #expect(ledger.readiness.allSatisfy { $0 == 10 })
    #expect(surface.frames.last?.contains("input \(expected)") == true)
    if id == 62 { #expect(ledger.presentedAtInput.first?.contains("input 10") == true) }
    #expect(loop.lifecycleCoordinator.activeTaskCount == 0)
  }

  @Test(arguments: Array(65...70))
  func pumpBoundariesAndArrivalAccounting(id: Int) throws {
    let instant = MonotonicInstant(offset: .seconds(10))
    let buffer = EventPumpBuffer(clock: { instant })
    func mouse(_ kind: MouseEvent.Kind, x: Double = 0) -> RuntimeEvent {
      .input(.mouse(.init(kind: kind, location: Point(x: x, y: 0), timestamp: instant)))
    }
    let events: [RuntimeEvent]
    switch id {
    case 65: events = [mouse(.moved), .input(.key(.character("k"))), mouse(.moved, x: 2)]
    case 66: events = [mouse(.moved), .input(.paste(.init(content: "a\nb"))), mouse(.moved, x: 2)]
    case 67:
      events = [
        mouse(.scrolled(deltaX: 1, deltaY: 2)), mouse(.scrolled(deltaX: 2, deltaY: 3)), .inputEnded,
      ]
    case 68:
      events = [
        mouse(.scrolled(deltaX: 0, deltaY: 1)), mouse(.scrolled(deltaX: 0, deltaY: 1), x: 1),
      ]
    case 69: events = [mouse(.dragged(.primary)), mouse(.dragged(.secondary), x: 1)]
    default: events = [mouse(.moved), mouse(.moved, x: 1)]
    }
    for event in events { buffer.enqueue(event) }
    #expect(buffer.oldestPendingArrival() == instant)
    var drained: [PumpedEvent] = []
    for _ in 0..<events.count { drained.append(contentsOf: buffer.drain()) }
    #expect(!buffer.hasPendingEvents())
    #expect(buffer.oldestPendingArrival() == nil)
    #expect(drained.reduce(0) { $0 + $1.arrival.count } == events.count)
    if id == 67 {
      try #require(drained.count == 2)
      if case .input(.mouse(let event)) = drained[0].event {
        #expect(event.kind == .scrolled(deltaX: 3, deltaY: 5))
      } else {
        Issue.record("expected merged wheel event")
      }
      if case .inputEnded = drained[1].event {} else { Issue.record("EOF must follow wheel input") }
      #expect(drained[0].arrival.count == 2)
    } else if id == 70 {
      #expect(drained.count == 1)
      buffer.enqueue(.input(.key(.character("z"))))
      let next = try #require(buffer.drain().first)
      #expect(next.arrival.id == 2)
      #expect(next.arrival.count == 1)
      #expect(buffer.oldestPendingArrival() == nil)
    } else {
      #expect(drained.count == events.count)
      for (actual, expected) in zip(drained, events) {
        if case .input(let a) = actual.event, case .input(let b) = expected {
          #expect(a == b)
        } else {
          Issue.record("expected an unchanged input event")
        }
      }
      #expect(drained.map(\.arrival.id) == Array(0..<UInt64(events.count)))
    }
  }
}

@MainActor
private final class SetCIngressLedger {
  var ready = 0
  var appearances = 0
  var keys: [Character] = []
  var readiness: [Int] = []
  var presentedAtInput: [String] = []
}

private final class SetCFiniteInput: TerminalInputReading {
  let stream: AsyncStream<InputEvent>
  init(_ events: [InputEvent]) {
    stream = AsyncStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish()
    }
  }
  func inputEvents() -> AsyncStream<InputEvent> { stream }
}
