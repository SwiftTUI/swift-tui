import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite("AnimationController snapshot extraction")
struct AnimationControllerSnapshotTests {
  @Test("extracts foregroundColor from local drawMetadata")
  func extractsLocalForegroundColor() throws {
    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }

  @Test("falls back to environment snapshot when local drawMetadata has no foreground")
  func extractsForegroundFromEnvironmentFallback() throws {
    // Mirror the gallery case: a leaf (TextFigure) whose drawMetadata
    // is default but whose resolved environment carries the foreground
    // style set by an ancestor `.foregroundStyle(color)` modifier.
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: DrawMetadata()
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(
      snapshot.foregroundColor == Color.blue,
      "environment-carried foreground styles must be extracted so `.foregroundStyle(color)` on non-Text views animates"
    )
  }

  @Test("local drawMetadata takes priority over environment snapshot")
  func localDrawMetadataWinsOverEnvironment() throws {
    var style = StyleEnvironmentSnapshot()
    style.foregroundStyle = .color(Color.blue)
    let environment = EnvironmentSnapshot(style: style)

    var drawMetadata = DrawMetadata()
    drawMetadata.baseStyle.foregroundStyle = .color(Color.red)

    let node = ResolvedNode(
      identity: Identity(components: [.named("test")]),
      kind: .view("Leaf"),
      environmentSnapshot: environment,
      drawMetadata: drawMetadata
    )

    let snapshot = AnimatableSnapshot.extract(from: node)
    #expect(snapshot.foregroundColor == Color.red)
  }
}

@MainActor
@Suite("AnimationController removal injection")
struct AnimationControllerRemovalTests {
  @Test("removed identity with .opacity transition is re-injected into the tree")
  func removedIdentityIsReinjectedIntoTree() throws {
    let controller = AnimationController()
    let animation = Animation.easeInOut(duration: .milliseconds(200))
    controller.register(animation)

    // Register the transition for the soon-to-be-removed child.
    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: parent has the leaf as a child.
    let leaf = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf")
    )
    var root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      root,
      transaction: .init(),
      timestamp: t0
    )

    // Frame 2: leaf is gone; transaction carries a withAnimation intent.
    //
    // IMPORTANT: the real gallery case does NOT re-register the
    // transition on the frame where the view disappears — the branch
    // containing `.transition(.opacity)` is no longer evaluated, so
    // `TransitionViewModifier.resolveElements` never runs.  The
    // controller must carry the registration forward from the previous
    // frame to detect the removal correctly.
    var root2 = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      root2,
      transaction: transaction,
      timestamp: t0
    )

    // At t0 the apply pass should inject the removed leaf back into
    // the tree (it's still mid-animation).
    let tickResult = controller.applyInterpolations(to: &root2, at: t0)
    #expect(tickResult.hasActiveAnimations)

    let injectedChildren = root2.children
    #expect(
      injectedChildren.contains(where: { $0.identity == leafIdentity }),
      "removed leaf should be re-injected as a child of its previous parent"
    )

    // The injected leaf should carry a reduced opacity reflecting the
    // early point in the .opacity removal (progress ≈ 0 → still near 1).
    if let injected = injectedChildren.first(where: { $0.identity == leafIdentity }) {
      let opacity = injected.drawMetadata.baseStyle.explicitOpacity
      #expect(opacity != nil)
    }
  }

  @Test(
    "removal walks up disappearing ancestors to inject under a surviving parent"
  )
  func removalWalksUpToSurvivingAncestor() throws {
    // Mirrors the gallery case:
    //     Overlay { if showFigure { TextFigure().transition(.opacity).padding(1) } }
    // When `showFigure` becomes false, BOTH the PaddingView wrapper and
    // the TextFigure leaf disappear from the tree.  The transition is
    // registered on the TextFigure leaf, but the PaddingView is its
    // immediate parent — and the overlay is the surviving ancestor.
    // The controller must walk up, capture the PaddingView subtree, and
    // inject it under the overlay so the whole wrapped unit fades out
    // together.
    let controller = AnimationController()
    let animation = Animation.easeInOut(duration: .milliseconds(200))
    controller.register(animation)

    let overlayIdentity = Identity(components: [.named("overlay")])
    let paddingIdentity = Identity(components: [.named("overlay"), .named("padding")])
    let leafIdentity = Identity(
      components: [.named("overlay"), .named("padding"), .named("leaf")]
    )

    // Register the transition on the leaf (that's where
    // TransitionViewModifier attaches it).
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: overlay → padding → leaf present.
    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    let padding = ResolvedNode(
      identity: paddingIdentity,
      kind: .view("Padding"),
      children: [leaf]
    )
    var overlay = ResolvedNode(
      identity: overlayIdentity,
      kind: .view("Overlay"),
      children: [padding]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(overlay, transaction: .init(), timestamp: t0)

    // Frame 2: both padding and leaf disappear.  Overlay is the only
    // surviving ancestor.  The transition is NOT re-registered because
    // the branch containing `.transition(.opacity)` is gone from the
    // resolved tree — mirrors the real gallery behavior.
    var overlay2 = ResolvedNode(
      identity: overlayIdentity,
      kind: .view("Overlay"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(overlay2, transaction: transaction, timestamp: t0)

    let result = controller.applyInterpolations(to: &overlay2, at: t0)
    #expect(result.hasActiveAnimations)

    // Overlay should now have the padding subtree back as a child,
    // with the leaf inside it — NOT just the bare leaf.
    let injectedPadding = overlay2.children.first { $0.identity == paddingIdentity }
    #expect(
      injectedPadding != nil,
      "the whole padding subtree should be re-injected under the surviving overlay ancestor"
    )
    if let injectedPadding {
      #expect(
        injectedPadding.children.contains { $0.identity == leafIdentity },
        "the padding wrapper should still contain the original leaf"
      )

      // Opacity should cascade to the leaf so the text actually fades.
      if let reinjectedLeaf = injectedPadding.children.first(
        where: { $0.identity == leafIdentity }
      ) {
        #expect(reinjectedLeaf.drawMetadata.baseStyle.explicitOpacity != nil)
      }
    }
  }

  @Test("removal entry purges after the animation completes")
  func removalPurgesAfterAnimationCompletes() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("root"), .named("leaf")])
    controller.beginTransitionCollection()
    controller.registerTransition(for: leafIdentity, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()

    // Frame 1: leaf present.
    let leaf = ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
    var root = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: [leaf]
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(root, transaction: .init(), timestamp: t0)

    // Frame 2: leaf removed with animation intent.  No re-registration
    // because the branch is gone from the resolved tree.
    var root2 = ResolvedNode(
      identity: Identity(components: [.named("root")]),
      kind: .view("Root"),
      children: []
    )
    controller.beginTransitionCollection()
    // (no registration — branch is gone)
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(root2, transaction: transaction, timestamp: t0)

    // Apply at t0 + 500 ms — well past the 100 ms linear duration — so
    // the controller should purge the entry and stop requesting frames.
    let past = t0.advanced(by: .milliseconds(500))
    var treeCopy = root2
    let result = controller.applyInterpolations(to: &treeCopy, at: past)

    #expect(!result.hasActiveAnimations)
    #expect(result.nextDeadline == nil)
    #expect(
      !treeCopy.children.contains(where: { $0.identity == leafIdentity }),
      "purged removal should not be re-injected after the animation completes"
    )
  }
}
