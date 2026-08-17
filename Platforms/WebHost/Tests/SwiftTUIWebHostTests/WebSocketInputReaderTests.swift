// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises the
// WebHost server stack, whose modules build empty on Windows
// (whole-file-guarded).
#if !os(Windows)

  import Foundation
  @_spi(Runners) import SwiftTUI
  import Testing

  @testable import SwiftTUIWebHost

  struct WebSocketInputReaderTests {
    @Test("resize wake survives a late signal-stream subscription")
    func resizeWakeSurvivesLateSignalSubscription() async throws {
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 1, height: 1),
        sink: RecordingInputTestSink()
      )
      let signalReader = InProcessSignalReader()
      let client = await ChannelClient.attached(
        transport: transport,
        signalReader: signalReader
      )

      await client.feed("\u{001E}resize:120:60:9:18\n")
      var signalIterator = signalReader.events().makeAsyncIterator()

      #expect(transport.surfaceSize == .init(width: 120, height: 60))
      #expect(await signalIterator.next() == "SIGWINCH")
      signalReader.finish()
    }

    @Test("resize and style input update the transport")
    func resizeAndStyleInputUpdateTransport() async throws {
      let sink = RecordingInputTestSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 1, height: 1),
        sink: sink
      )
      let signalReader = InProcessSignalReader()
      var signalIterator = signalReader.events().makeAsyncIterator()
      let client = await ChannelClient.attached(
        transport: transport,
        signalReader: signalReader
      )
      let style = TerminalRenderStyle(
        appearance: .init(
          foregroundColor: try! .hex("#102030"),
          backgroundColor: try! .hex("#405060"),
          tintColor: try! .hex("#708090"),
          source: .override
        )
      )
      let encodedStyle = try #require(TerminalRenderStyleCodec.encodeBase64(style))

      await client.feed("\u{001E}resize:80:24:9:18\n\u{001E}style:\(encodedStyle)\n")

      #expect(await client.yieldedEvents().isEmpty)
      #expect(transport.surfaceSize == .init(width: 80, height: 24))
      #expect(transport.appearance == style.appearance)
      #expect(transport.pointerInputCapabilities.precision.isSubCell)
      #expect(await signalIterator.next() == "SIGWINCH")
      #expect(await signalIterator.next() == "SIGWINCH")
      signalReader.finish()
    }

    @Test("a caps record declares capabilities, activates delivery, and refreshes")
    func capsRecordDeclaresWireCapabilities() async throws {
      let sink = RecordingInputTestSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 1, height: 1),
        sink: sink
      )
      let client = await ChannelClient.attached(transport: transport)
      #expect(transport.wireCapabilities == HostWireCapabilities())
      let attached = await client.channel.consumeObservations()
      #expect(attached.phase == .preCapabilities)

      await client.feed("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")

      #expect(
        transport.wireCapabilities == HostWireCapabilities(acceptsDeltaFrames: true)
      )
      let declared = await client.channel.consumeObservations()
      #expect(declared.phase == .active)
      #expect(declared.capsProcessedCount == 1)
      #expect(declared.refreshRequestCount == 1)

      // A second declaration on the same connection is not a new epoch.
      await client.feed("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
      let repeated = await client.channel.consumeObservations()
      #expect(repeated.capsProcessedCount == 0)
      #expect(repeated.refreshRequestCount == 0)
    }

    @Test("a resync record routes to the WebSocket transport")
    func resyncRecordRoutesToTransport() async throws {
      let sink = RecordingInputTestSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )
      let client = await ChannelClient.attached(transport: transport)
      await client.feed("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")

      _ = try transport.present(RasterSurface(size: .init(width: 2, height: 1), lines: ["A "]))
      _ = try transport.present(
        SemanticHostFrame(
          sequence: 2,
          raster: RasterSurface(size: .init(width: 2, height: 1), lines: ["B "]),
          semantics: .init(),
          focusedIdentity: nil,
          rasterDamage: .init(textRows: [.init(row: 0)])
        )
      )
      try await transport.drain()

      let resyncClient = await ChannelClient.attached(transport: transport)
      await resyncClient.feed("\u{001E}resync:{\"scope\":\"keyframe\"}\n")

      _ = try transport.present(
        SemanticHostFrame(
          sequence: 3,
          raster: RasterSurface(size: .init(width: 2, height: 1), lines: ["C "]),
          semantics: .init(),
          focusedIdentity: nil,
          rasterDamage: .init(textRows: [.init(row: 0)])
        )
      )
      try await transport.drain()

      let records = await sink.records()
      #expect(records.count == 3)
      #expect(records[1].contains("\"encoding\":\"delta\""))
      #expect(!records[2].contains("\"encoding\":\"delta\""))
      #expect(records[2].contains("\"gen\":3"))
    }

    @Test("a capability declaration refreshes the retained frame as a keyframe")
    func capabilityDeclarationRefreshesRetainedFrame() async throws {
      let sink = RecordingInputTestSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )
      // A refresh before any present has nothing to send: the reconnecting
      // client simply waits for the app's next frame.
      let firstClient = await ChannelClient.attached(transport: transport)
      await firstClient.feed("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
      try await transport.drain()
      #expect(await sink.records().isEmpty)

      _ = try transport.present(
        SemanticHostFrame(
          sequence: 1,
          raster: RasterSurface(size: .init(width: 2, height: 1), lines: ["A "]),
          semantics: .init(),
          focusedIdentity: nil
        )
      )
      try await transport.drain()
      #expect(await sink.records().count == 1)

      // The reconnecting client's declaration re-anchors and then re-sends the
      // retained frame, so its first surface record is a full keyframe in the
      // new epoch rather than nothing at all.
      let reconnected = await ChannelClient.attached(transport: transport)
      await reconnected.feed("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
      try await transport.drain()

      let records = await sink.records()
      #expect(records.count == 2)
      #expect(!records[1].contains("\"encoding\":\"delta\""))
      #expect(records[1].contains("\"gen\":1"))
    }

    @Test("an image resync request retransmits only the named payload")
    func imageResyncRetransmitsOnlyNamedPayload() async throws {
      let sink = RecordingInputTestSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      _ = try transport.present(Self.twoImageFrame(sequence: 1))
      _ = try transport.present(Self.twoImageFrame(sequence: 2))
      try await transport.drain()

      let steadyRecords = await sink.records()
      #expect(steadyRecords.count == 2)
      let initialImages = try Self.decodedImages(in: steadyRecords[0])
      let steadyImages = try Self.decodedImages(in: steadyRecords[1])
      #expect(initialImages.count == 2)
      #expect(steadyImages.count == 2)

      let requestedID = try #require(initialImages[0]["id"] as? String)
      let retainedID = try #require(initialImages[1]["id"] as? String)
      let requestedPayload = try #require(initialImages[0]["dataBase64"] as? String)
      _ = try #require(initialImages[1]["dataBase64"] as? String)
      #expect(requestedID != retainedID)
      #expect(steadyImages[0]["id"] as? String == requestedID)
      #expect(steadyImages[1]["id"] as? String == retainedID)
      #expect(steadyImages[0]["dataBase64"] == nil)
      #expect(steadyImages[1]["dataBase64"] == nil)

      let client = await ChannelClient.attached(transport: transport)
      await client.feed(
        "\u{001E}resync:{\"scope\":\"images\",\"ids\":[\"\(requestedID)\"]}\n"
      )

      _ = try transport.present(Self.twoImageFrame(sequence: 3))
      try await transport.drain()

      let repairedRecords = await sink.records()
      #expect(repairedRecords.count == 3)
      let repairedImages = try Self.decodedImages(in: repairedRecords[2])
      #expect(repairedImages.count == 2)
      #expect(repairedImages[0]["id"] as? String == requestedID)
      #expect(repairedImages[0]["dataBase64"] as? String == requestedPayload)
      #expect(repairedImages[1]["id"] as? String == retainedID)
      #expect(repairedImages[1]["dataBase64"] == nil)
    }

    @Test("key and paste input yield expected input events")
    func keyAndPasteInputYieldExpectedEvents() async throws {
      let client = await ChannelClient.attached()

      await client.feed("\u{001E}key:character:A:1\n\u{001E}paste:hello%20web\n")

      #expect(
        await client.yieldedEvents() == [
          .key(.init(.character("A"), modifiers: [.shift])),
          .paste(.init(content: "hello web")),
        ])
    }

    private static func twoImageFrame(
      sequence: UInt64
    ) -> SemanticHostFrame {
      let firstBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x01]
      let secondBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x02]
      let imageSize = CellSize(width: 1, height: 1)
      return SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(
          size: .init(width: 2, height: 1),
          cells: [[RasterCell(character: " "), RasterCell(character: " ")]],
          imageAttachments: [
            RasterImageAttachment(
              identity: Identity(components: ["root", "first-image"]),
              bounds: CellRect(origin: .zero, size: imageSize),
              source: .data(firstBytes),
              resolvedReference: .embeddedImage(firstBytes),
              pixelSize: .init(width: 1, height: 1)
            ),
            RasterImageAttachment(
              identity: Identity(components: ["root", "second-image"]),
              bounds: CellRect(origin: .init(x: 1, y: 0), size: imageSize),
              source: .data(secondBytes),
              resolvedReference: .embeddedImage(secondBytes),
              pixelSize: .init(width: 1, height: 1)
            ),
          ]
        ),
        semantics: .init(),
        focusedIdentity: nil
      )
    }

    private static func decodedImages(
      in output: String
    ) throws -> [[String: Any]] {
      let prefix = "\u{001E}surface:"
      let line = output.trimmingCharacters(in: .newlines)
      #expect(line.hasPrefix(prefix))
      let json = String(line.dropFirst(prefix.count))
      let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
      let frame = try #require(decoded as? [String: Any])
      return try #require(frame["images"] as? [[String: Any]])
    }
  }

  /// One attached client on a real `WebHostSceneChannel`, stepped deterministically.
  ///
  /// These tests drive the production wiring rather than a hand-built control
  /// handler: a capability declaration has to travel the same channel gate in a
  /// test that it travels in the runner, or the test proves nothing about the path
  /// that ships. Bytes are handed to the reader through its own `process` step
  /// rather than through the client socket, so an assertion runs when the record
  /// has actually been applied instead of after a guessed number of task hops.
  private struct ChannelClient {
    let channel: WebHostSceneChannel
    let reader: WebSocketInputReader
    private let token: UInt64
    private let events: EventRecorder
    // Both halves of the connection have to be retained. Dropping the client
    // continuation ends the receive loop and dropping the returned output stream
    // terminates it — either one detaches the connection immediately.
    private let clientContinuation: AsyncStream<WebHostSocketMessage>.Continuation
    private let output: AsyncStream<WebHostSocketMessage>

    static func attached(
      transport: WebSocketSurfaceTransport? = nil,
      signalReader: InProcessSignalReader? = nil
    ) async -> Self {
      let channel = WebHostSceneChannel()
      var clientContinuation: AsyncStream<WebHostSocketMessage>.Continuation?
      let client = AsyncStream<WebHostSocketMessage> { clientContinuation = $0 }
      let output = await channel.attach(client: client)
      let token = await channel.currentConnectionToken() ?? 0
      let reader =
        if let transport {
          WebSocketInputReader(
            channel: channel,
            transport: transport,
            signalReader: signalReader
          )
        } else {
          WebSocketInputReader(source: channel)
        }
      return Self(
        channel: channel,
        reader: reader,
        token: token,
        events: EventRecorder(),
        clientContinuation: clientContinuation!,
        output: output
      )
    }

    /// Feeds one client chunk and returns once the reader has applied it.
    func feed(
      _ text: String
    ) async {
      await reader.process(
        .bytes(token: token, Array(text.utf8)),
        yielding: events.continuation
      )
    }

    /// Ends the recording and returns every event the reader yielded, in order.
    /// The stream buffers, so iterating after `finish()` completes immediately —
    /// no sleep, no semaphore, no guessed hop count.
    func yieldedEvents() async -> [InputEvent] {
      events.continuation.finish()
      var collected: [InputEvent] = []
      for await event in events.stream {
        collected.append(event)
      }
      return collected
    }

    private final class EventRecorder: Sendable {
      let continuation: AsyncStream<InputEvent>.Continuation
      let stream: AsyncStream<InputEvent>

      init() {
        var continuation: AsyncStream<InputEvent>.Continuation?
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation!
      }
    }
  }

  private actor RecordingInputTestSink: WebHostByteSink {
    private var batches: [String] = []

    func send(_ bytes: [UInt8]) async throws {
      batches.append(String(decoding: bytes, as: UTF8.self))
    }

    func records() -> [String] {
      batches
    }
  }

#endif
