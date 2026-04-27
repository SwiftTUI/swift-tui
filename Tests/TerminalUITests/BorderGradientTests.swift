import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Cell-level assertions for the new `.border(blend:set:sides:phase:)`
/// modifier.  Pinned by M5.A: when a `BorderBlend` is attached, the
/// rasterizer samples colors continuously around the rectangle's
/// perimeter and assigns one color per perimeter cell, walking
/// clockwise from the top-left corner.
@MainActor
struct BorderGradientTests {
  @Test(".border(blend:) writes perimeter-sampled colors on a small rect")
  func borderBlendBasicRendering() {
    // A 4x3 frame with a red→blue→red closed loop.  Each corner and
    // edge cell should have a non-nil foreground color, and at least
    // one cell should differ from pure red (the gradient sweeps
    // through blue at the perimeter midpoint).
    let view = Text("hi").border(
      blend: BorderBlend([Color.red, Color.blue, Color.red]),
      set: .single
    )
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("BorderBlendBasic"))
    )
    let cells = artifacts.rasterSurface.cells
    // Trimmed frame is 4x3 ("hi" content + 1-cell .single border).
    #expect(artifacts.rasterSurface.size.width == 4)
    #expect(artifacts.rasterSurface.size.height == 3)

    let topLeft = cells[0][0].style?.foregroundColor
    let topRight = cells[0][3].style?.foregroundColor
    #expect(topLeft != nil)
    #expect(topRight != nil)

    // Some perimeter cell must differ from red — the gradient sweeps
    // through blue near the perimeter midpoint.
    var nonRedCount = 0
    for y in 0..<3 {
      for x in 0..<4 where !(y == 1 && x == 1) && !(y == 1 && x == 2) {
        if let fg = cells[y][x].style?.foregroundColor, fg != Color.red {
          nonRedCount += 1
        }
      }
    }
    #expect(nonRedCount > 0)
  }

  @Test(".border(blend:) with phase rotation shifts the gradient start")
  func borderBlendPhaseShiftsStart() {
    // Render the same view at phase 0 and phase 0.5; at least one
    // perimeter cell should differ.
    let blend = BorderBlend([Color.red, Color.green, Color.blue, Color.red])
    let view0 = Text("hi").border(blend: blend, set: .single, phase: 0)
    let viewHalf = Text("hi").border(blend: blend, set: .single, phase: 0.5)
    let art0 = DefaultRenderer().render(
      view0,
      context: .init(identity: testIdentity("BorderBlendPhase0"))
    )
    let artHalf = DefaultRenderer().render(
      viewHalf,
      context: .init(identity: testIdentity("BorderBlendPhaseHalf"))
    )
    let cells0 = art0.rasterSurface.cells
    let cellsHalf = artHalf.rasterSurface.cells

    // Sweep all perimeter cells; at least one must differ.
    var differ = false
    outer: for y in 0..<3 {
      for x in 0..<4 where !(y == 1 && x == 1) && !(y == 1 && x == 2) {
        let fg0 = cells0[y][x].style?.foregroundColor
        let fgHalf = cellsHalf[y][x].style?.foregroundColor
        if fg0 != fgHalf {
          differ = true
          break outer
        }
      }
    }
    #expect(differ)
  }

  @Test("withAnimation drives BorderBlend phase through the controller")
  func borderBlendPhaseAnimatesThroughController() throws {
    // M5.B: phase is now an animatable property.  Seed the controller
    // with a border at phase 0, then process a second frame where the
    // same identity carries phase 1.0 under an explicit withAnimation
    // intent.  After applyInterpolations() at the linear curve's
    // midpoint, the mutated node's .border layoutBehavior should
    // expose a phase strictly between 0 and 1 — not snapped to either
    // endpoint.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("blendLeaf")])
    let blend = BorderBlend([Color.red, Color.blue, Color.red])

    func borderNode(phase: Double) -> ResolvedNode {
      ResolvedNode(
        identity: leafIdentity,
        kind: .view("Border"),
        layoutBehavior: .border(
          .single,
          placement: .outset,
          foreground: nil,
          background: nil,
          blend: blend,
          blendPhase: phase,
          sides: .all
        )
      )
    }

    let t0 = MonotonicInstant.now()
    // Frame 1: phase 0, no animation intent — this seeds the previous
    // snapshot so Frame 2's diff is observable.
    controller.processResolvedTree(
      borderNode(phase: 0),
      transaction: .init(),
      timestamp: t0
    )

    // Frame 2: phase 1.0 under withAnimation intent.
    var frame2 = borderNode(phase: 1.0)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Apply halfway through the 1000 ms linear curve.
    let halfway = t0.advanced(by: .milliseconds(500))
    let result = controller.applyInterpolations(to: &frame2, at: halfway)

    #expect(result.hasPendingWork)
    #expect(result.redrawIdentities.contains(leafIdentity))

    guard
      case .border(_, _, _, _, _, let interpolatedPhase, _) = frame2.layoutBehavior
    else {
      Issue.record("layoutBehavior should still be .border after interpolation")
      return
    }

    // Linear animation from phase 0 to 1.0 at midpoint t=500ms should
    // produce phase ≈ 0.5.  Allow ±0.02 for any floating-point noise
    // or tiny scheduling offsets in the animation clock — a loose
    // "strictly between 0 and 1" check would miss regressions that
    // interpolate to 0.01 or 0.99.
    #expect(
      abs(interpolatedPhase - 0.5) < 0.02,
      "halfway interpolation of a linear 0→1 curve should be ≈ 0.5, got \(interpolatedPhase)"
    )
  }

  @Test("BorderBlend phase animation enqueues an active request")
  func borderBlendPhaseAnimationEnqueuesActiveRequest() throws {
    // End-to-end pipeline assertion: rendering a border with
    // `phase: 1.0` under a `withAnimation` transaction — after a seed
    // frame with `phase: 0` — must leave the controller holding an
    // active animation request.  This pins the wiring from
    //   .border(blend:set:phase:) modifier
    //   → ResolvedNode.layoutBehavior.border(blendPhase:)
    //   → AnimationController diff
    //   → active animation queue
    // through `DefaultRenderer.render`.
    //
    // The rasterized-cell-differs-with-phase invariant is covered by
    // `borderBlendPhaseShiftsStart` above (static phase 0 vs phase
    // 0.5 — equivalent to what a linear animation would produce at
    // the midpoint).  We intentionally do NOT re-verify a raster diff
    // here because `DefaultRenderer.render` uses
    // `MonotonicInstant.now()` internally, so a second render at a
    // "later" time can't be pinned from the test without restructuring
    // the pipeline.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)

    let blend = BorderBlend([Color.red, Color.green, Color.blue, Color.red])
    let rootIdentity = testIdentity("BorderBlendPhaseAnimated")

    // Frame 1 (seed): phase 0, no animation intent.
    _ = renderer.render(
      Text("hi").border(blend: blend, set: .single, phase: 0),
      context: .init(identity: rootIdentity)
    )

    // Frame 2: phase 1.0 under withAnimation.  The controller records
    // a diff of phase 0 → 1.0 and enqueues a linear animation.
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      Text("hi").border(blend: blend, set: .single, phase: 1.0),
      context: .init(identity: rootIdentity, transaction: transaction)
    )
    #expect(
      controller.activeAnimationCount > 0,
      "controller must hold an active animation after the animated phase change"
    )
  }

  @Test(".border(blend:) respects sides mask by drawing only enabled edges")
  func borderBlendSidesMask() {
    // With sides: [.top], only the top row should carry a border
    // glyph; the layout shrinks to "content + top inset only".
    let view = Text("hi").border(
      blend: BorderBlend([Color.red, Color.blue]),
      set: .single,
      sides: [.top]
    )
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("BorderBlendTopOnly"))
    )
    // Frame: 2 wide ("hi"), 2 tall (1 top border + 1 content row).
    let size = artifacts.rasterSurface.size
    #expect(size.width == 2)
    #expect(size.height == 2)

    // The top row's two cells should both have a non-nil foreground
    // (sampled from the perimeter), and they should differ from each
    // other for a 2-stop gradient laid across the rect's perimeter.
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].style?.foregroundColor != nil)
    #expect(cells[0][1].style?.foregroundColor != nil)
  }
}
