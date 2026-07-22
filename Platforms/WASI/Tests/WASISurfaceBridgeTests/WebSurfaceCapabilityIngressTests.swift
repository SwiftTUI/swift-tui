import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

/// The `caps:` declaration ingress at the shared input parser, pinned
/// against the canonical cross-repo record fixture the WebSocket client
/// emits. Unknown-command tolerance is asserted alongside because it is the
/// load-bearing half of the pairing contract: a new bundle's `caps:` record
/// against an old server must drop silently, never fail the session.
@Suite
struct WebSurfaceCapabilityIngressTests {
  @Test("the canonical caps record fixture parses to a capabilities message")
  func canonicalCapsFixtureParses() throws {
    // `Fixtures/Transport/web-caps-record.txt` is the cross-repo canonical
    // record: swift-tui-web's client encoder pins its emitted bytes against
    // its mirrored copy, and the coordination root's transport_fixture_sync
    // gate keeps the copies in lockstep — so this parse is the Swift half
    // of the round trip.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("Transport")
      .appendingPathComponent("web-caps-record.txt")
    let fixture = try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: "\\u001E", with: "\u{001E}")

    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(Array(fixture.utf8))

    #expect(parsed.events.isEmpty)
    #expect(
      parsed.controlMessages == [
        .capabilities(
          HostWireCapabilities(maxWebSurfaceVersion: 3, acceptsDeltaFrames: true)
        )
      ]
    )
  }

  @Test("a malformed caps record is dropped and the session keeps defaults")
  func malformedCapsRecordIsDropped() {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(Array("\u{001E}caps:{not json}\n".utf8))

    #expect(parsed.events.isEmpty)
    #expect(parsed.controlMessages.isEmpty)
  }

  @Test("unknown control records are dropped silently")
  func unknownControlRecordsAreDropped() {
    // Load-bearing for forward compatibility: deployed servers must keep
    // tolerating record types they have never heard of, or a newer bundle
    // could never safely declare anything.
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      Array("\u{001E}futureRecord:{\"x\":1}\n\u{001E}key:return:0\n".utf8)
    )

    #expect(parsed.controlMessages.isEmpty)
    #expect(parsed.events == [.key(.init(.return))])
  }

  @Test("the WASI transport stores threaded capabilities without reading them")
  func transportStoresThreadedCapabilities() {
    let declared = HostWireCapabilities(maxWebSurfaceVersion: 3, acceptsDeltaFrames: true)
    let transport = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 1),
      renderStyle: .init(appearance: .fallback),
      wireCapabilities: declared
    )
    #expect(transport.wireCapabilities == declared)

    let undeclared = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 1),
      renderStyle: .init(appearance: .fallback)
    )
    #expect(undeclared.wireCapabilities == HostWireCapabilities())
  }
}
