import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// `Transaction.isContinuous` (org plan 2026-08-04-002 §5) must be
/// observable on both intent channels:
///
/// - the authored channel — a `.transaction` transform's edit descends to
///   nested transforms and survives a `.animation(_:value:)` request
///   override below it;
/// - the write channel — a `withTransaction`-scoped state write carries the
///   flag on its scheduler segment, so the next resolve's transforms below
///   the written subtree observe it.
///
/// The framework neither sets nor consumes the flag yet: SwiftUI does not
/// auto-set it on gesture updates either (probe, 2026-08-05), so it ships
/// as author-readable metadata, and the animation-explicitness gates stay
/// keyed to animation intent.
@MainActor
@Suite("Transaction isContinuous")
struct TransactionContinuityTests {
  @Test("defaults to false and round-trips")
  func defaultsAndRoundTrip() {
    var transaction = Transaction()
    #expect(!transaction.isContinuous)
    transaction.isContinuous = true
    #expect(transaction.isContinuous)
  }

  @Test("an authored transform's isContinuous is visible to nested transforms")
  func authoredChannelDescends() throws {
    let observed = LockedBox<[Bool]>([])
    let renderer = DefaultRenderer()

    _ = renderer.render(
      Text("probe")
        .transaction { inner in
          observed.withLock { $0.append(inner.isContinuous) }
        }
        .transaction { outer in
          outer.isContinuous = true
        },
      context: .init(identity: testIdentity("ContinuityAuthored")),
      proposal: .init(width: 20, height: 3)
    )

    #expect(observed.value == [true], "the inner transform must see the outer edit")
  }

  @Test("without an authored edit nested transforms observe false")
  func authoredChannelDefaultFalse() throws {
    let observed = LockedBox<[Bool]>([])
    let renderer = DefaultRenderer()

    _ = renderer.render(
      Text("probe")
        .transaction { inner in
          observed.withLock { $0.append(inner.isContinuous) }
        },
      context: .init(identity: testIdentity("ContinuityAuthoredDefault")),
      proposal: .init(width: 20, height: 3)
    )

    #expect(observed.value == [false])
  }

  @Test("a value-animation request override below preserves isContinuous")
  func valueAnimationOverridePreserves() throws {
    let observed = LockedBox<[Bool]>([])
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("ContinuityValueAnimation")

    func body(value: Int) -> some View {
      Text("probe")
        .transaction { inner in
          observed.withLock { $0.append(inner.isContinuous) }
        }
        .animation(.linear(duration: .milliseconds(50)), value: value)
        .transaction { outer in
          outer.isContinuous = true
        }
    }

    // Seed, then change the watched value so ValueAnimationModifier takes
    // its request-override branch — the branch that historically dropped
    // sibling transaction fields (mechanics §5 of the plan).
    _ = renderer.render(
      body(value: 0),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 3)
    )
    _ = renderer.render(
      body(value: 1),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 3)
    )

    #expect(
      observed.value == [true, true],
      "the request override must not reset the outer transform's continuity edit"
    )
  }

  @Test("a scoped write's segment carries isContinuous into the next resolve")
  func writeChannelCarriesIsContinuous() throws {
    let observed = LockedBox<[Bool]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ContinuityWriteChannel"),
      size: .init(width: 32, height: 5)
    ) {
      ContinuousWriteProbe(observed: observed)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    observed.value = []
    try withAnimationSinks(controller) {
      _ = try harness.clickText("ContinuousWrite")
    }

    #expect(
      observed.value.contains(true),
      """
      the withTransaction-scoped write carried isContinuous on its scheduler \
      segment, so the transform below the written subtree must observe it \
      on the write-driven frame — observed: \(observed.value)
      """
    )
  }

  @Test("the animation-explicitness gates ignore a continuity-only transaction")
  func continuityAloneIsNotExplicit() {
    // A transaction that carries only `isContinuous` is not
    // animation-explicit: it must neither survive segment append (nothing
    // consumes it downstream of a plain invalidation) nor force the
    // controller to walk the resolved tree.
    var segments: [AnimationInvalidationSegment] = []
    var continuityOnly = AnimationInvalidationSegment(
      identities: [Identity(components: ["a"])],
      animationRequest: .inherit
    )
    continuityOnly.isContinuous = true
    AnimationInvalidationSegments.append(continuityOnly, to: &segments)
    #expect(segments.isEmpty, "a continuity-only segment is not explicit")

    let controller = AnimationController()
    var base = TransactionSnapshot()
    base.isContinuous = true
    controller.processResolvedTree(
      ResolvedNode(identity: testIdentity("ContinuityGate"), kind: .view("Probe")),
      transaction: .init(),
      timestamp: .now()
    )
    #expect(
      controller.canSkipResolvedTreeProcessing(transaction: base),
      "continuity alone must not defeat the resolved-tree processing skip"
    )
  }
}

/// Writes through `withTransaction` with an animation AND `isContinuous`
/// set, so the segment is explicit and the flag has a vehicle to ride.
private struct ContinuousWriteProbe: View {
  @State private var level = 0.0
  let observed: LockedBox<[Bool]>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("ContinuousWrite") {
        var transaction = Transaction()
        transaction.animation = .linear(duration: .milliseconds(120))
        transaction.isContinuous = true
        withTransaction(transaction) {
          level = 1
        }
      }
      Text("target")
        .opacity(0.2 + level * 0.6)
        .transaction { inner in
          observed.withLock { $0.append(inner.isContinuous) }
        }
    }
  }
}
