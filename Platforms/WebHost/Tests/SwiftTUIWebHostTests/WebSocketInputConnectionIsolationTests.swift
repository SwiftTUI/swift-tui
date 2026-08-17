// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises the
// WebHost server stack, whose modules build empty on Windows
// (whole-file-guarded).
#if !os(Windows)

  import Foundation
  @_spi(Runners) import SwiftTUI
  import SwiftTUIWASISurfaceBridge
  import Synchronization
  import Testing

  @testable import SwiftTUIWebHost

  /// The three refusals that make a WebSocket reconnect safe, each proven on its
  /// own. The conformance fixture covers the pre-parse queue filter; these cover
  /// the two it explicitly does not — resetting an already-buffered parser
  /// fragment at a connection boundary, and rechecking the token after a record
  /// is parsed but before it is applied.
  struct WebSocketInputConnectionIsolationTests {
    @Test("a connection boundary clears buffered parser state")
    func connectionBoundaryClearsBufferedParserState() async throws {
      let harness = await IsolationHarness.make()

      // A partial capability record: the parser holds it, waiting for the
      // newline that never comes on this connection.
      await harness.feed(token: 1, "\u{001E}caps:{\"acceptsDelta")
      let buffered = try #require(harness.lastParserObservation())
      #expect(buffered.token == 1)
      #expect(buffered.bufferedBytes > 0)

      await harness.closeCurrentClient()
      let secondToken = await harness.attach()
      #expect(secondToken == 2)
      await harness.advanceThroughConnectionBoundary(token: secondToken)

      let reset = try #require(harness.lastParserObservation())
      #expect(reset.token == 2)
      #expect(reset.bufferedBytes == 0)
      let discarded = await harness.channel.consumeObservations().discardedInboundChunks
      #expect(discarded.count == 1)
      #expect(discarded.first?.token == 1)
      #expect(discarded.first?.reason == .connectionBoundary)
      #expect(discarded.first?.bytes == Array("caps:{\"acceptsDelta".utf8))

      // Only now may clean current-token capabilities be supplied; the
      // successor's bytes were never allowed to complete the abandoned record.
      await harness.feed(token: secondToken, "\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
      #expect(
        harness.transport.wireCapabilities == HostWireCapabilities(acceptsDeltaFrames: true))
      let activated = await harness.channel.consumeObservations()
      #expect(activated.phase == .active)
      #expect(activated.capsProcessedCount == 1)
    }

    @Test("a parsed capability record rechecks its token before application")
    func parsedCapsRechecksTokenBeforeApplication() async throws {
      let harness = await IsolationHarness.make()
      // The connection retires while the parsed declaration is in hand.
      harness.holdNextRecord { [harness] in
        await harness.closeCurrentClient()
        _ = await harness.attach()
      }

      await harness.feed(token: 1, "\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")

      #expect(harness.transport.wireCapabilities == HostWireCapabilities())
      let refused = await harness.channel.consumeObservations()
      #expect(refused.capsProcessedCount == 0)
      #expect(refused.refreshRequestCount == 0)
      #expect(refused.phase == .preCapabilities)
      #expect(refused.currentToken == 2)
      // The refusal has to happen in the reader, not only in the channel's own
      // gate: a stale declaration that reached `applyCapabilities` would be
      // counted as an ignored stale callback. Zero means the record never got
      // that far.
      #expect(refused.ignoredStaleCallbackCount == 0)

      // Clean current-token capabilities still activate and auto-refresh.
      await harness.feed(token: 2, "\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
      #expect(
        harness.transport.wireCapabilities == HostWireCapabilities(acceptsDeltaFrames: true))
      let activated = await harness.channel.consumeObservations()
      #expect(activated.capsProcessedCount == 1)
      #expect(activated.refreshRequestCount == 1)
      #expect(activated.phase == .active)
    }

    @Test("parsed terminal input rechecks its token before it is yielded")
    func parsedTerminalInputRechecksTokenBeforeYield() async throws {
      let harness = await IsolationHarness.make()
      harness.holdNextRecord { [harness] in
        await harness.closeCurrentClient()
        _ = await harness.attach()
      }

      await harness.feed(token: 1, "\u{001E}key:character:X:0\n")
      #expect(await harness.yieldedEvents().isEmpty)

      // Clean current-token input still reaches the scene.
      let resumed = await IsolationHarness.make()
      await resumed.feed(token: 1, "\u{001E}key:character:Y:0\n")
      #expect(
        await resumed.yieldedEvents() == [.key(.init(.character("Y"), modifiers: []))])
    }

    /// A real channel, transport, and reader, stepped one tagged event at a time.
    private final class IsolationHarness: Sendable {
      let channel: WebHostSceneChannel
      let transport: WebSocketSurfaceTransport
      let reader: WebSocketInputReader
      private let observations: Observations
      private let connections = Mutex(Connections())

      private struct Connections {
        var clients: [UInt64: AsyncStream<WebHostSocketMessage>.Continuation] = [:]
        // Retained: dropping an output stream terminates its connection.
        var outputs: [AsyncStream<WebHostSocketMessage>] = []
      }

      init() {
        let channel = WebHostSceneChannel()
        let sink = DiscardingSink()
        let transport = WebSocketSurfaceTransport(
          surfaceSize: .init(width: 1, height: 1),
          sink: sink
        )
        let observations = Observations()
        self.channel = channel
        self.transport = transport
        self.observations = observations
        let hooks = WebSocketInputReaderTestHooks(
          parserStateDidChange: { token, bufferedBytes in
            observations.recordParserState(token: token, bufferedBytes: bufferedBytes)
          },
          beforeApplyParsedRecord: { _, _ in
            await observations.runPendingBarrier()
          }
        )
        let controlHandler: @Sendable (WebSurfaceInputControlMessage, UInt64) async -> Void = {
          message, token in
          switch message {
          case .resize(let size, let cellPixelSize):
            transport.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
          case .style(let style):
            transport.updateStyle(style)
          case .pointerCapabilities(let supportsScrollPanning):
            transport.updatePointerCapabilities(
              supportsScrollPanning: supportsScrollPanning
            )
          case .capabilities(let capabilities):
            await channel.applyCapabilities(
              token: token,
              reanchor: { transport.declareCapabilities(capabilities) },
              requestRefresh: { transport.requestSurfaceRefresh() }
            )
          case .resync(let request):
            transport.requestResync(request)
          }
        }
        reader = WebSocketInputReader(
          source: channel,
          hooks: hooks,
          controlHandler: controlHandler
        )
      }

      static func make() async -> IsolationHarness {
        let harness = IsolationHarness()
        _ = await harness.attach()
        return harness
      }

      /// Holds the next parsed record at the reader's application-time token
      /// check and runs `barrier` in the gap.
      func holdNextRecord(
        _ barrier: @escaping @Sendable () async -> Void
      ) {
        observations.setBarrier(barrier)
      }

      @discardableResult
      func attach() async -> UInt64 {
        var continuation: AsyncStream<WebHostSocketMessage>.Continuation?
        let client = AsyncStream<WebHostSocketMessage> { continuation = $0 }
        let output = await channel.attach(client: client)
        let token = await channel.currentConnectionToken() ?? 0
        connections.withLock { connections in
          connections.clients[token] = continuation!
          connections.outputs.append(output)
        }
        return token
      }

      func closeCurrentClient() async {
        guard let token = await channel.currentConnectionToken() else {
          Issue.record("no current client to close")
          return
        }
        connections.withLock { $0.clients[token] }?.yield(.normalClose)
        // Bounded condition wait: the close travels the real receive path.
        for _ in 0..<512 {
          if await channel.currentConnectionToken() == nil {
            return
          }
          await Task.yield()
        }
        Issue.record("the current client never detached")
      }

      func feed(
        token: UInt64,
        _ text: String
      ) async {
        await reader.process(
          .bytes(token: token, Array(text.utf8)),
          yielding: observations.continuation
        )
      }

      func advanceThroughConnectionBoundary(
        token: UInt64
      ) async {
        await reader.process(
          .connectionOpened(token: token),
          yielding: observations.continuation
        )
      }

      func lastParserObservation() -> (token: UInt64?, bufferedBytes: Int)? {
        observations.parserState()
      }

      func yieldedEvents() async -> [InputEvent] {
        await observations.finishAndCollect()
      }
    }

    private final class Observations: Sendable {
      private struct Storage {
        var parserState: (token: UInt64?, bufferedBytes: Int)?
        var barrier: (@Sendable () async -> Void)?
      }

      let continuation: AsyncStream<InputEvent>.Continuation
      private let stream: AsyncStream<InputEvent>
      private let storage = Mutex(Storage())

      init() {
        var continuation: AsyncStream<InputEvent>.Continuation?
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
      }

      func recordParserState(
        token: UInt64?,
        bufferedBytes: Int
      ) {
        storage.withLock { $0.parserState = (token, bufferedBytes) }
      }

      func parserState() -> (token: UInt64?, bufferedBytes: Int)? {
        storage.withLock(\.parserState)
      }

      func setBarrier(
        _ barrier: @escaping @Sendable () async -> Void
      ) {
        storage.withLock { $0.barrier = barrier }
      }

      /// Runs the pending barrier exactly once.
      func runPendingBarrier() async {
        let barrier = storage.withLock { storage -> (@Sendable () async -> Void)? in
          let barrier = storage.barrier
          storage.barrier = nil
          return barrier
        }
        await barrier?()
      }

      func finishAndCollect() async -> [InputEvent] {
        continuation.finish()
        var collected: [InputEvent] = []
        for await event in stream {
          collected.append(event)
        }
        return collected
      }
    }

    private final class DiscardingSink: WebHostByteSink, Sendable {
      func send(_ bytes: [UInt8]) async throws {}
    }
  }

#endif
