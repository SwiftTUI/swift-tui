import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Animation ledger lifetime")
struct AnimationLedgerLifetimeTests {
  private let root = testIdentity("T255", "Root")
  private let leaf = testIdentity("T255", "Root", "Leaf")
  private let nodeID = ViewNodeID(rawValue: 95_501)
  private let start = MonotonicInstant(offset: .seconds(900))
  private let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 4))

  private func resolved(present: Bool) -> ResolvedNode {
    ResolvedNode(
      identity: root, kind: .view("Root"),
      children: present
        ? [
          ResolvedNode(viewNodeID: nodeID, identity: leaf, kind: .view("Leaf"))
        ] : [])
  }

  private func placed(present: Bool) -> PlacedNode {
    PlacedNode(
      identity: root, bounds: bounds,
      children: present
        ? [
          PlacedNode(identity: leaf, bounds: bounds)
        ] : [])
  }

  @Test(
    "T255: completed placed insertions release their registered curve", arguments: [false, true])
  func completedInsertionReleasesCurve(scale: Bool) {
    let controller = AnimationController()
    controller.processResolvedTree(resolved(present: false), transaction: .init(), timestamp: start)
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leaf, viewNodeID: nodeID,
      transition: scale ? AnyTransition.scale : AnyTransition.offset(x: 4))
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      resolved(present: true), transaction: transaction, timestamp: start)
    #expect(!controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    _ = controller.placedAnimationOverlaySnapshot(
      for: placed(present: true), at: start.advanced(by: .seconds(2)))
    #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
  }

  @Test("T255: removal purge releases curves after the last barrier", arguments: [0, 1, 2])
  func completedRemovalReleasesCurve(mode: Int) {
    let controller = AnimationController()
    controller.beginTransitionCollection()
    controller.registerTransition(for: leaf, viewNodeID: nodeID, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()
    controller.processResolvedTree(resolved(present: true), transaction: .init(), timestamp: start)
    if mode > 0 { controller.capturePlacedTree(placed(present: true)) }
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let completed = FireCounter()
    if mode == 2 {
      let batch = AnimationBatchID(95_502)
      transaction.animationBatchID = batch
      controller.registerCompletion(batchID: batch, barrier: .removed) { completed.increment() }
    }
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var empty = resolved(present: false)
    controller.processResolvedTree(empty, transaction: transaction, timestamp: start)
    #expect(controller.debugStateSnapshot().removingNodeIDs.count == 1)
    let end = start.advanced(by: .seconds(2))
    if mode == 0 {
      _ = controller.applyInterpolations(to: &empty, at: end)
    } else {
      _ = controller.placedAnimationOverlaySnapshot(for: placed(present: false), at: end)
      if mode == 2 {
        #expect(completed.count == 0)
        #expect(controller.debugStateSnapshot().registeredAnimationCount == 1)
        _ = controller.applyInterpolations(to: &empty, at: end.advanced(by: .milliseconds(16)))
        #expect(completed.count == 1)
      }
    }
    #expect(controller.debugStateSnapshot().removingNodeIDs.isEmpty)
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
  }

  @Test("T255: a shared curve survives until its last placed consumer completes")
  func sharedCurveSurvivesLaterInsertion() {
    let controller = AnimationController()
    controller.processResolvedTree(resolved(present: false), transaction: .init(), timestamp: start)
    let animation = Animation.linear(duration: .seconds(1))
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.beginTransitionCollection()
    controller.registerTransition(for: leaf, viewNodeID: nodeID, transition: AnyTransition.scale)
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      resolved(present: true), transaction: transaction, timestamp: start)
    let second = testIdentity("T255", "Root", "Second")
    let secondNodeID = ViewNodeID(rawValue: 95_503)
    var both = resolved(present: true)
    both.children.append(
      ResolvedNode(viewNodeID: secondNodeID, identity: second, kind: .view("Leaf")))
    var bothPlaced = placed(present: true)
    bothPlaced.children.append(PlacedNode(identity: second, bounds: bounds))
    controller.beginTransitionCollection()
    controller.registerTransition(for: leaf, viewNodeID: nodeID, transition: AnyTransition.scale)
    controller.registerTransition(
      for: second, viewNodeID: secondNodeID, transition: AnyTransition.scale)
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      both, transaction: transaction, timestamp: start.advanced(by: .milliseconds(500)))
    #expect(controller.debugStateSnapshot().activeAnimationKeys.count == 2)
    _ = controller.placedAnimationOverlaySnapshot(
      for: bothPlaced, at: start.advanced(by: .milliseconds(1100)))
    #expect(controller.debugStateSnapshot().activeAnimationKeys.count == 1)
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 1)
    _ = controller.placedAnimationOverlaySnapshot(
      for: bothPlaced, at: start.advanced(by: .milliseconds(1600)))
    #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
  }

  @Test("T255: completed matched geometry releases its registered curve")
  func completedMatchedGeometryReleasesCurve() {
    let controller = AnimationController()
    let key = MatchedGeometryKey(id: "T255-match")
    var first = resolved(present: true)
    first.children[0].matchedGeometry = .init(key: key)
    var firstPlaced = placed(present: true)
    firstPlaced.children[0].matchedGeometry = .init(key: key)
    controller.processResolvedTree(first, transaction: .init(), timestamp: start)
    controller.capturePlacedTree(firstPlaced)
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let second = testIdentity("T255", "Root", "Second")
    first.children[0].identity = second
    controller.processResolvedTree(first, transaction: transaction, timestamp: start)
    firstPlaced.children[0].identity = second
    firstPlaced.children[0].bounds.origin.x = 10
    #expect(controller.activeMatchedGeometryCount == 1)
    _ = controller.placedAnimationOverlaySnapshot(
      for: firstPlaced, at: start.advanced(by: .seconds(2)))
    #expect(controller.activeMatchedGeometryCount == 0)
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
  }
}
