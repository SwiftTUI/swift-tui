import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Regression pins for the animation tick-gating fix.
///
/// Background: a `.border(blend:)` whose phase is driven by
/// `withAnimation(.linear.repeatForever)` schedules a 30 FPS tick.  If
/// the animated view sits below a `ScrollView` viewport (or inside an
/// inactive `TabView` tab, or behind an opaque overlay) the animation
/// ticks against a subtree whose `DrawNode` bounds are fully clipped.
/// The rasterizer produces identical cells frame-to-frame, damage is
/// empty, and the terminal sees 0 bytes written — but the animation
/// controller keeps saying `hasActiveAnimations = true` and returns a
/// `nextDeadline`, so the scheduler keeps waking and pinning CPU.
///
/// Fix: after each render, compare
/// `animationTick.affectedIdentities` against
/// `artifacts.drawnIdentities` (the set of identities whose placed
/// bounds survived ancestor clipping during the paint walk).  If the
/// intersection is empty the animation is "quiescent against the
/// clip" and the run loop skips `requestDeadline(_:)`.  When any
/// external invalidation — scroll, resize, tab switch, state change —
/// wakes the scheduler, the next frame's visibility check re-runs and
/// the tick loop resumes.
///
/// These tests pin the geometric predicate end-to-end: they drive the
/// `DefaultRenderer` through a seed frame and an animated frame,
/// confirm the animation controller records an active tick, and then
/// assert whether the affected identity actually appears in the
/// frame's `drawnIdentities`.  The run loop uses
/// `affectedIdentities.isDisjoint(with: drawnIdentities)` to decide
/// whether to call `requestDeadline`, so this intersection is the
/// exact invariant that separates "burn CPU" from "quiesce".
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
      controller.dominantActiveRequest() != nil,
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
      tick.hasActiveAnimations,
      "tick result must report active animations while repeatForever is in flight"
    )
    #expect(
      !tick.affectedIdentities.isEmpty,
      "tick must identify at least one affected identity"
    )

    // The whole point of the fix: at least one affected identity
    // exists, but NONE of them appear in the frame's drawnIdentities,
    // because the border sits below the ScrollView's viewport clip.
    // The run loop's `isDisjoint(with:)` check therefore returns
    // true and `requestDeadline` is NOT called.
    #expect(
      tick.affectedIdentities.isDisjoint(with: animatedArtifacts.drawnIdentities),
      """
      Expected every affected animation identity to be geometrically clipped \
      by the ScrollView viewport, so the run loop can skip requestDeadline. \
      affectedIdentities=\(tick.affectedIdentities) \
      drawnIdentities∩affected=\(tick.affectedIdentities.intersection(animatedArtifacts.drawnIdentities))
      """
    )
  }

  @Test("animated border inside visible viewport IS in drawnIdentities")
  func animatedBorderInsideViewportKeepsTicking() throws {
    // Same tree shape, but the viewport is tall enough to include
    // the animated border.  The fix must not break the normal case:
    // affectedIdentities ∩ drawnIdentities must be non-empty so the
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

    #expect(tick.hasActiveAnimations)
    #expect(!tick.affectedIdentities.isEmpty)

    // Regression guard: the affected identity set MUST intersect the
    // drawn set when the border is inside the viewport.  If this ever
    // flips, the fix has quiesced a legitimate animation and the
    // gallery's chasing-light demo will stop animating on first paint.
    #expect(
      !tick.affectedIdentities.isDisjoint(with: animatedArtifacts.drawnIdentities),
      """
      Expected at least one affected animation identity to be in the frame's \
      drawnIdentities when the border is visible. \
      affectedIdentities=\(tick.affectedIdentities) \
      drawnIdentities.count=\(animatedArtifacts.drawnIdentities.count)
      """
    )
  }
}
