import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import SwiftTUIWebHost

struct WebSocketSurfaceTransportTests {
  @Test("damage-aware semantic present emits a v2 web-surface frame with accessibilityTree")
  func damageAwareSemanticPresentEmitsV2FrameWithAccessibilityTree() async throws {
    let sink = RecordingByteSink()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 2, height: 1),
      sink: sink
    )
    let root = Identity(components: ["root"])
    let button = root.child("button")

    let metrics = try transport.present(
      Self.basicSurface("OK"),
      semanticSnapshot: SemanticSnapshot(
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
      focusedIdentity: button,
      damage: nil
    )

    let record = try #require(await sink.strings().first)
    let frame = try decodedSurfaceFrame(record)
    #expect(frame["version"] as? Int == 2)
    let tree = try #require(frame["accessibilityTree"] as? [[String: Any]])
    #expect(tree.first?["id"] as? String == "root/button")
    #expect(tree.first?["isFocused"] as? Bool == true)
    #expect(metrics.bytesWritten == record.utf8.count)
  }

  @Test("damage-aware semantic present emits damage and partial repaint metrics")
  func damageAwareSemanticPresentEmitsDamageAndPartialMetrics() async throws {
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

    let damageAwareTransport: any DamageAwareSemanticPresentationSurface = transport
    let metrics = try damageAwareTransport.present(
      Self.basicSurface("OK"),
      semanticSnapshot: SemanticSnapshot(),
      focusedIdentity: nil,
      damage: damage
    )

    let record = try #require(await sink.strings().first)
    let frame = try decodedSurfaceFrame(record)
    let decodedDamage = try #require(frame["damage"] as? [String: Any])
    let textRows = try #require(decodedDamage["textRows"] as? [[Any]])
    let textRow = try #require(textRows.first)

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

    let records = await sink.strings()
    #expect(records.count == 2)
    #expect(records[0].contains("\"A\""))
    #expect(records[1].contains("\"B\""))
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
