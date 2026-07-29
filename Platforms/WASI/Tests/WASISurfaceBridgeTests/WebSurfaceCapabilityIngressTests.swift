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
  @Test("resync request parser accepts keyframe and image scopes")
  func resyncRequestParserAcceptsKnownScopes() {
    #expect(
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"keyframe"}"#)
        == HostWireResyncRequest(scope: .keyframe)
    )
    #expect(
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","ids":["first","second"]}"#)
        == HostWireResyncRequest(scope: .images(["first", "second"]))
    )
    #expect(
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"images"}"#)
        == HostWireResyncRequest(scope: .images([]))
    )
    #expect(
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","ids":[]}"#)
        == HostWireResyncRequest(scope: .images([]))
    )
    #expect(
      HostWireResyncRequest.fromRequestJSON(
        #"{"scope":"images","ids":["\u0061","\uD83D\uDE00"]}"#
      ) == HostWireResyncRequest(scope: .images(["a", "😀"]))
    )
  }

  @Test("resync request parser rejects malformed and unknown scopes")
  func resyncRequestParserRejectsMalformedRequests() {
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"future"}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","ids":[1]}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"keyframe""#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","x":[}}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","x":{]}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","x":[garbage]}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","x":[1,,2]}"#) == nil)
    #expect(HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","x":{"a" 1}}"#) == nil)
    #expect(
      HostWireResyncRequest.fromRequestJSON(
        "{\"scope\":\"images\",\"ids\":[\"raw\ncontrol\"]}"
      ) == nil
    )
  }

  @Test("resync request parser rejects excessive unknown-value nesting")
  func resyncRequestParserRejectsExcessiveNesting() {
    let nestedValue =
      String(repeating: "[", count: 129)
      + "null"
      + String(repeating: "]", count: 129)
    let request = #"{"scope":"images","future":"# + nestedValue + "}"

    #expect(HostWireResyncRequest.fromRequestJSON(request) == nil)
  }

  @Test("shared input parser emits resync control messages")
  func sharedInputParserEmitsResyncControlMessages() {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      Array(
        ("\u{001E}resync:{\"scope\":\"keyframe\"}\n"
          + "\u{001E}resync:{\"scope\":\"images\",\"ids\":[\"image-a\"]}\n").utf8
      )
    )

    #expect(parsed.events.isEmpty)
    #expect(
      parsed.controlMessages == [
        .resync(.init(scope: .keyframe)),
        .resync(.init(scope: .images(["image-a"]))),
      ]
    )
  }

  @Test("resync requests invalidate only their requested encoder state")
  func resyncRequestsMutateEncodingState() {
    var state = HostWireEncodingState(
      deltaEnabled: true,
      knownImageIDs: ["first", "second"],
      hasBaseline: true,
      baselineSize: .init(width: 2, height: 1),
      epochID: 7
    )

    state.requestResync(.init(scope: .images(["first"])))
    #expect(state.hasBaseline)
    #expect(state.knownImageIDs == ["second"])
    #expect(state.epochID == 7)

    let beforeMalformedImageIDs = state.knownImageIDs
    let beforeMalformedBaseline = state.hasBaseline
    let beforeMalformedGeneration = state.recordsEncoded
    if let malformed = HostWireResyncRequest.fromRequestJSON(
      #"{"scope":"images","x":[}}"#
    ) {
      state.requestResync(malformed)
    }
    #expect(state.knownImageIDs == beforeMalformedImageIDs)
    #expect(state.hasBaseline == beforeMalformedBaseline)
    #expect(state.recordsEncoded == beforeMalformedGeneration)

    state.requestResync(.init(scope: .images([])))
    #expect(state.knownImageIDs.isEmpty)

    state.requestResync(.init(scope: .keyframe))
    #expect(!state.hasBaseline)
    #expect(state.baselineSize == .init(width: 2, height: 1))
    #expect(state.epochID == 7)
  }

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
        .capabilities(HostWireCapabilities(acceptsDeltaFrames: true))
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

  @Test("the WASI transport carries the capabilities it was constructed with")
  func transportCarriesThreadedCapabilities() {
    // This assertion used to be titled "stores threaded capabilities without
    // reading them" — it certified the defect, because not reading them is
    // exactly how a separately-resolved delta flag contradicted the
    // declaration. What the transport *does* with them is now pinned
    // end-to-end by `WebSurfaceTransportTests`, against emitted bytes.
    let declared = HostWireCapabilities(acceptsDeltaFrames: true)
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
