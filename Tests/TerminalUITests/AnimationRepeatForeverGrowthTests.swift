import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Regression pins for the "gallery freezes on the chasing-light panel"
/// bug.
///
/// The user's repro: navigate to the Borders & Shapes tab, which mounts
/// a `BorderBlend` chasing-light animation under
/// `withAnimation(.linear(duration: .milliseconds(3000)).repeatForever)`
/// alongside a `Canvas` sparkline further down the same `ScrollView`
/// content.  Once the animation is in flight every 33 ms tick frame
/// pegs the run loop at ~30 ms / frame.  Removing `.onAppear` (so the
/// animation never starts) makes the freeze go away; switching to a
/// short, non-repeating animation makes it less noticeable.
///
/// Diagnosis (see commit message): two distinct measurement-cache
/// equivalence bugs were both kicking in.
///
///   1. ``LayoutBehavior.border``'s `==` includes the cosmetic
///      `blendPhase` field, so two borders that differ only in their
///      animated phase reported "not equivalent" and forced the layout
///      cache to re-measure them on every tick.
///   2. ``DrawPayload.isEquivalentForMeasurement`` had no `.canvas`
///      case at all and fell through to `default: return false`, so a
///      `Canvas` leaf reported "not equivalent" against itself even
///      when its drawing was byte-for-byte identical.
///
/// Both bugs cascade up the ancestor spine via the recursive
/// `ResolvedNode.isEquivalentForMeasurement` walk: a single leaf that
/// fails the equivalence check invalidates every ancestor's cached
/// measurement.  In the gallery, the canvas at the bottom of the
/// borders tab caused the entire tab's ancestor spine to re-measure
/// on every chasing-light tick.
///
/// These tests pin both fixes:
///
///   * `borderBlendPhase` mutations alone do not invalidate the
///     measurement cache.
///   * Identical `Canvas` payloads are measurement-equivalent.
///   * A view that pairs an animated border with a `Canvas` further
///     down the tree drives ZERO `measuredNodesComputed` per tick
///     across many frames.
@MainActor
@Suite("Animation chasing-light tick frames must not invalidate the measure cache")
struct AnimationRepeatForeverGrowthTests {
  // MARK: - Equivalence-predicate unit pins

  @Test("LayoutBehavior.border equivalence ignores blendPhase")
  func borderLayoutBehaviorEquivalenceIgnoresPhase() {
    let phaseA = LayoutBehavior.border(
      .rounded,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .all
    )
    let phaseB = LayoutBehavior.border(
      .rounded,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.42,
      sides: .all
    )
    #expect(
      phaseA != phaseB,
      "two borders with distinct blendPhase values must differ under ==, or there is no animation phase to interpolate at all"
    )
    #expect(
      phaseA.isEquivalentForMeasurement(to: phaseB),
      "blendPhase is a draw-time-only field, so layout-measurement equivalence must ignore it"
    )

    // Sanity check: the carve-out must NOT swallow border changes that
    // actually do affect layout (set or sides).
    let differentSet = LayoutBehavior.border(
      .double,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .all
    )
    #expect(
      !phaseA.isEquivalentForMeasurement(to: differentSet),
      "different BorderSet values change borderLayoutInsets and must invalidate the cache"
    )
    let differentSides = LayoutBehavior.border(
      .rounded,
      foreground: nil,
      background: nil,
      blend: BorderBlend([.red, .blue, .red]),
      blendPhase: 0.31,
      sides: .top
    )
    #expect(
      !phaseA.isEquivalentForMeasurement(to: differentSides),
      "different sides masks change borderLayoutInsets and must invalidate the cache"
    )
  }

  @Test("DrawPayload.canvas equivalence treats canvases as measurement-equivalent")
  func canvasDrawPayloadIsMeasurementEquivalent() {
    let lhs = DrawPayload.canvas(CanvasPayload(drawing: ProbeCanvasDrawing(value: 1)))
    let rhs = DrawPayload.canvas(CanvasPayload(drawing: ProbeCanvasDrawing(value: 2)))
    // Two canvases must be equivalent for measurement EVEN WHEN their
    // drawings differ.  The layout engine routes `.canvas` through the
    // same path as `.shape`: the cell frame is reserved by the parent's
    // proposal and the drawing is rasterized at paint time.  Drawings
    // never contribute to size — see ``LayoutEngine.measuredCellSize``,
    // ``case .canvas``.
    #expect(lhs.isEquivalentForMeasurement(to: rhs))
  }

  // MARK: - Pipeline integration

  @Test(
    "animated border + Canvas leaf drives zero measure churn across many ticks",
    arguments: [50, 200]
  )
  func animatedBorderWithCanvasLeafDoesNotChurnMeasurement(tickCount: Int) throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    AnimationRegistrationStorage.currentSink = controller
    TransitionRegistrationStorage.currentSink = controller
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let animation = Animation.linear(duration: .milliseconds(3000))
      .repeatForever(autoreverses: false)
    controller.register(animation)

    let blend = BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red])
    let rootIdentity = Identity(components: [.named("ChasingLightCanvasRepro")])

    @MainActor
    func body(phase: Double) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("chasing light")
          .padding(1)
          .frame(width: 30, height: 3)
          .border(
            blend: blend,
            set: .rounded,
            phase: phase
          )
        // The Canvas leaf is what surfaced bug #2 in the gallery: every
        // animation tick invalidated its measurement cache via the
        // missing `.canvas` case in DrawPayload.isEquivalentForMeasurement,
        // which cascaded up the ancestor spine.  Pin it here too so any
        // future regression in the canvas equivalence walk fires this
        // test, not just the gallery smoke test.
        Canvas(ProbeCanvasDrawing(value: 7))
          .frame(width: 30, height: 4)
      }
    }

    // Frame 1: seed render at phase 0, no animation intent.
    _ = renderer.render(
      body(phase: 0),
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(40), height: .finite(20))
    )

    // Mirror the run loop's "after first frame" switch into selective
    // dirty evaluation, so subsequent renders take the same code paths
    // a real tick frame would take.
    renderer.enableSelectiveEvaluation()

    // Frame 2: explicit animate transaction starts the chasing-light
    // animation.  This is the equivalent of the run loop committing
    // `.onAppear { withAnimation(...) { gradientPhase = 1.0 } }`.
    var animateTransaction = TransactionSnapshot()
    animateTransaction.animationRequest = .animate(animation.animationBox)
    _ = renderer.render(
      body(phase: 1.0),
      context: ResolveContext(
        identity: rootIdentity,
        transaction: animateTransaction
      ),
      proposal: ProposedSize(width: .finite(40), height: .finite(20))
    )

    // Drive `tickCount` tick frames.  Each tick constructs the same
    // view (phase unchanged at the @State level — the animation
    // controller is what drives the per-frame interpolation) and
    // routes the controller's dominantActiveRequest back in as the
    // transaction, mirroring `RunLoop.resolveContext(for:)` exactly.
    var measureCounts: [Int] = []
    var activeAnimationCounts: [Int] = []
    for _ in 0..<tickCount {
      var tickTransaction = TransactionSnapshot()
      tickTransaction.animationRequest =
        controller.dominantActiveRequest() ?? .inherit
      let artifacts = renderer.render(
        body(phase: 1.0),
        context: ResolveContext(
          identity: rootIdentity,
          transaction: tickTransaction
        ),
        proposal: ProposedSize(width: .finite(40), height: .finite(20))
      )
      measureCounts.append(artifacts.diagnostics.measuredNodesComputed)
      activeAnimationCounts.append(controller.activeAnimationCount)
    }

    let maxMeasured = measureCounts.max() ?? 0
    #expect(
      maxMeasured == 0,
      """
      tick frames must reuse 100% of the measurement cache; \
      maxMeasuredNodesComputed=\(maxMeasured) \
      counts@[0,1,9,49]=\
      [\(measureCounts.first ?? -1),\
      \(measureCounts.dropFirst().first ?? -1),\
      \(measureCounts.dropFirst(9).first ?? -1),\
      \(measureCounts.dropFirst(49).first ?? -1)]
      """
    )

    let maxActive = activeAnimationCounts.max() ?? 0
    let firstActive = activeAnimationCounts.first ?? 0
    #expect(
      maxActive <= firstActive,
      """
      activeAnimationCount must stay bounded across repeatForever ticks; \
      first=\(firstActive) max=\(maxActive)
      """
    )
  }
}

/// Test-only ``CanvasDrawing`` whose `==` distinguishes drawings by an
/// integer payload.  Used by the canvas-equivalence pins above.
private struct ProbeCanvasDrawing: CanvasDrawing, Equatable {
  let value: Int

  func draw(into context: inout CanvasContext) {
    // No-op: the layout cache reuse contract is independent of what
    // the drawing actually paints.
  }
}
