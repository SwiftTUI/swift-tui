import Dispatch
import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIWebHost

@Suite
struct WebHostIngressTests {
  @Test("ingress queue enforces byte and record limits and preserves FIFO")
  func queueLimits() async throws {
    let queue = WebHostIngressQueue<[UInt8]>()
    for index in 0..<4 {
      #expect(queue.offer([UInt8](repeating: UInt8(index), count: 1024 * 1024), bytes: 1024 * 1024))
    }
    #expect(!queue.offer([9], bytes: 1))
    #expect(queue.snapshot.highWaterBytes == 4 * 1024 * 1024)
    queue.finish()
    var index: UInt8 = 0
    for await bytes in queue.stream() {
      #expect(bytes.first == index)
      index += 1
    }
    #expect(index == 4)
    #expect(queue.snapshot.bytes == 0)
    #expect(queue.snapshot.maximumConsumedAge < .seconds(5))

    let records = WebHostIngressQueue<Int>()
    for i in 0..<256 { #expect(records.offer(i, bytes: 0)) }
    #expect(!records.offer(256, bytes: 0))
    #expect(records.snapshot.highWaterRecords == 256)
    records.finish()
    var values: [Int] = []
    for await value in records.stream() { values.append(value) }
    #expect(values == Array(0..<256))
  }

  @Test("cancelled queue consumer wakes without another producer")
  func cancelledConsumer() async {
    let queue = WebHostIngressQueue<Int>()
    let consumer = Task { for await _ in queue.stream() {} }
    consumer.cancel()
    await consumer.value
    #expect(!queue.offer(1, bytes: 1))
  }

  @Test("queue delivery and finish race with cancellation without lock inversion")
  func finishCancellationRace() async {
    let completed = Mutex(false)
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
      precondition(completed.withLock { $0 }, "ingress cancellation watchdog expired")
    }
    defer { completed.withLock { $0 = true } }
    for index in 0..<2_048 {
      let queue = WebHostIngressQueue<Int>()
      let consumer = Task { for await _ in queue.stream() {} }
      let producer = Task {
        if index.isMultiple(of: 2) { queue.offer(index, bytes: 1) }
        queue.finish()
      }
      consumer.cancel()
      await consumer.value
      await producer.value
    }
  }

  @Test("thousands of finished receives retire while a replaced connection finishes later")
  func receiveRetirement() async throws {
    let channel = WebHostSceneChannel()
    let probe = IngressProbe()
    await channel.observeIngress { probe.record($0) }
    let events = channel.inboundEvents()
    let drain = Task { for await _ in events {} }
    let (old, oldContinuation) = AsyncStream<WebHostSocketMessage>.makeStream()
    let oldOutput = await channel.attach(client: old)
    for _ in 0..<2_048 {
      let (client, continuation) = AsyncStream<WebHostSocketMessage>.makeStream()
      let output = await channel.attach(client: client)
      continuation.finish()
      await probe.wait { $0?.activeReceiveTasks == 1 }
      withExtendedLifetime(output) {}
    }
    oldContinuation.yield(.data([0x71]))
    oldContinuation.finish()
    await probe.wait { $0?.activeReceiveTasks == 0 }
    withExtendedLifetime(oldOutput) {}
    await channel.shutdown()
    await drain.value
  }

  @Test("decoded reservations bound events even after a stalled runtime pump dequeues them")
  func heldRuntimeEvents() async throws {
    let channel = WebHostSceneChannel()
    let probe = IngressProbe()
    await channel.observeIngress { probe.record($0) }
    let reader = WebSocketInputReader(source: channel)
    let held = Mutex<[ScopedInputEvent]>([])
    let arrivals = ConditionSignal()
    let stream = reader.scopedInputEvents()
    let pump = Task {
      for await event in stream {
        held.withLock { $0.append(event) }
        arrivals.notify()
      }
    }
    let (client, continuation) = AsyncStream<WebHostSocketMessage>.makeStream()
    let output = await channel.attach(client: client)
    // One valid wire chunk expands to more events than a paused runtime admits.
    continuation.yield(.data([UInt8](repeating: 0x71, count: 257)))
    await probe.wait { $0?.currentToken == nil }
    #expect(reader.admittedInputSnapshot.refused > 0)
    #expect(reader.admittedInputSnapshot.highWaterRecords == 256)
    #expect(reader.admittedInputSnapshot.highWaterBytes <= 4 * 1024 * 1024)
    #expect(held.withLock { $0.allSatisfy { !$0.isCurrent } })
    held.withLock { $0.removeAll() }
    let (next, nextContinuation) = AsyncStream<WebHostSocketMessage>.makeStream()
    let nextOutput = await channel.attach(client: next)
    nextContinuation.yield(.data([0x72]))
    await arrivals.wait(until: {
      held.withLock { $0.contains { $0.isCurrent && $0.event == .key(.character("r")) } }
    })
    await channel.shutdown()
    await pump.value
    continuation.finish()
    nextContinuation.finish()
    withExtendedLifetime((output, nextOutput)) {}
  }

  @Test("replacement closes old sockets and failed attach closes the new socket")
  func saturatedAttach() async {
    let channel = WebHostSceneChannel()
    let oldClosed = Mutex(false)
    let newClosed = Mutex(false)
    let (oldClient, oldContinuation) = AsyncStream<WebHostSocketMessage>.makeStream()
    let old = await channel.attachSocket(client: oldClient) { oldClosed.withLock { $0 = true } }
    for _ in 0..<255 { oldContinuation.yield(.data([0x71])) }
    await channel.waitForProcessedInboundCallbacks(atLeast: 255)
    #expect(channel.ingressSnapshot.records == 256)
    let (newClient, newContinuation) = AsyncStream<WebHostSocketMessage>.makeStream()
    let next = await channel.attachSocket(client: newClient) { newClosed.withLock { $0 = true } }
    #expect(oldClosed.withLock { $0 })
    #expect(newClosed.withLock { $0 })
    #expect(next.token == nil)
    await channel.shutdown()
    oldContinuation.finish()
    newContinuation.finish()
    withExtendedLifetime((old.output, next.output)) {}
  }

  @Test("real socket overload with unique payloads disconnects and can reconnect")
  func slowSocketConsumer() async throws {
    try await withServer { session in
      let probe = IngressProbe()
      await session.channel.observeIngress { probe.record($0) }
      let socket = try WebSocketTestClient.connect(to: session.webSocketURL)
      defer { socket.close() }
      await probe.wait { $0?.currentToken != nil }
      let firstToken = await session.channel.currentConnectionToken()
      for index in 0..<4_096 {
        // Each frame owns different bytes; no shared copy-on-write payload.
        let payload = Data((String(index) + String(repeating: "x", count: 110)).utf8)
        do { try socket.sendBinary(payload) } catch { break }
      }
      await probe.wait { $0?.currentToken == nil && $0?.socket != nil }
      let scene = session.channel.ingressSnapshot
      let socketStats = try #require(await session.channel.socketIngressSnapshot)
      #expect(scene.highWaterRecords <= 256)
      #expect(scene.highWaterBytes <= 4 * 1024 * 1024)
      #expect(socketStats.highWaterRecords <= 256)
      #expect(socketStats.highWaterBytes <= 4 * 1024 * 1024)
      #expect(scene.refused + socketStats.refused > 0)
      #expect(socketStats.maximumConsumedAge < .seconds(5))
      print(
        "WebHost unique-payload saturation: scene \(scene.highWaterRecords) records / \(scene.highWaterBytes) bytes; socket \(socketStats.highWaterRecords) records / \(socketStats.highWaterBytes) bytes; maximum consumed age \(socketStats.maximumConsumedAge)"
      )
      let next = try WebSocketTestClient.connect(to: session.webSocketURL)
      defer { next.close() }
      await probe.wait { $0?.currentToken != nil && $0?.currentToken != firstToken }
      let start = ContinuousClock.now
      await session.stop()
      #expect(start.duration(to: .now) < .seconds(2))
    }
  }

  @Test("stale and boundary diagnostic payloads remain bounded without observation reads")
  func diagnosticLimits() async {
    let channel = WebHostSceneChannel()
    let probe = IngressProbe()
    await channel.observeIngress { probe.record($0) }
    for index in 0..<1000 {
      await channel.recordDiscardedInboundChunk(
        .init(
          token: UInt64(index),
          bytes: [UInt8](repeating: UInt8(truncatingIfNeeded: index), count: 128 * 1024),
          reason: index.isMultiple(of: 2) ? .staleAtIngress : .connectionBoundary))
    }
    let observations = await channel.consumeObservations()
    #expect(observations.discardedInboundChunks.count == 32)
    #expect(
      observations.discardedInboundChunks.reduce(0) { $0 + $1.bytes.count } == 4 * 1024 * 1024)
    #expect(await channel.consumeObservations().discardedInboundChunks.isEmpty)
    await channel.shutdown()
  }
}

private final class IngressProbe: Sendable {
  private let state = Mutex<WebHostSceneChannel.IngressObservation?>(nil)
  private let changes = ConditionSignal()
  func record(_ observation: WebHostSceneChannel.IngressObservation) {
    state.withLock { $0 = observation }
    changes.notify()
  }
  func wait(_ predicate: @escaping @Sendable (WebHostSceneChannel.IngressObservation?) -> Bool)
    async
  {
    await changes.wait(until: { self.state.withLock { predicate($0) } })
  }
}
