import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import SwiftTUIWebHost

struct WebSocketInputReaderTests {
  @Test("resize and style input update the transport")
  func resizeAndStyleInputUpdateTransport() async throws {
    let source = InMemoryByteSource()
    let sink = RecordingInputTestSink()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 1, height: 1),
      sink: sink
    )
    let reader = WebSocketInputReader(source: source, transport: transport)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: try! .hex("#102030"),
        backgroundColor: try! .hex("#405060"),
        tintColor: try! .hex("#708090"),
        source: .override
      )
    )
    let encodedStyle = try #require(TerminalRenderStyleCodec.encodeBase64(style))

    await source.yield("\u{001E}resize:80:24:9:18\n\u{001E}style:\(encodedStyle)\n")
    await source.finish()

    #expect(await iterator.next() == nil)
    #expect(transport.surfaceSize == .init(width: 80, height: 24))
    #expect(transport.appearance == style.appearance)
    #expect(transport.pointerInputCapabilities.precision.isSubCell)
  }

  @Test("a caps record declares wire capabilities on the transport")
  func capsRecordDeclaresWireCapabilities() async throws {
    let source = InMemoryByteSource()
    let sink = RecordingInputTestSink()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 1, height: 1),
      sink: sink
    )
    let reader = WebSocketInputReader(source: source, transport: transport)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()

    #expect(transport.wireCapabilities == HostWireCapabilities())

    await source.yield(
      "\u{001E}caps:{\"acceptsDeltaFrames\":true}\n"
    )
    await source.finish()

    #expect(await iterator.next() == nil)
    #expect(
      transport.wireCapabilities == HostWireCapabilities(acceptsDeltaFrames: true)
    )
  }

  @Test("a resync record routes to the WebSocket transport")
  func resyncRecordRoutesToTransport() async throws {
    let source = InMemoryByteSource()
    let sink = RecordingInputTestSink()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 2, height: 1),
      sink: sink
    )
    let reader = WebSocketInputReader(source: source, transport: transport)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()

    await source.yield("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n")
    await source.finish()
    #expect(await iterator.next() == nil)

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

    let resyncSource = InMemoryByteSource()
    let resyncReader = WebSocketInputReader(source: resyncSource, transport: transport)
    let resyncEvents = resyncReader.inputEvents()
    var resyncIterator = resyncEvents.makeAsyncIterator()
    await resyncSource.yield("\u{001E}resync:{\"scope\":\"keyframe\"}\n")
    await resyncSource.finish()
    #expect(await resyncIterator.next() == nil)

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

    let source = InMemoryByteSource()
    let reader = WebSocketInputReader(source: source, transport: transport)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()
    await source.yield(
      "\u{001E}resync:{\"scope\":\"images\",\"ids\":[\"\(requestedID)\"]}\n"
    )
    await source.finish()
    #expect(await iterator.next() == nil)

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
    let source = InMemoryByteSource()
    let reader = WebSocketInputReader(source: source)
    let events = reader.inputEvents()
    var iterator = events.makeAsyncIterator()

    await source.yield("\u{001E}key:character:A:1\n\u{001E}paste:hello%20web\n")

    #expect(await iterator.next() == .key(.init(.character("A"), modifiers: [.shift])))
    #expect(await iterator.next() == .paste(.init(content: "hello web")))

    await source.finish()
    #expect(await iterator.next() == nil)
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

private actor InMemoryByteSource: WebHostByteSource {
  nonisolated let stream: AsyncStream<[UInt8]>
  private let continuation: AsyncStream<[UInt8]>.Continuation

  init() {
    var continuation: AsyncStream<[UInt8]>.Continuation?
    stream = AsyncStream { continuation = $0 }
    self.continuation = continuation!
  }

  nonisolated func chunks() -> AsyncStream<[UInt8]> {
    stream
  }

  func yield(
    _ text: String
  ) {
    continuation.yield(Array(text.utf8))
  }

  func finish() {
    continuation.finish()
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
