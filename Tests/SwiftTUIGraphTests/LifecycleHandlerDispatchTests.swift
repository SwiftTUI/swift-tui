import Testing

@testable import SwiftTUIGraph

/// F130: lifecycle handler dispatch is a dictionary lookup with a
/// deterministic latest-wins policy. Two owner nodes registering at the same
/// identity + ordinal share one handlerID string; the registry retains both
/// typed registrations (distinct owner keys), and every string-keyed view —
/// dispatch and the previous-frame snapshot — must resolve to the LATEST
/// registration. The old value-scan collapsed by dictionary iteration order,
/// which is nondeterministic run to run.
@MainActor
@Suite("Lifecycle handler dispatch determinism")
struct LifecycleHandlerDispatchTests {
  @MainActor
  private final class FireLog {
    private(set) var fired: [String] = []
    func record(_ label: String) { fired.append(label) }
  }

  @Test("two owners at one identity+ordinal dispatch the latest registration")
  func twoOwnersDispatchLatestDeterministically() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("DispatchRoot")
    let sharedIdentity = testIdentity("DispatchRoot", "Shared")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("DispatchRoot", "A"), kind: .view("A")),
          ResolvedNode(identity: testIdentity("DispatchRoot", "B"), kind: .view("B")),
        ]
      )
    )
    let nodeA = try #require(graph.nodeForIdentity(testIdentity("DispatchRoot", "A")))
    let nodeB = try #require(graph.nodeForIdentity(testIdentity("DispatchRoot", "B")))

    // Many independent collision pairs: the old unordered value-scan picks
    // an arbitrary winner per pair, so at least one stale pick is
    // overwhelmingly likely pre-fix.
    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerIDs: [String] = []
    for ordinal in 0..<24 {
      var handlerID = ""
      ViewNodeContext.withCurrentValue(nodeA) {
        handlerID = registry.registerAppear(identity: sharedIdentity, ordinal: ordinal) {
          log.record("stale[\(ordinal)]")
        }
      }
      ViewNodeContext.withCurrentValue(nodeB) {
        let latestID = registry.registerAppear(identity: sharedIdentity, ordinal: ordinal) {
          log.record("latest[\(ordinal)]")
        }
        #expect(latestID == handlerID, "the two owners must share one handlerID")
      }
      handlerIDs.append(handlerID)
    }

    for handlerID in handlerIDs {
      registry.appearHandler(for: handlerID)?()
    }
    #expect(
      log.fired == (0..<24).map { "latest[\($0)]" },
      "dispatch resolved a stale owner's handler: \(log.fired)"
    )
  }

  @Test("the snapshot's string maps collapse to the latest registration")
  func snapshotCollapsesToLatest() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("SnapshotRoot")
    let sharedIdentity = testIdentity("SnapshotRoot", "Shared")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("SnapshotRoot", "A"), kind: .view("A")),
          ResolvedNode(identity: testIdentity("SnapshotRoot", "B"), kind: .view("B")),
        ]
      )
    )
    let nodeA = try #require(graph.nodeForIdentity(testIdentity("SnapshotRoot", "A")))
    let nodeB = try #require(graph.nodeForIdentity(testIdentity("SnapshotRoot", "B")))

    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerIDs: [String] = []
    for ordinal in 0..<24 {
      ViewNodeContext.withCurrentValue(nodeA) {
        _ = registry.registerDisappear(identity: sharedIdentity, ordinal: ordinal) {
          log.record("stale[\(ordinal)]")
        }
      }
      ViewNodeContext.withCurrentValue(nodeB) {
        handlerIDs.append(
          registry.registerDisappear(identity: sharedIdentity, ordinal: ordinal) {
            log.record("latest[\(ordinal)]")
          }
        )
      }
    }

    let snapshot = registry.snapshot()
    for handlerID in handlerIDs {
      snapshot.disappearHandlers[handlerID]?()
    }
    #expect(log.fired == (0..<24).map { "latest[\($0)]" })
  }

  @Test("teardown of one owner's subtree rebuilds the dispatch index")
  func teardownRebuildsIndex() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("TeardownRoot")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("TeardownRoot", "Owner"), kind: .view("Owner"))
        ]
      )
    )
    let node = try #require(graph.nodeForIdentity(testIdentity("TeardownRoot", "Owner")))

    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerID = ""
    ViewNodeContext.withCurrentValue(node) {
      handlerID = registry.registerAppear(
        identity: testIdentity("TeardownRoot", "Owner"),
        ordinal: 0
      ) {
        log.record("fired")
      }
    }
    #expect(registry.appearHandler(for: handlerID) != nil)

    registry.removeSubtrees(rootedAt: [testIdentity("TeardownRoot", "Owner")])
    #expect(
      registry.appearHandler(for: handlerID) == nil,
      "a torn-down subtree's handler stayed reachable through the index"
    )
  }
}
