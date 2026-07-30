import Foundation
@_spi(Runners) import SwiftTUI
import Synchronization
import Testing

@testable import SwiftTUIWebHost

/// The terminal half of the channel's lifecycle. The reconnect oracle is
/// deliberately nonterminal — `shutdown` is not a fixture action — so these
/// tests own the distinction that decides whether a reattaching client can ever
/// be served: a *client* close is connection-local, and only an explicit
/// session stop is terminal.
struct WebHostSceneChannelTerminalLifecycleTests {
  @Test("a client close is connection-local and leaves scene input alive")
  func clientCloseIsConnectionLocal() async throws {
    let channel = WebHostSceneChannel()
    var firstClient: AsyncStream<WebHostSocketMessage>.Continuation?
    let first = AsyncStream<WebHostSocketMessage> { firstClient = $0 }
    let firstOutput = await channel.attach(client: first)
    var events = channel.inboundEvents().makeAsyncIterator()
    guard case .connectionOpened(let firstToken) = try #require(await events.next()) else {
      Issue.record("attach did not open a tagged connection")
      return
    }

    firstClient?.yield(.normalClose)
    guard case .connectionClosed(let closedToken) = try #require(await events.next()) else {
      Issue.record("the client close did not retire its connection")
      return
    }
    #expect(closedToken == firstToken)

    let detached = await channel.consumeObservations()
    #expect(detached.phase == .detached)
    #expect(detached.currentToken == nil)
    #expect(detached.lastIssuedToken == firstToken)
    // The load-bearing assertion: finishing scene input here would terminate
    // `WebSocketInputReader` permanently, and a reattaching client's capability
    // declaration could never be read.
    #expect(!detached.sceneInputFinished)

    // A late callback from the retired client cannot detach or reactivate its
    // successor. Both halves of connection 2 stay in scope for the rest of the
    // test: releasing either one detaches it, which would make the assertions
    // below pass or fail on deallocation timing rather than on the behavior.
    var secondClient: AsyncStream<WebHostSocketMessage>.Continuation?
    let second = AsyncStream<WebHostSocketMessage> { secondClient = $0 }
    let secondOutput = await channel.attach(client: second)
    let secondToken = try #require(await channel.currentConnectionToken())
    #expect(secondToken == firstToken + 1)

    firstClient?.yield(.normalClose)
    firstClient?.yield(.data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)))
    let afterStaleCallbacks = await pollObservations(channel) { $0.ignoredStaleCallbackCount > 0 }
    #expect(afterStaleCallbacks.ignoredStaleCallbackCount >= 1)
    #expect(afterStaleCallbacks.currentToken == secondToken)
    #expect(afterStaleCallbacks.phase == .preCapabilities)
    #expect(!afterStaleCallbacks.sceneInputFinished)
    withExtendedLifetime((firstOutput, secondOutput, secondClient)) {}
  }

  @Test("session stop is idempotent, terminal, and reached by every stop path")
  func sessionStopIsIdempotentAndTerminal() async throws {
    let channel = WebHostSceneChannel()
    var client: AsyncStream<WebHostSocketMessage>.Continuation?
    let clientStream = AsyncStream<WebHostSocketMessage> { client = $0 }
    _ = await channel.attach(client: clientStream)
    try await channel.send(Array("\u{001E}runtimeIssue:{\"code\":\"before-stop\"}\n".utf8))

    // The stop-handler spy: `WebHostServerSession.stop()` must terminate the
    // channel *before* the server stop handler runs, so no client can attach
    // into a channel the session is tearing down.
    let spy = StopHandlerSpy()
    let session = WebHostServerSession(
      baseURL: URL(string: "http://127.0.0.1:1/")!,
      webSocketURL: URL(string: "ws://127.0.0.1:1/ws")!,
      token: WebHostToken(rawValue: "test-token"),
      channel: channel,
      stopHandler: { [spy, channel] in
        await spy.record(phaseAtStop: channel.consumeObservations().phase)
      }
    )

    await session.stop()

    #expect(await spy.stopCount() == 1)
    #expect(await spy.phaseAtStop() == .terminal)
    let stopped = await channel.consumeObservations()
    #expect(stopped.phase == .terminal)
    #expect(stopped.currentToken == nil)
    #expect(stopped.detachedNonSurfaceBacklogCount == 0)
    #expect(stopped.sceneInputFinished)

    // Scene input finished exactly once: a second shutdown is a harmless
    // no-op, not a second `finish()` on the continuation.
    await session.stop()
    #expect(await spy.stopCount() == 2)
    let afterSecondStop = await channel.consumeObservations()
    #expect(afterSecondStop.phase == .terminal)
    #expect(afterSecondStop.sceneInputFinished)

    // Later attach, send, input, and close callbacks cannot reactivate or
    // deliver.
    var lateClient: AsyncStream<WebHostSocketMessage>.Continuation?
    let lateStream = AsyncStream<WebHostSocketMessage> { lateClient = $0 }
    let lateOutput = await channel.attach(client: lateStream)
    // Asserted through the gauge rather than by awaiting the returned stream:
    // a terminal channel issues no token, and awaiting a stream that a broken
    // implementation left open would wedge instead of failing.
    #expect(await channel.lastIssuedConnectionToken() == stopped.lastIssuedToken)
    #expect(await channel.currentConnectionToken() == nil)
    withExtendedLifetime(lateOutput) {}
    try await channel.send(Array("\u{001E}runtimeIssue:{\"code\":\"after-stop\"}\n".utf8))
    try await channel.send(Array("\u{001E}surface:{\"version\":2}\n".utf8))
    lateClient?.yield(.data(Array("\u{001E}key:character:Z:0\n".utf8)))
    lateClient?.yield(.normalClose)

    let terminal = await pollObservations(channel) { _ in true }
    #expect(terminal.phase == .terminal)
    #expect(terminal.currentToken == nil)
    #expect(terminal.detachedNonSurfaceBacklogCount == 0)
    #expect(terminal.suppressedSurfaceRecords.isEmpty)
    #expect(terminal.capsProcessedCount == 0)
    #expect(terminal.refreshRequestCount == 0)
  }

  /// Bounded condition wait over consumed intervals: callbacks travel real
  /// async paths, so an assertion has to be allowed to arrive late — but never
  /// on a sleep.
  private func pollObservations(
    _ channel: WebHostSceneChannel,
    until predicate: (WebHostChannelObservations) -> Bool
  ) async -> WebHostChannelObservations {
    var latest = await channel.consumeObservations()
    for _ in 0..<512 {
      if predicate(latest) {
        return latest
      }
      await Task.yield()
      let next = await channel.consumeObservations()
      latest = WebHostChannelObservations(
        suppressedSurfaceRecords: latest.suppressedSurfaceRecords
          + next.suppressedSurfaceRecords,
        discardedInboundChunks: latest.discardedInboundChunks + next.discardedInboundChunks,
        detachedNonSurfaceBacklogCount: next.detachedNonSurfaceBacklogCount,
        detachedNonSurfaceBacklogBytes: next.detachedNonSurfaceBacklogBytes,
        refreshRequestCount: latest.refreshRequestCount + next.refreshRequestCount,
        capsProcessedCount: latest.capsProcessedCount + next.capsProcessedCount,
        ignoredStaleCallbackCount: latest.ignoredStaleCallbackCount
          + next.ignoredStaleCallbackCount,
        currentToken: next.currentToken,
        lastIssuedToken: next.lastIssuedToken,
        phase: next.phase,
        sceneInputFinished: next.sceneInputFinished
      )
    }
    return latest
  }

  private actor StopHandlerSpy {
    private var count = 0
    private var phase: WebHostSceneChannel.Phase?

    func record(phaseAtStop: WebHostSceneChannel.Phase) {
      count += 1
      if phase == nil {
        phase = phaseAtStop
      }
    }

    func stopCount() -> Int {
      count
    }

    func phaseAtStop() -> WebHostSceneChannel.Phase? {
      phase
    }
  }
}
