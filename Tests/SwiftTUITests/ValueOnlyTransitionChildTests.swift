import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Pins `.transition()` on a value-only child — the gallery Animations-tab
/// shape: the transition-marked view lives under an `.overlay { if flag {…} }`
/// branch and, before the fix, resolved without its own graph node. Its
/// registration then fell back to the enclosing evaluation host's
/// `ViewNodeID`, which never departs or arrives, so the ViewNodeID-occurrence
/// diff (`8a27677a`) could not see the conditional toggle: removals never
/// planned an exit overlay and insertions were mis-suppressed as reparents.
/// Node-backing the transition child gives the diff a real occurrence to key
/// on in both directions.
@MainActor
@Suite
struct ValueOnlyTransitionChildTests {
  private struct TransitionHost: View {
    var showsFigure: Bool
    var body: some View {
      Text("BASE")
        .overlay {
          if showsFigure {
            Text("FIG").transition(.opacity)
          }
        }
    }
  }

  @Test("conditional removal of an overlay-hosted transition child plans an exit overlay")
  func overlayHostedRemovalPlansExitOverlay() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.withSink(controller) {
      TransitionRegistrationStorage.withSink(controller) {
        let animation = Animation.linear(duration: .milliseconds(1200))
        controller.register(animation)
        let rootIdentity = testIdentity("value-only-transition-removal")

        _ = renderer.render(
          TransitionHost(showsFigure: true),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        var transaction = TransactionSnapshot()
        transaction.animationRequest = .animate(animation.animationBox)
        let artifacts = renderer.render(
          TransitionHost(showsFigure: false),
          context: ResolveContext(identity: rootIdentity, transaction: transaction),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        let snapshot = controller.debugStateSnapshot()
        #expect(
          snapshot.removingIdentities.count == 1,
          """
          the departed transition child must plan exactly one removal overlay, \
          got \(snapshot.removingIdentities)
          """
        )

        // The exit overlay must actually composite: applying placed overlays
        // mid-curve re-injects the departed subtree as a transient child.
        var placed = artifacts.placedTree
        controller.applyPlacedOverlays(
          to: &placed,
          at: MonotonicInstant.now().advanced(by: .milliseconds(100))
        )
        #expect(
          containsTransientNode(placed),
          "the removal overlay must be re-injected as a transient placed node"
        )
      }
    }
  }

  @Test("conditional insertion of an overlay-hosted transition child animates in")
  func overlayHostedInsertionStartsInsertionAnimation() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.withSink(controller) {
      TransitionRegistrationStorage.withSink(controller) {
        let animation = Animation.linear(duration: .milliseconds(1200))
        controller.register(animation)
        let rootIdentity = testIdentity("value-only-transition-insertion")

        _ = renderer.render(
          TransitionHost(showsFigure: false),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        var transaction = TransactionSnapshot()
        transaction.animationRequest = .animate(animation.animationBox)
        _ = renderer.render(
          TransitionHost(showsFigure: true),
          context: ResolveContext(identity: rootIdentity, transaction: transaction),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        #expect(
          controller.activeAnimationCount > 0,
          "the inserted transition child must start its insertion animation"
        )
      }
    }
  }

  @Test("a removal with no animation intent completes on the next placed sample")
  func unanimatedRemovalDoesNotStrandItsEntry() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.withSink(controller) {
      TransitionRegistrationStorage.withSink(controller) {
        let rootIdentity = testIdentity("value-only-transition-unanimated")

        _ = renderer.render(
          TransitionHost(showsFigure: true),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )
        let artifacts = renderer.render(
          TransitionHost(showsFigure: false),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        // Without an animation box there is nothing to interpolate: the
        // sample pass must complete the removal instead of skipping it
        // forever (a stranded entry keeps the frame pump armed for the
        // rest of the session).
        var placed = artifacts.placedTree
        controller.applyPlacedOverlays(
          to: &placed,
          at: MonotonicInstant.now()
        )
        #expect(
          controller.debugStateSnapshot().removingIdentities.isEmpty,
          "an unanimated removal must not strand a removal entry"
        )
      }
    }
  }

  // A bare composite branch child (the node-backed conditional shape) hosts
  // its transition registration on its own mint, and single-child flattening
  // aliases that mint's stamp onto the absorbing chain level — the
  // controller's re-home pass must move the registration onto the committed
  // stamp or neither removal channel can see the branch flip.
  private struct CompositeTransitionHost: View {
    var showsFigure: Bool
    var body: some View {
      Text("BASE")
        .overlay {
          if showsFigure {
            TransitionFigure()
          }
        }
    }
  }

  private struct TransitionFigure: View {
    @State private var progress = 0.0
    var body: some View {
      Text("FIG \(progress)").transition(.opacity)
    }
  }

  @Test("conditional removal of a composite-hosted transition child plans an exit overlay")
  func compositeHostedRemovalPlansExitOverlay() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.withSink(controller) {
      TransitionRegistrationStorage.withSink(controller) {
        let animation = Animation.linear(duration: .milliseconds(1200))
        controller.register(animation)
        let rootIdentity = testIdentity("composite-transition-removal")

        _ = renderer.render(
          CompositeTransitionHost(showsFigure: true),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        var transaction = TransactionSnapshot()
        transaction.animationRequest = .animate(animation.animationBox)
        _ = renderer.render(
          CompositeTransitionHost(showsFigure: false),
          context: ResolveContext(identity: rootIdentity, transaction: transaction),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        let snapshot = controller.debugStateSnapshot()
        #expect(
          snapshot.removingIdentities.count == 1,
          """
          the departed composite transition child must plan exactly one removal \
          overlay, got \(snapshot.removingIdentities)
          """
        )
      }
    }
  }

  @Test("conditional insertion of a composite-hosted transition child animates in")
  func compositeHostedInsertionStartsInsertionAnimation() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController

    AnimationRegistrationStorage.withSink(controller) {
      TransitionRegistrationStorage.withSink(controller) {
        let animation = Animation.linear(duration: .milliseconds(1200))
        controller.register(animation)
        let rootIdentity = testIdentity("composite-transition-insertion")

        _ = renderer.render(
          CompositeTransitionHost(showsFigure: false),
          context: ResolveContext(identity: rootIdentity),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        var transaction = TransactionSnapshot()
        transaction.animationRequest = .animate(animation.animationBox)
        _ = renderer.render(
          CompositeTransitionHost(showsFigure: true),
          context: ResolveContext(identity: rootIdentity, transaction: transaction),
          proposal: ProposedSize(width: .finite(20), height: .finite(4))
        )

        #expect(
          controller.activeAnimationCount > 0,
          "the inserted composite transition child must start its insertion animation"
        )
      }
    }
  }

  private func containsTransientNode(_ node: PlacedNode) -> Bool {
    if node.isTransient { return true }
    return node.children.contains { containsTransientNode($0) }
  }
}
