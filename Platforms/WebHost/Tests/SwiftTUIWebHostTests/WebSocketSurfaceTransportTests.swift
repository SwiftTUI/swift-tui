import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUIWebHost

struct WebSocketSurfaceTransportTests {
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
      HostWireCapabilities(maxWebSurfaceVersion: 3, acceptsDeltaFrames: true)
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
    let capabilities = HostWireCapabilities(
      maxWebSurfaceVersion: 3, acceptsDeltaFrames: true)
    transport.declareCapabilities(capabilities)
    try transport.present(Self.steadyFrame(sequence: 1))
    try transport.present(Self.steadyFrame(sequence: 2))

    // A reconnecting client re-declares; its decoder has no baseline, so
    // the stream must restart with a full keyframe.
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

private struct StalledByteSink: WebHostByteSink {
  func send(_: [UInt8]) async throws {
    // Park until the caller cancels: AsyncEvent.wait() is cancellation-aware,
    // so a never-fired event suspends with no poll loop and resumes the
    // instant cancellation arrives.
    await AsyncEvent().wait()
    throw CancellationError()
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
