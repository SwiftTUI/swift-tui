import Testing

@testable import SwiftTUIGraph

/// Registrations with equal display labels retain their separate owner lifetimes.
@MainActor
@Suite("Lifecycle handler dispatch determinism")
struct LifecycleHandlerDispatchTests {
  @MainActor
  private final class FireLog {
    private(set) var fired: [String] = []
    func record(_ label: String) { fired.append(label) }
  }

  @Test("two owners at one identity and ordinal dispatch their own registration")
  func twoOwnersDispatchIndependently() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("DispatchRoot")
    let sharedIdentity = testIdentity("DispatchRoot", "Shared")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("DispatchRoot", "A"), kind: .view(.init("A"))),
          ResolvedNode(identity: testIdentity("DispatchRoot", "B"), kind: .view(.init("B"))),
        ]
      )
    )
    let nodeA = try #require(graph.nodeForIdentity(testIdentity("DispatchRoot", "A")))
    let nodeB = try #require(graph.nodeForIdentity(testIdentity("DispatchRoot", "B")))

    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerIDs: [LifecycleHandlerID] = []
    for ordinal in 0..<24 {
      var handlerID: LifecycleHandlerID = ""
      ViewNodeContext.withCurrentValue(nodeA) {
        handlerID = registry.registerAppear(identity: sharedIdentity, ordinal: ordinal) {
          log.record("stale[\(ordinal)]")
        }
      }
      ViewNodeContext.withCurrentValue(nodeB) {
        let latestID = registry.registerAppear(identity: sharedIdentity, ordinal: ordinal) {
          log.record("latest[\(ordinal)]")
        }
        #expect(latestID != handlerID)
        #expect(latestID.description == handlerID.description)
        handlerIDs.append(latestID)
      }
      handlerIDs.append(handlerID)
    }

    for handlerID in handlerIDs {
      registry.appearHandler(for: handlerID)?()
    }
    #expect(
      log.fired == (0..<24).flatMap { ["latest[\($0)]", "stale[\($0)]"] },
      "dispatch resolved a stale owner's handler: \(log.fired)"
    )
  }

  @Test("the snapshot dispatches by the registered owner")
  func snapshotPreservesOwner() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("SnapshotRoot")
    let sharedIdentity = testIdentity("SnapshotRoot", "Shared")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: testIdentity("SnapshotRoot", "A"), kind: .view(.init("A"))),
          ResolvedNode(identity: testIdentity("SnapshotRoot", "B"), kind: .view(.init("B"))),
        ]
      )
    )
    let nodeA = try #require(graph.nodeForIdentity(testIdentity("SnapshotRoot", "A")))
    let nodeB = try #require(graph.nodeForIdentity(testIdentity("SnapshotRoot", "B")))

    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerIDs: [LifecycleHandlerID] = []
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
      snapshot.disappearHandler(for: handlerID)?()
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
          ResolvedNode(identity: testIdentity("TeardownRoot", "Owner"), kind: .view(.init("Owner")))
        ]
      )
    )
    let node = try #require(graph.nodeForIdentity(testIdentity("TeardownRoot", "Owner")))

    let registry = LocalLifecycleRegistry()
    let log = FireLog()
    var handlerID: LifecycleHandlerID = ""
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
