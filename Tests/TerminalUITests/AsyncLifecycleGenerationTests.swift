import Testing

@_spi(Runners) @testable import TerminalUI

@Suite("Async lifecycle generation fences")
struct AsyncLifecycleGenerationTests {
  @Test("signal reader ignores stale stream teardown after replacement")
  func signalReaderIgnoresStaleStreamTeardownAfterReplacement() async throws {
    let reader = InProcessSignalReader()
    let firstReady = AwaitingNextProbe()
    let secondReady = AwaitingNextProbe()
    let firstConsumer = awaitNextValue(
      from: reader.events(),
      readyProbe: firstReady
    )
    let secondConsumer = awaitNextValue(
      from: reader.events(),
      readyProbe: secondReady
    )

    try await waitUntil("first signal consumer ready") {
      await firstReady.isReady
    }
    try await waitUntil("second signal consumer ready") {
      await secondReady.isReady
    }

    firstConsumer.cancel()
    _ = await firstConsumer.result

    reader.send("SIGWINCH")

    let signal = try await awaitTaskValue(
      secondConsumer,
      label: "replacement signal delivery"
    )

    #expect(signal == "SIGWINCH")
    reader.finish()
  }

  @Test("injected input reader ignores stale stream teardown after replacement")
  func injectedInputReaderIgnoresStaleStreamTeardownAfterReplacement() async throws {
    let inputReader = InjectedTerminalInputReader()
    let firstReady = AwaitingNextProbe()
    let secondReady = AwaitingNextProbe()
    let firstConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readyProbe: firstReady
    )
    let secondConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readyProbe: secondReady
    )

    try await waitUntil("first input consumer ready") {
      await firstReady.isReady
    }
    try await waitUntil("second input consumer ready") {
      await secondReady.isReady
    }

    firstConsumer.cancel()
    _ = await firstConsumer.result

    inputReader.send(Array("q".utf8))

    let event = try await awaitTaskValue(
      secondConsumer,
      label: "replacement input delivery"
    )

    #expect(event == .key(.character("q")))
    inputReader.finish()
  }

  @Test("injected input reader preserves pending mouse flushes across stale teardown")
  func injectedInputReaderPreservesPendingMouseFlushesAcrossStaleTeardown() async throws {
    let inputReader = InjectedTerminalInputReader()
    let firstReady = AwaitingNextProbe()
    let secondReady = AwaitingNextProbe()
    let firstConsumer = awaitNextValue(
      from: inputReader.inputEvents(),
      readyProbe: firstReady
    )
    let secondConsumer = collectEvents(
      from: inputReader.inputEvents(),
      readyProbe: secondReady
    )
    let scrollSequence: [UInt8] = [
      0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x35, 0x3B, 0x37, 0x4D,
    ]

    try await waitUntil("first mouse input consumer ready") {
      await firstReady.isReady
    }
    try await waitUntil("second mouse input consumer ready") {
      await secondReady.isReady
    }

    inputReader.send(scrollSequence)
    firstConsumer.cancel()
    _ = await firstConsumer.result
    inputReader.send(scrollSequence)

    try await Task.sleep(nanoseconds: 20_000_000)
    inputReader.finish()

    let events = try await awaitTaskValue(
      secondConsumer,
      label: "replacement mouse flush delivery"
    )

    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .scrolled(deltaX: 0, deltaY: 2),
            location: .init(x: 4, y: 6)
          )
        )
      ]
    )
  }
}

private actor AwaitingNextProbe {
  private(set) var isReady = false

  func markReady() {
    isReady = true
  }
}

private func awaitNextValue<Element: Sendable>(
  from stream: AsyncStream<Element>,
  readyProbe: AwaitingNextProbe
) -> Task<Element?, Never> {
  Task {
    var iterator = stream.makeAsyncIterator()
    await readyProbe.markReady()
    return await iterator.next()
  }
}

private func collectEvents<Element: Sendable>(
  from stream: AsyncStream<Element>,
  readyProbe: AwaitingNextProbe
) -> Task<[Element], Never> {
  Task {
    var iterator = stream.makeAsyncIterator()
    await readyProbe.markReady()

    var events: [Element] = []
    while let event = await iterator.next() {
      events.append(event)
    }
    return events
  }
}

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 1_000_000_000,
  pollNanoseconds: UInt64 = 10_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !(await condition()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw AsyncLifecycleGenerationTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private func awaitTaskValue<Value: Sendable>(
  _ task: Task<Value, Never>,
  label: String,
  timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> Value {
  try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask {
      await task.value
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw AsyncLifecycleGenerationTimeout(label)
    }

    let value = try await group.next()
    group.cancelAll()
    return try #require(value)
  }
}

private struct AsyncLifecycleGenerationTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
