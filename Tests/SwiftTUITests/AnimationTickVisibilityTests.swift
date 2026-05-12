import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Property pins for ``AnimationTickResult.redrawIdentities``.
///
/// Background: a `.border(blend:)` whose phase is driven by
/// `withAnimation(.linear.repeatForever)` schedules a 30 FPS tick.
/// `redrawIdentities` describes which view identities the tick
/// touched, which downstream consumers (the incremental presentation
/// diff in the render pipeline) use to decide which subtrees to
/// re-rasterize.
///
/// Phase 4 removed the wake-up gate that used to skip
/// `requestDeadline(_:)` when `redrawIdentities.isDisjoint(with:
/// drawnIdentities)` — the gate had a one-way trap with stranded
/// drains and was replaced with the explicit ``hasPendingWork``
/// signal.  These tests still pin the descriptive property: when the
/// animated view sits below a clipped viewport the affected identity
/// must NOT appear in the frame's `drawnIdentities`, and when the
/// view is visible it MUST appear.  Even though no production code
/// gates on this disjointness anymore, the invariant remains a
/// useful pin on the placed-tree clip walk.
@MainActor
struct AnimationTickVisibilityTests {
  @Test("animated border clipped by ScrollView viewport is NOT in drawnIdentities")
  func animatedBorderBelowScrollViewportIsQuiescent() throws {
    // Build a ScrollView with a huge content frame that places an
    // animated chasing-light border far below the visible viewport.
    // The ScrollView's clipBounds must entirely exclude the border's
    // placed rect for the animation to be considered quiescent.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(3000))
      .repeatForever(autoreverses: false)
    controller.register(animation)

    let blend = BorderBlend([.red, .yellow, .green, .cyan, .blue, .red])
    let rootIdentity = testIdentity("ScrollClipAnim", "root")

    // The phase is wrapped in a closure so we can render two frames
    // with different phase values and a withAnimation intent on the
    // second — the standard "seed, then animate" pattern used by
    // `borderBlendPhaseAnimationEnqueuesActiveRequest`.
    func body(phase: Double) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          // A tall block that pushes the animated border far below
          // the top of the content.  y ≈ 50 inside a 2-row viewport
          // guarantees the border's placed rect is entirely clipped.
          ForEach(0..<50, id: \.self) { _ in
            Text("filler")
          }
          Text("chasing")
            .padding(1)
            .frame(width: 10, height: 3)
            .border(
              blend: blend,
              set: .single,
              phase: phase
            )
        }
      }
      .frame(width: 20, height: 2)
    }

    // Frame 1 (seed): phase 0, no animation intent.
    _ = renderer.render(
      body(phase: 0),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 2)
    )

    // Frame 2: phase 1.0 under an explicit withAnimation transaction.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let animatedArtifacts = renderer.render(
      body(phase: 1.0),
      context: .init(identity: rootIdentity, transaction: transaction),
      proposal: .init(width: 20, height: 2)
    )

    // The controller must be holding an active animation: the phase
    // change 0 → 1.0 under withAnimation must have been captured.
    #expect(
      controller.activeAnimationCount > 0,
      "controller must have an active animation after the phase change"
    )

    // Apply a tick at t = 100 ms to populate `lastTickResult` the same
    // way the run loop would.
    var treeCopy = animatedArtifacts.resolvedTree
    let tick = controller.applyInterpolations(
      to: &treeCopy,
      at: .now().advanced(by: .milliseconds(100))
    )

    #expect(
      tick.hasPendingWork,
      "tick result must report active animations while repeatForever is in flight"
    )
    #expect(
      !tick.redrawIdentities.isEmpty,
      "tick must identify at least one affected identity"
    )

    // The whole point of the fix: at least one affected identity
    // exists, but NONE of them appear in the frame's drawnIdentities,
    // because the border sits below the ScrollView's viewport clip.
    // The run loop's `isDisjoint(with:)` check therefore returns
    // true and `requestDeadline` is NOT called.
    #expect(
      tick.redrawIdentities.isDisjoint(with: animatedArtifacts.drawnIdentities),
      """
      Expected every affected animation identity to be geometrically clipped \
      by the ScrollView viewport, so the run loop can skip requestDeadline. \
      redrawIdentities=\(tick.redrawIdentities) \
      drawnIdentities∩redraw=\(tick.redrawIdentities.intersection(animatedArtifacts.drawnIdentities))
      """
    )
  }

  @Test("animated border inside visible viewport IS in drawnIdentities")
  func animatedBorderInsideViewportKeepsTicking() throws {
    // Same tree shape, but the viewport is tall enough to include
    // the animated border.  The fix must not break the normal case:
    // redrawIdentities ∩ drawnIdentities must be non-empty so the
    // run loop schedules the next deadline.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(3000))
      .repeatForever(autoreverses: false)
    controller.register(animation)

    let blend = BorderBlend([.red, .yellow, .green, .cyan, .blue, .red])
    let rootIdentity = testIdentity("ScrollVisibleAnim", "root")

    func body(phase: Double) -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("chasing")
            .padding(1)
            .frame(width: 10, height: 3)
            .border(
              blend: blend,
              set: .single,
              phase: phase
            )
        }
      }
      .frame(width: 20, height: 20)
    }

    // Frame 1 (seed).
    _ = renderer.render(
      body(phase: 0),
      context: .init(identity: rootIdentity),
      proposal: .init(width: 20, height: 20)
    )

    // Frame 2 (animated).
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    let animatedArtifacts = renderer.render(
      body(phase: 1.0),
      context: .init(identity: rootIdentity, transaction: transaction),
      proposal: .init(width: 20, height: 20)
    )

    var treeCopy = animatedArtifacts.resolvedTree
    let tick = controller.applyInterpolations(
      to: &treeCopy,
      at: .now().advanced(by: .milliseconds(100))
    )

    #expect(tick.hasPendingWork)
    #expect(!tick.redrawIdentities.isEmpty)

    // Regression guard: the affected identity set MUST intersect the
    // drawn set when the border is inside the viewport.  If this ever
    // flips, the fix has quiesced a legitimate animation and the
    // gallery's chasing-light demo will stop animating on first paint.
    #expect(
      !tick.redrawIdentities.isDisjoint(with: animatedArtifacts.drawnIdentities),
      """
      Expected at least one affected animation identity to be in the frame's \
      drawnIdentities when the border is visible. \
      redrawIdentities=\(tick.redrawIdentities) \
      drawnIdentities.count=\(animatedArtifacts.drawnIdentities.count)
      """
    )
  }
}
