import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// `withCheckedMainActorAccess` adds a release-checked `preconditionIsolated`
// before bridging into MainActor-isolated state (supplemental item #21). The
// off-main trap path can't be unit-tested safely (it's a precondition crash),
// but the success path — invoked on the main actor it must transparently return
// the body's value — is exercised here, as it is implicitly by every layout
// test that touches the retrofitted accessors.
@MainActor
@Suite("Checked main-actor access")
struct CheckedMainActorAccessTests {
  @Test("returns the body's value when invoked on the main actor")
  func returnsBodyValueOnMain() {
    #expect(withCheckedMainActorAccess("test.int") { 42 } == 42)
  }

  @Test("passes through non-trivial Sendable return values")
  func passesThroughSendableValues() {
    #expect(withCheckedMainActorAccess("test.array") { ["a", "b"] } == ["a", "b"])
  }
}
