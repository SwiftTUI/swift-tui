import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import SwiftTUIWebHost

struct WebSocketSurfaceTransportTests {
  @Test("semantic present emits a v2 web-surface frame with accessibilityTree")
  func semanticPresentEmitsV2FrameWithAccessibilityTree() async throws {
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
      focusedIdentity: button
    )

    let record = try #require(await sink.strings().first)
    let frame = try decodedSurfaceFrame(record)
    #expect(frame["version"] as? Int == 2)
    let tree = try #require(frame["accessibilityTree"] as? [[String: Any]])
    #expect(tree.first?["id"] as? String == "root/button")
    #expect(tree.first?["isFocused"] as? Bool == true)
    #expect(metrics.bytesWritten == record.utf8.count)
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
