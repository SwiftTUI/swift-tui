import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

@MainActor
@Suite("Animation interpolation cone")
struct AnimationInterpolationConeTests {
  @Test("one animated leaf visits only the root-to-leaf route")
  func oneAnimatedLeafVisitsOnlyItsRoute() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)
    let targetIndex = 79
    let t0 = MonotonicInstant.now()

    let baseline = tree(opacities: [targetIndex: 1])
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: t0)

    var target = tree(opacities: [targetIndex: 0])
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(target, transaction: transaction, timestamp: t0)

    _ = controller.applyInterpolations(
      to: &target,
      at: t0.advanced(by: .milliseconds(100))
    )

    #expect(controller.lastPropertyInterpolationVisitedNodeCount == 2)
    let opacity = try #require(target.children[targetIndex].drawMetadata.baseStyle.explicitOpacity)
    #expect(abs(opacity - 0.5) < 0.05)
    #expect(target.children[0] == baseline.children[0])
    #expect(target.children[127] == baseline.children[127])
  }

  @Test("two animated leaves visit the union of their routes")
  func twoAnimatedLeavesVisitRouteUnion() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)
    let firstIndex = 17
    let secondIndex = 103
    let t0 = MonotonicInstant.now()

    let baseline = tree(opacities: [firstIndex: 1, secondIndex: 1])
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: t0)

    var target = tree(opacities: [firstIndex: 0, secondIndex: 0])
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(target, transaction: transaction, timestamp: t0)

    _ = controller.applyInterpolations(
      to: &target,
      at: t0.advanced(by: .milliseconds(100))
    )

    #expect(controller.lastPropertyInterpolationVisitedNodeCount == 3)
    for index in [firstIndex, secondIndex] {
      let opacity = try #require(target.children[index].drawMetadata.baseStyle.explicitOpacity)
      #expect(abs(opacity - 0.5) < 0.05)
    }
  }

  private func tree(opacities: [Int: Double]) -> ResolvedNode {
    let rootIdentity = Identity(components: [.named("F149RouteRoot")])
    let children = (0..<128).map { index in
      var metadata = DrawMetadata()
      metadata.baseStyle.explicitOpacity = opacities[index] ?? 1
      return ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: UInt64(index + 2)),
        identity: rootIdentity.child("leaf-\(index)"),
        kind: .view("Leaf"),
        drawMetadata: metadata
      )
    }
    return ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: rootIdentity,
      kind: .view("Root"),
      children: children
    )
  }
}
