@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite("Async lifecycle generation fences")
struct AsyncLifecycleGenerationTests {
  @Test("signal reader ignores stale stream teardown after replacement")
  func signalReaderIgnoresStaleStreamTeardownAfterReplacement() async throws {
    let reader = InProcessSignalReader()
    let firstReady = AsyncEvent()
    let secondReady = AsyncEvent()
    let firstConsumer = awaitNextValue(
      from: reader.events(),
      readySignal: firstReady
    )
    let secondConsumer = awaitNextValue(
      from: reader.events(),
      readySignal: secondReady
    )

    await firstReady.wait()
    await secondReady.wait()

    firstConsumer.cancel()
    _ = await firstConsumer.result

    reader.send("SIGWINCH")

    let signal = try #require(await secondConsumer.value)

    #expect(signal == "SIGWINCH")
    reader.finish()
  }

  @Test("injected input reader ignores stale stream teardown after replacement")
  func injectedInputReaderIgnoresStaleStreamTeardownAfterReplacement() async throws {
    let inputReader = InjectedTerminalInputReader()
    let firstReady = AsyncEvent()
    let secondReady = AsyncEvent()
    let firstConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readySignal: firstReady
    )
    let secondConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readySignal: secondReady
    )

    await firstReady.wait()
    await secondReady.wait()

    firstConsumer.cancel()
    _ = await firstConsumer.result

    inputReader.send(Array("q".utf8))

    let event = try #require(await secondConsumer.value)

    #expect(event == .key(.character("q")))
    inputReader.finish()
  }

  @Test("injected input reader preserves pending mouse flushes across stale teardown")
  func injectedInputReaderPreservesPendingMouseFlushesAcrossStaleTeardown() async throws {
    let inputReader = InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    let firstReady = AsyncEvent()
    let secondReady = AsyncEvent()
    let firstConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readySignal: firstReady
    )
    let secondConsumer = Task { () -> [InputEvent] in
      var iterator = inputReader.inputEvents().makeAsyncIterator()
      secondReady.fire()

      var events: [InputEvent] = []
      while let event = await iterator.next() {
        events.append(event)
      }
      return events
    }
    let scrollSequence: [UInt8] = [
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
    ]

    await firstReady.wait()
    await secondReady.wait()

    inputReader.send(scrollSequence)
    firstConsumer.cancel()
    _ = await firstConsumer.result
    inputReader.send(scrollSequence)

    let flushedEvents = inputReader.flushPendingCoalescedMouseEvents()
    inputReader.finish()

    let events = await secondConsumer.value
    let expectedEvents: [InputEvent] = [
      .mouse(
        MouseEvent(
          kind: .scrolled(deltaX: 0, deltaY: 2),
          location: .cellFallback(CellPoint(x: 4, y: 6))
        )
      )
    ]

    #expect(flushedEvents == expectedEvents)
    #expect(events == expectedEvents)
  }
}

/// Spawns a consumer that subscribes to `stream` and resolves to its first
/// element. `readySignal` fires once the iterator exists, so the caller can
/// `await` exactly when the consumer has claimed its stream generation —
/// no polling, no timeout.
private func awaitNextValue<Element: Sendable>(
  from stream: AsyncStream<Element>,
  readySignal: AsyncEvent
) -> Task<Element?, Never> {
  Task {
    var iterator = stream.makeAsyncIterator()
    readySignal.fire()
    return await iterator.next()
  }
}
