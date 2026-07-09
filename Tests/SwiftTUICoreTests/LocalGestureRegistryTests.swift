import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite
struct LocalGestureRegistryTests {
  @Test("Registered recognizers are retrievable by identity")
  func registerAndRetrieve() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "root")])
    let recognizer = AnyGestureRecognizer(NoopRecognizer())

    registry.register(identity: identity, recognizer: recognizer)
    #expect(registry.recognizer(for: identity) === recognizer)
  }

  @Test("removeSubtrees clears descendants but not siblings")
  func removeSubtrees() {
    let registry = LocalGestureRegistry()
    let parent = Identity(components: [IdentityComponent(rawValue: "p")])
    let child = parent.child(IdentityComponent(rawValue: "c"))
    let sibling = Identity(components: [IdentityComponent(rawValue: "s")])

    registry.register(identity: parent, recognizer: AnyGestureRecognizer(NoopRecognizer()))
    registry.register(identity: child, recognizer: AnyGestureRecognizer(NoopRecognizer()))
    registry.register(identity: sibling, recognizer: AnyGestureRecognizer(NoopRecognizer()))

    registry.removeSubtrees(rootedAt: [parent])

    #expect(registry.recognizer(for: parent) == nil)
    #expect(registry.recognizer(for: child) == nil)
    #expect(registry.recognizer(for: sibling) != nil)
  }

  @Test("Teardown is invoked when a recognizer is removed via subtree removal")
  func teardownOnRemove() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])
    let tracker = TearDownTracker()
    registry.register(
      identity: identity,
      recognizer: AnyGestureRecognizer(tracker)
    )
    registry.removeSubtrees(rootedAt: [identity])
    #expect(tracker.tornDown == true)
  }

  @Test("Re-registering the same identity tears down the previous recognizer")
  func replaceTearsDownPrevious() {
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "r")])
    let first = TearDownTracker()
    let second = TearDownTracker()
    registry.register(identity: identity, recognizer: AnyGestureRecognizer(first))
    registry.register(identity: identity, recognizer: AnyGestureRecognizer(second))
    #expect(first.tornDown == true)
    #expect(second.tornDown == false)
  }

  // MARK: - F100: the restore triple-fallback is load-bearing against prune

  @Test("restore with an empty owner map preserves an active recognizer's live owner across prune")
  func restoreWithEmptyOwnersPreservesLiveOwnerAcrossPrune() {
    // The cache-hit-frame shape: resolve didn't run, so the incoming
    // snapshot's owner map can be empty. Restore must keep the CURRENT live
    // owner (with its viewNodeID) for an active recognizer — collapsing to
    // the family's two-term fallback would mint an unowned key, and
    // prune(keeping:) force-drops nil-viewNodeID owners, tearing down the
    // mid-interaction recognizer.
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "drag")])
    let tracker = TearDownTracker()
    tracker.phase = .began
    let recognizer = AnyGestureRecognizer(tracker)
    let liveNode = ViewNodeID(rawValue: 7)

    registry.restore(
      [identity: recognizer],
      ownersByIdentity: [
        identity: RuntimeRegistrationOwnerKey(viewNodeID: liveNode, identity: identity)
      ]
    )
    #expect(recognizer.isActive)

    // Cache-hit restore: same recognizer, no owner information.
    registry.restore([identity: recognizer], ownersByIdentity: [:])

    registry.prune(keeping: [liveNode])
    #expect(registry.recognizer(for: identity) === recognizer)
    #expect(tracker.tornDown == false)
  }

  @Test("prune force-drops an active recognizer whose owner never gained a viewNodeID")
  func pruneDropsUnownedActiveRecognizer() {
    // The hazard the triple-fallback guards against, pinned as behavior: an
    // owner key without a viewNodeID cannot prove liveness, so prune drops
    // the identity even mid-interaction and tears the recognizer down.
    let registry = LocalGestureRegistry()
    let identity = Identity(components: [IdentityComponent(rawValue: "unowned")])
    let tracker = TearDownTracker()
    tracker.phase = .began
    let recognizer = AnyGestureRecognizer(tracker)

    registry.restore([identity: recognizer], ownersByIdentity: [:])
    registry.prune(keeping: [ViewNodeID(rawValue: 7)])

    #expect(registry.recognizer(for: identity) == nil)
    #expect(tracker.tornDown == true)
  }

  @Test("prune keeps live-owned recognizers and drops departed-owned ones")
  func pruneSplitsByOwnerLiveness() {
    let registry = LocalGestureRegistry()
    let keptIdentity = Identity(components: [IdentityComponent(rawValue: "kept")])
    let droppedIdentity = Identity(components: [IdentityComponent(rawValue: "dropped")])
    let keptTracker = TearDownTracker()
    let droppedTracker = TearDownTracker()
    let liveNode = ViewNodeID(rawValue: 1)
    let departedNode = ViewNodeID(rawValue: 2)

    registry.restore(
      [
        keptIdentity: AnyGestureRecognizer(keptTracker),
        droppedIdentity: AnyGestureRecognizer(droppedTracker),
      ],
      ownersByIdentity: [
        keptIdentity: RuntimeRegistrationOwnerKey(viewNodeID: liveNode, identity: keptIdentity),
        droppedIdentity: RuntimeRegistrationOwnerKey(
          viewNodeID: departedNode, identity: droppedIdentity
        ),
      ]
    )

    registry.prune(keeping: [liveNode])

    #expect(registry.recognizer(for: keptIdentity) != nil)
    #expect(registry.recognizer(for: droppedIdentity) == nil)
    #expect(keptTracker.tornDown == false)
    #expect(droppedTracker.tornDown == true)
  }
}

@MainActor
private final class NoopRecognizer: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() {}
}

@MainActor
private final class TearDownTracker: GestureRecognizer {
  typealias Value = Int
  var phase: GestureRecognizerPhase = .possible
  var tornDown = false
  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition { .ignored }
  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }
  func currentValue() -> Int? { nil }
  func tearDown() { tornDown = true }
}
