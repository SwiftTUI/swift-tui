import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct DefaultPresenceTransitionTests {
  private struct RuntimeHost: View {
    @State private var visible = false
    var body: some View {
      VStack {
        Button("toggle") {
          withAnimation(.linear(duration: .milliseconds(200))) { visible.toggle() }
        }
        if visible { Text("PRESENT") }
      }
    }
  }

  @Test(
    "input-driven default transitions settle and obey the runtime motion policy",
    arguments: [false, true])
  func runtimeInput(reduced: Bool) async throws {
    let harness = try AnimatorRuntimeHarness(motion: reduced ? .reduced : .normal) { RuntimeHost() }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    try withAnimationSinks(controller) { _ = try harness.clickText("toggle") }
    #expect((controller.activeAnimationCount > 0) == !reduced)
    try await harness.wait { controller.activeAnimationCount == 0 }
    #expect(harness.frame.contains("PRESENT"))
    try withAnimationSinks(controller) { _ = try harness.clickText("toggle") }
    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty == reduced)
    try await harness.wait { controller.debugStateSnapshot().removingIdentities.isEmpty }
    #expect(!harness.frame.contains("PRESENT"))
  }

  private struct Host: View {
    var visible: Bool
    var identityTransition = false
    var body: some View {
      VStack {
        Text("STAYS")
        if visible {
          if identityTransition {
            Text("FIG").transition(.identity).padding(1)
          } else {
            VStack {
              Text("FIG")
              Text("CHILD")
            }
          }
        }
      }
    }
  }

  private func change(
    from: Bool, to: Bool, animated: Bool = true,
    identityTransition: Bool = false, reduceMotion: Bool = false
  ) -> AnimationController {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("default-presence")
    let proposal = ProposedSize(width: .finite(20), height: .finite(5))
    withAnimationSinks(controller) {
      _ = renderer.render(
        Host(visible: from, identityTransition: identityTransition)
          .environment(\.accessibilityReduceMotion, reduceMotion),
        context: .init(identity: root), proposal: proposal)
      var transaction = TransactionSnapshot()
      if animated {
        // RunLoop.makeResolveContext clamps frame transactions under the
        // runtime's reduced-motion policy before they reach the renderer.
        transaction.animationRequest =
          reduceMotion
          ? .disabled
          : .animate(Animation.linear(duration: .seconds(1)).animationBox)
      }
      _ = renderer.render(
        Host(visible: to, identityTransition: identityTransition)
          .environment(\.accessibilityReduceMotion, reduceMotion),
        context: .init(identity: root, transaction: transaction), proposal: proposal)
    }
    return controller
  }

  @Test("an unmarked conditional inserts with one opacity animation for its entire subtree")
  func insertion() {
    let controller = change(from: false, to: true)
    #expect(
      controller.debugStateSnapshot().activeAnimationKeys.filter { $0.scope == .property(.opacity) }
        .count == 1)
  }

  @Test("an unmarked conditional removal retains one nonsemantic exit overlay")
  func removal() {
    #expect(change(from: true, to: false).debugStateSnapshot().removingIdentities.count == 1)
  }

  @Test("an explicit identity transition suppresses the default on both presence edges")
  func explicitIdentity() {
    #expect(change(from: false, to: true, identityTransition: true).activeAnimationCount == 0)
    #expect(
      change(from: true, to: false, identityTransition: true).debugStateSnapshot()
        .removingIdentities.isEmpty)
  }

  @Test("ordinary presence changes do not create default transitions")
  func unanimated() {
    #expect(change(from: false, to: true, animated: false).activeAnimationCount == 0)
    #expect(
      change(from: true, to: false, animated: false).debugStateSnapshot().removingIdentities.isEmpty
    )
  }

  @Test("reduced motion suppresses implicit presence animation")
  func reducedMotion() {
    #expect(change(from: false, to: true, reduceMotion: true).activeAnimationCount == 0)
    #expect(
      change(from: true, to: false, reduceMotion: true).debugStateSnapshot().removingIdentities
        .isEmpty)
  }

  @Test("reinsertion resumes from the displayed removal opacity")
  func reinsertion() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("default-reinsertion")
    let proposal = ProposedSize(width: .finite(20), height: .finite(5))
    let start = MonotonicInstant(offset: .seconds(100))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)
    try withAnimationSinks(controller) {
      _ = renderer.render(
        Host(visible: true), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      _ = renderer.render(
        Host(visible: false), context: .init(identity: root, transaction: animated),
        proposal: proposal, frameInstant: start)
      let frame = renderer.render(
        Host(visible: true), context: .init(identity: root, transaction: animated),
        proposal: proposal, frameInstant: start.advanced(by: .milliseconds(500)))
      let key = try #require(
        controller.debugStateSnapshot().activeAnimationKeys.first {
          $0.scope == .property(.opacity)
        })
      let node = try #require(
        AnimationTreeQueries.findResolvedSubtree(
          in: frame.resolvedTree, identity: key.identity))
      #expect(node.drawMetadata.baseStyle.explicitOpacity == 0.5)
      #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
    }
  }
}
