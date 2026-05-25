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
