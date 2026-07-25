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
    #expect(!HostWireCapabilities().acceptsDeltaFrames)
  }

  @Test("a full declaration parses every field")
  func fullDeclarationParses() {
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"acceptsDeltaFrames":true}
      """
    )
    #expect(parsed == HostWireCapabilities(acceptsDeltaFrames: true))
  }

  @Test("retired keys are skipped, so clients still sending them are unaffected")
  func retiredKeysAreSkipped() {
    // The tolerance that lets keys arrive early also lets them leave late.
    // `maxAndroidSchemaVersion` retired with the legacy keyed-JSON wire;
    // `maxWebSurfaceVersion` and `supportsResync` retired when capabilities
    // became named feature bits. A client emitting any of them parses
    // exactly as if it had emitted none.
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"maxWebSurfaceVersion":3,"acceptsDeltaFrames":true,\
      "supportsResync":true,"maxAndroidSchemaVersion":3}
      """
    )
    #expect(parsed == HostWireCapabilities(acceptsDeltaFrames: true))
  }

  @Test("a retired version ceiling cannot suppress a declared capability")
  func retiredCeilingDoesNotSuppressDeclaredCapability() {
    // The shape of the defect this collapse removed: a host declaring delta
    // acceptance under a v2 ceiling was a contradiction two fields could
    // express and each transport resolved for itself. One bit cannot
    // contradict itself, and the ceiling is now inert.
    let parsed = HostWireCapabilities.fromDeclarationJSON(
      """
      {"maxWebSurfaceVersion":2,"acceptsDeltaFrames":true}
      """
    )
    #expect(parsed == HostWireCapabilities(acceptsDeltaFrames: true))
    #expect(parsed?.negotiatedEncodingState().deltaEnabled == true)
  }

  @Test("the negotiated encoding state derives from the declaration alone")
  func negotiatedEncodingStateDerivesFromDeclaration() {
    #expect(!HostWireCapabilities().negotiatedEncodingState().deltaEnabled)
    #expect(
      HostWireCapabilities(acceptsDeltaFrames: true)
        .negotiatedEncodingState().deltaEnabled
    )
  }

  @Test("negotiating always yields a fresh epoch")
  func negotiatingYieldsFreshEpoch() {
    // Every transport routes both its undeclared default and its
    // post-declaration reset through here, so the re-anchor is structural: a
    // negotiated state never inherits a baseline or a transmitted-image set.
    let negotiated = HostWireCapabilities(acceptsDeltaFrames: true)
      .negotiatedEncodingState()
    #expect(!negotiated.hasBaseline)
    #expect(negotiated.baselineSize == nil)
    #expect(negotiated.knownImageIDs.isEmpty)
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
      {"acceptsDeltaFrames":"yes","renderer":"dom"}
      """
    )
    #expect(parsed == HostWireCapabilities())
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
