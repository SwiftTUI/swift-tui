import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private struct FlavorKey: TransactionKey {
  static let defaultValue = "plain"
}

private struct CountKey: TransactionKey {
  static let defaultValue = 0
}

/// Custom `TransactionKey` values (org plan 2026-08-04-002 §7): the
/// `EnvironmentKey` shape with `Value` narrowed to `Hashable & Sendable`
/// (the environment-`Sendable` narrowing precedent). Key values must be
/// observable on both intent channels, participate in reuse equivalence
/// (transforms read them at resolve), and stay non-explicit — a keys-only
/// transaction carries no animation intent.
@MainActor
@Suite("Transaction custom keys")
struct TransactionKeyTests {
  @Test("unset keys read their default; set keys round-trip independently")
  func subscriptDefaultsAndRoundTrip() {
    var transaction = Transaction()
    #expect(transaction[FlavorKey.self] == "plain")
    #expect(transaction[CountKey.self] == 0)

    transaction[FlavorKey.self] = "spicy"
    transaction[CountKey.self] = 3

    #expect(transaction[FlavorKey.self] == "spicy")
    #expect(transaction[CountKey.self] == 3)
  }

  @Test("an authored transform's key edit is visible to nested transforms")
  func authoredChannelDescends() throws {
    let observed = LockedBox<[String]>([])
    let renderer = DefaultRenderer()

    _ = renderer.render(
      Text("probe")
        .transaction { inner in
          observed.withLock { $0.append(inner[FlavorKey.self]) }
        }
        .transaction { outer in
          outer[FlavorKey.self] = "spicy"
        },
      context: .init(identity: testIdentity("TransactionKeyAuthored")),
      proposal: .init(width: 20, height: 3)
    )

    #expect(observed.value == ["spicy"])
  }

  @Test("a scoped write's segment carries key values into the next resolve")
  func writeChannelCarriesKeys() throws {
    let observed = LockedBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TransactionKeyWriteChannel"),
      size: .init(width: 32, height: 5)
    ) {
      KeyedWriteProbe(observed: observed)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    observed.value = []
    try withAnimationSinks(controller) {
      _ = try harness.clickText("KeyedWrite")
    }

    #expect(
      observed.value.contains("spicy"),
      """
      the withTransaction-scoped write carried the key value on its \
      scheduler segment — observed: \(observed.value)
      """
    )
  }

  @Test("key values affect retained reuse equivalence")
  func keysAffectReuseEquivalence() {
    let bare = TransactionSnapshot()
    var keyed = TransactionSnapshot()
    keyed.customValues[ObjectIdentifier(FlavorKey.self)] = AnyHashableSendable("spicy")

    #expect(!bare.isReuseEquivalent(to: keyed))
  }

  @Test("a keys-only transaction is not animation-explicit")
  func keysAloneAreNotExplicit() {
    var segments: [AnimationInvalidationSegment] = []
    var keysOnly = AnimationInvalidationSegment(
      identities: [Identity(components: ["a"])],
      animationRequest: .inherit
    )
    keysOnly.customValues[ObjectIdentifier(FlavorKey.self)] = AnyHashableSendable("spicy")
    AnimationInvalidationSegments.append(keysOnly, to: &segments)

    #expect(segments.isEmpty, "keys are resolve-side data, not animation intent")
  }
}

private struct KeyedWriteProbe: View {
  @State private var level = 0.0
  let observed: LockedBox<[String]>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("KeyedWrite") {
        var transaction = Transaction()
        transaction.animation = .linear(duration: .milliseconds(120))
        transaction[FlavorKey.self] = "spicy"
        withTransaction(transaction) {
          level = 1
        }
      }
      Text("target")
        .opacity(0.2 + level * 0.6)
        .transaction { inner in
          observed.withLock { $0.append(inner[FlavorKey.self]) }
        }
    }
  }
}
