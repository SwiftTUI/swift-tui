import Testing

@testable import SwiftTUIRuntime

/// The absence-means-today contract for host capability declarations: the
/// defaults reproduce deployed-decoder reality, and the declaration parser
/// is tolerant exactly where the wire-evolution policy needs it (unknown
/// keys skipped, malformed payloads rejected whole so callers keep the
/// defaults).
@Suite
struct HostWireCapabilitiesTests {
  @Test("defaults reproduce today's deployed-decoder contract")
  func defaultsReproduceTodaysContract() {
    let defaults = HostWireCapabilities()
    #expect(defaults.maxWebSurfaceVersion == 2)
    #expect(!defaults.acceptsDeltaFrames)
    #expect(!defaults.supportsResync)
  }

  @Test("a full declaration parses every field")
  func fullDeclarationParses() {
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"maxWebSurfaceVersion":3,"acceptsDeltaFrames":true,\
      "supportsResync":true,"maxAndroidSchemaVersion":3}
      """
    )
    // maxAndroidSchemaVersion retired with the legacy keyed-JSON wire; old
    // declarations still carrying it are skipped as an unknown key.
    #expect(
      parsed
        == HostWireCapabilities(
          maxWebSurfaceVersion: 3,
          acceptsDeltaFrames: true,
          supportsResync: true
        )
    )
  }

  @Test("an empty declaration keeps the defaults")
  func emptyDeclarationKeepsDefaults() {
    #expect(HostWireCapabilities.fromDeclarationJSON("{}") == HostWireCapabilities())
    #expect(HostWireCapabilities.fromDeclarationJSON(" { } ") == HostWireCapabilities())
  }

  @Test("unknown keys are skipped, including nested containers")
  func unknownKeysAreSkipped() {
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"renderer":"dom","budget":1.5,"nested":{"a":[1,2,{"b":"}"}]},\
      "flags":null,"acceptsDeltaFrames":true}
      """
    )
    #expect(parsed == HostWireCapabilities(acceptsDeltaFrames: true))
  }

  @Test("mistyped known keys are skipped rather than failing the declaration")
  func mistypedKnownKeysAreSkipped() {
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"maxWebSurfaceVersion":"three","acceptsDeltaFrames":true}
      """
    )
    #expect(parsed == HostWireCapabilities(acceptsDeltaFrames: true))
  }

  @Test("malformed declarations are rejected whole")
  func malformedDeclarationsAreRejected() {
    for payload in [
      "", "3", "[]", "{", "{\"acceptsDeltaFrames\":true",
      "{\"acceptsDeltaFrames\" true}", "{}trailing",
      "{\"nested\":{\"unbalanced\":true}",
    ] {
      #expect(
        HostWireCapabilities.fromDeclarationJSON(payload) == nil,
        "expected rejection for payload: \(payload)"
      )
    }
  }
}
