// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises the
// WebHost server stack, whose modules build empty on Windows
// (whole-file-guarded).
#if !os(Windows)

  import Foundation
  @_spi(Runners) import SwiftTUI
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @testable import SwiftTUIWebHost

  struct WebSocketSurfaceTransportTests {
    @Test("slow progressing sockets stay bounded and reconnect with the latest full image frame")
    func slowProgressOverflowAndReconnect() async throws {
      let channel = WebHostSceneChannel()
      let disconnected = AsyncEvent()
      let client = AsyncStream<WebHostSocketMessage>.makeStream()
      let (output, connectionToken) = await channel.attachSocket(client: client.stream) {
        disconnected.fire()
      }
      let token = try #require(connectionToken)
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1), sink: channel)
      let caps = HostWireCapabilities(acceptsDeltaFrames: true)
      await channel.applyCapabilities(
        token: token,
        reanchor: { transport.declareCapabilities(caps, connectionToken: token) },
        requestRefresh: {})
      var iterator = output.makeAsyncIterator()
      try transport.present(Self.steadyFrame(sequence: 1))
      var current = try await nextBytes(&iterator)
      var lastGeneration = try #require(
        try decodedSurfaceFrame(String(decoding: current, as: UTF8.self))["gen"] as? Int)

      // The consumer completes one write for every two new frames. Every send
      // makes progress, so a per-send timeout cannot bound this imbalance.
      for step in 0..<16 {
        try transport.present(Self.steadyFrame(sequence: UInt64(2 + step * 2)))
        try transport.present(Self.steadyFrame(sequence: UInt64(3 + step * 2)))
        #expect(transport.outboundBacklog.records <= WebHostOutboundBudget.recordLimit)
        #expect(transport.outboundBacklog.bytes <= WebHostOutboundBudget.byteLimit)
        await channel.completeOutput(token: token, byteCount: current.count, succeeded: true)
        current = try await nextBytes(&iterator)
        let frame = try decodedSurfaceFrame(String(decoding: current, as: UTF8.self))
        #expect(frame["baselineGen"] as? Int == lastGeneration)
        lastGeneration = try #require(frame["gen"] as? Int)
      }
      for sequence in 34...200 {
        try transport.present(Self.imageFrame(sequence: UInt64(sequence)))
        #expect(transport.outboundBacklog.records <= WebHostOutboundBudget.recordLimit)
        #expect(transport.outboundBacklog.bytes <= WebHostOutboundBudget.byteLimit)
      }
      await disconnected.wait()
      await #expect(throws: WebHostByteSinkError.outboundBacklogExceeded) {
        try await transport.drain()
      }
      #expect(transport.outboundBacklog.records == 0)
      #expect(transport.outboundBacklog.bytes == 0)
      #expect(await channel.currentConnectionToken() == nil)

      let nextClient = AsyncStream<WebHostSocketMessage>.makeStream()
      let (nextOutput, nextConnectionToken) = await channel.attachSocket(client: nextClient.stream)
      {}
      let nextToken = try #require(nextConnectionToken)
      await channel.applyCapabilities(
        token: nextToken,
        reanchor: { transport.declareCapabilities(caps, connectionToken: nextToken) },
        requestRefresh: { transport.requestSurfaceRefresh() })
      var nextIterator = nextOutput.makeAsyncIterator()
      let refreshed = try await nextBytes(&nextIterator)
      let record = String(decoding: refreshed, as: UTF8.self)
      let frame = try decodedSurfaceFrame(record)
      #expect(frame["encoding"] == nil)
      #expect(frame["sequence"] as? Int == 200)
      #expect(record.contains("dataBase64"))
      var actual = frame
      var expected = try decodedSurfaceFrame(
        WebSurfaceFrameEncoder.encode(Self.imageFrame(sequence: 200)))
      for key in ["epoch", "gen"] {
        actual.removeValue(forKey: key)
        expected.removeValue(forKey: key)
      }
      #expect(NSDictionary(dictionary: actual).isEqual(to: expected))
      // Old completions and failures must not detach or acknowledge the new socket.
      await channel.completeOutput(token: token, byteCount: current.count, succeeded: false)
      await channel.disconnect(connectionToken: token)
      #expect(await channel.currentConnectionToken() == nextToken)
      await channel.completeOutput(token: nextToken, byteCount: refreshed.count, succeeded: true)
      try await transport.drain()
      await channel.shutdown()
      client.continuation.finish()
      nextClient.continuation.finish()
    }

    @MainActor
    @Test("slow sockets preserve clipboard, issue and announcement records in FIFO order")
    func reliableRecordsSurviveBackpressure() async throws {
      let channel = WebHostSceneChannel()
      let client = AsyncStream<WebHostSocketMessage>.makeStream()
      let (output, connectionToken) = await channel.attachSocket(client: client.stream) {}
      let token = try #require(connectionToken)
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1), sink: channel)
      await channel.applyCapabilities(
        token: token,
        reanchor: { transport.declareCapabilities(HostWireCapabilities(), connectionToken: token) },
        requestRefresh: {})
      try transport.present(Self.steadyFrame(sequence: 1))
      #expect(try transport.writeClipboard("keep clipboard"))
      try transport.notifyRuntimeIssue(
        .init(severity: .warning, code: "keep", message: "keep issue"))
      var announced = Self.steadyFrame(sequence: 2)
      announced.semantics.accessibilityAnnouncements = [.init(message: "keep announcement")]
      try transport.present(announced)
      try transport.present(Self.steadyFrame(sequence: 3))
      var iterator = output.makeAsyncIterator()
      var records: [String] = []
      for _ in 0..<5 {
        let bytes = try await nextBytes(&iterator)
        records.append(String(decoding: bytes, as: UTF8.self))
        await channel.completeOutput(token: token, byteCount: bytes.count, succeeded: true)
      }
      try await transport.drain()
      #expect(records[1].hasPrefix("\u{001E}clipboard:"))
      #expect(records[2].hasPrefix("\u{001E}runtimeIssue:"))
      #expect(records[3].contains("keep announcement"))
      #expect(!records[4].contains("keep announcement"))
      await channel.shutdown()
      client.continuation.finish()
    }

    @MainActor
    @Test("oversized reliable records fail explicitly without entering the byte queue")
    func oversizedRecordFailsAdmission() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(surfaceSize: .init(width: 2, height: 1), sink: sink)
      #expect(
        try !transport.writeClipboard(
          String(repeating: "x", count: WebHostOutboundBudget.byteLimit)))
      #expect(transport.outboundBacklog.bytes == 0)
      await #expect(throws: WebHostByteSinkError.outboundBacklogExceeded) {
        try await transport.drain()
      }
      #expect(await sink.strings().isEmpty)
    }

    @MainActor
    @Test("a successful control send cannot hide the need to reset a failed delta baseline")
    func controlSuccessAfterFailedFrameStillRekeys() async throws {
      let sink = FailOnceByteSink()
      let transport = WebSocketSurfaceTransport(surfaceSize: .init(width: 2, height: 1), sink: sink)
      transport.declareCapabilities(HostWireCapabilities(acceptsDeltaFrames: true))
      try transport.present(Self.imageFrame(sequence: 1))
      await #expect(throws: WebHostByteSinkError.self) { try await transport.drain() }
      #expect(try transport.writeClipboard("control after failed frame"))
      try await transport.drain()
      try transport.present(Self.imageFrame(sequence: 2))
      try await transport.drain()
      let records = await sink.strings()
      let record = try #require(records.last)
      let frame = try decodedSurfaceFrame(record)
      #expect(frame["encoding"] == nil)
      #expect(frame["gen"] as? Int == 1)
      #expect(record.contains("dataBase64"))
    }

    private func nextBytes(
      _ iterator: inout AsyncStream<WebHostSocketMessage>.Iterator,
      isolation: isolated (any Actor)? = #isolation
    ) async throws -> [UInt8] {
      guard case .data(let bytes) = try #require(await iterator.next(isolation: isolation)) else {
        throw WebHostByteSinkError.sendDidNotComplete
      }
      return bytes
    }

    @MainActor
    @Test("a capability declaration preserves controls that have not reached the socket")
    func capabilityDeclarationPreservesUnsentControls() async throws {
      let sink = PausingByteSink()
      let transport = WebSocketSurfaceTransport(surfaceSize: .init(width: 2, height: 1), sink: sink)
      try transport.present(Self.steadyFrame(sequence: 1))
      await sink.started.wait()
      #expect(try transport.writeClipboard("queued before capabilities"))
      transport.declareCapabilities(HostWireCapabilities(), connectionToken: 1)
      sink.release.fire()
      try await transport.drain()
      let records = await sink.strings()
      #expect(records.count == 2)
      #expect(records.last?.contains("queued before capabilities") == true)
    }

    @Test("semantic host-frame present emits a v2 web-surface frame with accessibilityTree")
    func semanticHostFramePresentEmitsV2FrameWithAccessibilityTree() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )
      let root = Identity(components: ["root"])
      let button = root.child("button")

      let metrics = try transport.present(
        SemanticHostFrame(
          sequence: 21,
          raster: Self.basicSurface("OK"),
          semantics: SemanticSnapshot(
            accessibilityNodes: [
              AccessibilityNode(
                identity: button,
                parentIdentity: root,
                rect: .init(origin: .zero, size: .init(width: 2, height: 1)),
                role: .button,
                label: "Save"
              )
            ]
          ),
          focusedIdentity: button
        ),
      )

      try await transport.drain()
      let record = try #require(await sink.strings().first)
      let frame = try decodedSurfaceFrame(record)
      #expect(frame["version"] as? Int == 2)
      #expect(frame["sequence"] as? Int == 21)
      let tree = try #require(frame["accessibilityTree"] as? [[String: Any]])
      #expect(tree.first?["id"] as? String == "root/button")
      #expect(tree.first?["isFocused"] as? Bool == true)
      #expect(metrics.bytesWritten == record.utf8.count)
    }

    @Test("a capability declaration re-anchors image transmission for the new client")
    func capabilityDeclarationReanchorsImageTransmission() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.present(Self.imageFrame(sequence: 1))
      try transport.present(Self.imageFrame(sequence: 2))
      try await transport.drain()
      var records = await sink.strings()
      #expect(records.count == 2)
      // First transmission carries the payload; the repeat is deduplicated by
      // the persistent image-ID set.
      #expect(records[0].contains("dataBase64"))
      #expect(!records[1].contains("dataBase64"))

      // A capability declaration marks a fresh client connection (the browser
      // client sends caps: exactly once, first, per socket). The reconnected
      // client's decoder starts empty, so the transport must re-anchor its
      // cross-connection encoding state and re-transmit image payloads — the
      // F55 reload defect.
      transport.declareCapabilities(HostWireCapabilities())
      try transport.present(Self.imageFrame(sequence: 3))
      try await transport.drain()
      records = await sink.strings()
      #expect(records.count == 3)
      #expect(records[2].contains("dataBase64"))
    }

    @Test("declared v3+delta clients receive delta records after the keyframe")
    func negotiatedDeltaEmitsDeltaRecordsAfterKeyframe() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )
      transport.declareCapabilities(
        HostWireCapabilities(acceptsDeltaFrames: true)
      )

      try transport.present(Self.steadyFrame(sequence: 1))
      try transport.present(Self.steadyFrame(sequence: 2))
      try await transport.drain()
      let records = await sink.strings()
      #expect(records.count == 2)
      // The first frame after the declaration is the keyframe; the steady
      // frame with narrow damage ships as a v3 delta record — the first
      // emission behavior negotiation unlocks.
      let keyframe = try decodedSurfaceFrame(records[0])
      #expect(keyframe["version"] as? Int == 2)
      #expect(keyframe["encoding"] == nil)
      let delta = try decodedSurfaceFrame(records[1])
      #expect(delta["version"] as? Int == 3)
      #expect(delta["encoding"] as? String == "delta")
      #expect(delta["deltaRows"] != nil)
    }

    @Test("undeclared clients keep receiving full frames")
    func undeclaredClientsKeepFullFrames() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.present(Self.steadyFrame(sequence: 1))
      try transport.present(Self.steadyFrame(sequence: 2))
      try await transport.drain()
      let records = await sink.strings()
      #expect(records.count == 2)
      for record in records {
        let frame = try decodedSurfaceFrame(record)
        #expect(frame["version"] as? Int == 2)
        #expect(frame["encoding"] == nil)
      }
    }

    @Test("a redeclaration re-keyframes a delta stream")
    func redeclarationRekeyframesDeltaStream() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )
      let capabilities = HostWireCapabilities(acceptsDeltaFrames: true)
      transport.declareCapabilities(capabilities)
      try transport.present(Self.steadyFrame(sequence: 1))
      try transport.present(Self.steadyFrame(sequence: 2))

      // A reconnecting client re-declares; its decoder has no baseline, so
      // the stream must restart with a full keyframe.
      try await transport.drain()
      transport.declareCapabilities(capabilities)
      try transport.present(Self.steadyFrame(sequence: 3))
      try await transport.drain()
      let records = await sink.strings()
      #expect(records.count == 3)
      let rekeyframe = try decodedSurfaceFrame(records[2])
      #expect(rekeyframe["version"] as? Int == 2)
      #expect(rekeyframe["encoding"] == nil)
    }

    private static func steadyFrame(
      sequence: UInt64
    ) -> SemanticHostFrame {
      SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(
          size: CellSize(width: 2, height: 1),
          cells: [[RasterCell(character: "s"), RasterCell(character: " ")]]
        ),
        semantics: SemanticSnapshot(),
        focusedIdentity: nil,
        rasterDamage: PresentationDamage(
          textRows: [PresentationDamage.TextRow(row: 0, columnRanges: [0..<1])]
        )
      )
    }

    private static func imageFrame(
      sequence: UInt64
    ) -> SemanticHostFrame {
      let pngBytes: [UInt8] = Array(
        Data(
          base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAEElEQVR4AQEFAPr/AP8AAP8FAAH/+lyI0QAAAABJRU5ErkJggg=="
        )!
      )
      return SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(
          size: CellSize(width: 2, height: 1),
          cells: [[RasterCell(character: "i"), RasterCell(character: " ")]],
          imageAttachments: [
            RasterImageAttachment(
              identity: Identity(components: ["root", "image"]),
              bounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
              source: .data(pngBytes),
              resolvedReference: .embeddedImage(pngBytes),
              pixelSize: PixelSize(width: 1, height: 1)
            )
          ]
        ),
        semantics: SemanticSnapshot(),
        focusedIdentity: nil
      )
    }

    @Test("semantic host-frame present emits damage and partial repaint metrics")
    func semanticHostFramePresentEmitsDamageAndPartialMetrics() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 2),
        sink: sink
      )
      let damage = PresentationDamage(
        textRows: [
          .init(row: 1, columnRanges: [0..<1])
        ]
      )

      let hostFrameSurface: any SemanticHostFramePresentationSurface = transport
      let metrics = try hostFrameSurface.present(
        SemanticHostFrame(
          sequence: 22,
          raster: Self.basicSurface("OK"),
          semantics: SemanticSnapshot(),
          focusedIdentity: nil,
          rasterDamage: damage
        )
      )

      try await transport.drain()
      let record = try #require(await sink.strings().first)
      let frame = try decodedSurfaceFrame(record)
      #expect(frame["version"] as? Int == 2)
      #expect(frame["sequence"] as? Int == 22)
      let decodedDamage = try #require(frame["damage"] as? [String: Any])
      let textRows = try #require(decodedDamage["textRows"] as? [[Any]])
      let textRow = try #require(textRows.first)

      #expect(decodedDamage["requiresFullTextRepaint"] as? Bool == false)
      #expect(decodedDamage["requiresFullGraphicsReplay"] as? Bool == false)
      #expect(textRow.first as? Int == 1)
      #expect(textRow.dropFirst().first as? [[Int]] == [[0, 1]])
      #expect(metrics.linesTouched == 1)
      #expect(metrics.cellsChanged == 1)
      #expect(metrics.strategy == .incremental)
    }

    @Test("sink backpressure preserves present record order")
    func sinkBackpressurePreservesPresentRecordOrder() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.present(Self.basicSurface("AA"))
      try transport.present(Self.basicSurface("BB"))

      try await transport.drain()
      let records = await sink.strings()
      #expect(records.count == 2)
      #expect(records[0].contains("\"A\""))
      #expect(records[1].contains("\"B\""))
    }

    @Test("sink backpressure has a bounded failure path")
    func sinkBackpressureTimesOut() async throws {
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: StalledByteSink(),
        sendTimeoutNanoseconds: 10_000_000
      )

      try transport.present(Self.basicSurface("AA"))
      await #expect(throws: WebHostByteSinkError.self) {
        try await transport.drain()
      }
    }

    @Test("a send failure is connection-scoped: the next present flows and clears the error")
    func sendFailureRecoversOnNextPresent() async throws {
      let sink = FailOnceByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.present(Self.basicSurface("AA"))
      await #expect(throws: WebHostByteSinkError.self) {
        try await transport.drain()
      }

      // The failed epoch is dropped; the next present must be accepted (the
      // old latch made this throw), delivered, and its success must clear the
      // retained error so this drain no longer throws.
      try transport.present(Self.basicSurface("BB"))
      try await transport.drain()

      let records = await sink.strings()
      #expect(records.count == 1)
      #expect(records[0].contains("\"B\""))
    }

    @Test("the pump keeps attempting sends after failures instead of latching")
    func pumpKeepsAttemptingAfterFailures() async throws {
      let sink = AlwaysFailingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.present(Self.basicSurface("AA"))
      await #expect(throws: WebHostByteSinkError.self) {
        try await transport.drain()
      }
      try transport.present(Self.basicSurface("BB"))
      await #expect(throws: WebHostByteSinkError.self) {
        try await transport.drain()
      }

      // The old latch skipped every batch after the first failure; each present
      // must reach the sink as a fresh attempt.
      #expect(await sink.attemptCount() == 2)
    }

    @MainActor
    @Test("transport sends typed clipboard records")
    func transportSendsTypedClipboardRecords() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.writeClipboard("copy \"this\"")

      try await transport.drain()
      #expect(await sink.strings() == ["\u{001E}clipboard:{\"text\":\"copy \\\"this\\\"\"}\n"])
    }

    @Test("transport sends typed runtime issue records")
    func transportSendsTypedRuntimeIssueRecords() async throws {
      let sink = RecordingByteSink()
      let transport = WebSocketSurfaceTransport(
        surfaceSize: .init(width: 2, height: 1),
        sink: sink
      )

      try transport.notifyRuntimeIssue(
        RuntimeIssue(
          severity: .warning,
          code: "toolbar.unhostedItems",
          message: "Toolbar item was not rendered",
          identity: Identity(components: ["root", "body"]),
          source: ".toolbarItem(...)"
        )
      )

      try await transport.drain()
      let record = try #require(await sink.strings().first)
      #expect(record.hasPrefix("\u{001E}runtimeIssue:"))
      #expect(record.contains("\"code\":\"toolbar.unhostedItems\""))
      #expect(record.contains("\"identity\":\"root/body\""))
    }

    private static func basicSurface(
      _ text: String
    ) -> RasterSurface {
      RasterSurface(
        size: .init(width: text.count, height: 1),
        lines: [text]
      )
    }
  }

  private actor RecordingByteSink: WebHostByteSink {
    private var sent: [[UInt8]] = []

    func send(_ bytes: [UInt8]) async throws {
      sent.append(bytes)
    }

    func strings() -> [String] {
      sent.map { String(decoding: $0, as: UTF8.self) }
    }
  }

  private actor PausingByteSink: WebHostByteSink {
    nonisolated let started = AsyncEvent()
    nonisolated let release = AsyncEvent()
    private var sent: [String] = []

    func send(_ bytes: [UInt8]) async throws {
      started.fire()
      await release.wait()
      try Task.checkCancellation()
      sent.append(String(decoding: bytes, as: UTF8.self))
    }

    func strings() -> [String] { sent }
  }

  private struct StalledByteSink: WebHostByteSink {
    func send(_: [UInt8]) async throws {
      // Park until the caller cancels: AsyncEvent.wait() is cancellation-aware,
      // so a never-fired event suspends with no poll loop and resumes the
      // instant cancellation arrives.
      await AsyncEvent().wait()
      throw CancellationError()
    }
  }

  private actor FailOnceByteSink: WebHostByteSink {
    private var sent: [[UInt8]] = []
    private var didFail = false

    func send(_ bytes: [UInt8]) async throws {
      guard didFail else {
        didFail = true
        throw WebHostByteSinkError.sendFailed("injected failure")
      }
      sent.append(bytes)
    }

    func strings() -> [String] {
      sent.map { String(decoding: $0, as: UTF8.self) }
    }
  }

  private actor AlwaysFailingByteSink: WebHostByteSink {
    private var attempts = 0

    func send(_: [UInt8]) async throws {
      attempts += 1
      throw WebHostByteSinkError.sendFailed("injected failure")
    }

    func attemptCount() -> Int {
      attempts
    }
  }

  private func decodedSurfaceFrame(
    _ output: String
  ) throws -> [String: Any] {
    let prefix = "\u{001E}surface:"
    let line = output.trimmingCharacters(in: .newlines)
    #expect(line.hasPrefix(prefix))
    let json = String(line.dropFirst(prefix.count))
    let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try #require(decoded as? [String: Any])
  }

#endif
