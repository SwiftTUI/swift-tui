import SwiftTUICore
import Testing

@testable import SwiftTUIViews

/// Coverage for the indicator-inset convergence seed (scroll-latency R1.3):
/// the seeded fast path must be measurement-cheaper in the steady state and
/// must never change what the convergence loop computes from scratch — a
/// poisoned seed is refuted by the verification measure and falls back to the
/// cold-start loop unchanged.
@MainActor
struct ScrollViewLayoutInsetSeedTests {
  private static let viewportProposal = ProposedViewSize(
    width: .finite(20),
    height: .finite(10)
  )

  private func contentNode(_ name: String, size: CellSize) -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity(name),
      kind: .view("Content"),
      intrinsicSize: size
    )
  }

  private func verticalScrollLayout() -> ScrollViewLayout {
    ScrollViewLayout(
      axes: .vertical,
      position: .zero,
      indicatorAxes: .vertical
    )
  }

  private func measuredViewport(
    of layout: ScrollViewLayout,
    content: ResolvedNode,
    proposal: ProposedViewSize = viewportProposal
  ) -> (size: LayoutSize, contentMeasures: Int) {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let subviews = [
      LayoutSubview(child: content, engine: engine, passContext: passContext)
    ]
    var cache: Void = ()
    let size = layout.sizeThatFits(
      proposal: proposal,
      subviews: subviews,
      cache: &cache
    )
    return (size, passContext.workMetrics.measuredNodesComputed)
  }

  @Test("A confirmed seed collapses the indicator-shown steady state to one measure")
  func confirmedSeedMeasuresOnce() {
    // 40x100 content in a 20x10 viewport: overflows, vertical indicator shown,
    // so the cold loop measures at the uninset and inset widths (2 measures).
    let content = contentNode("Overflowing", size: .init(width: 40, height: 100))
    let cold = measuredViewport(of: verticalScrollLayout(), content: content)
    #expect(cold.contentMeasures == 2)

    var seeded = verticalScrollLayout()
    seeded.applyRetainedMeasurementSeed(
      previousProposal: Self.viewportProposal,
      previousChildSize: .init(width: 40, height: 100)
    )
    let fast = measuredViewport(of: seeded, content: content)

    #expect(fast.size == cold.size)
    #expect(fast.contentMeasures == 1)
  }

  @Test("A poisoned nonzero seed is refuted and converges to the cold result")
  func poisonedSeedConvergesToColdResult() {
    // 10x5 content fits the 20x10 viewport: no indicator, cold loop converges
    // in one measure. A seed derived from a stale overflowing child size
    // starts the fast path at reserved insets; the verification measure
    // refutes it and the unchanged cold loop recomputes the same result.
    let content = contentNode("Fitting", size: .init(width: 10, height: 5))
    let cold = measuredViewport(of: verticalScrollLayout(), content: content)
    #expect(cold.contentMeasures == 1)

    var poisoned = verticalScrollLayout()
    poisoned.applyRetainedMeasurementSeed(
      previousProposal: Self.viewportProposal,
      previousChildSize: .init(width: 40, height: 100)
    )
    let refuted = measuredViewport(of: poisoned, content: content)

    #expect(refuted.size == cold.size)
    // Exactly one wasted verification measure, then the cold loop's one.
    #expect(refuted.contentMeasures == cold.contentMeasures + 1)
  }

  @Test("A zero seed skips the fast path and is byte-identical to cold start")
  func zeroSeedIsColdStart() {
    let content = contentNode("Tall", size: .init(width: 40, height: 100))
    let cold = measuredViewport(of: verticalScrollLayout(), content: content)

    var seeded = verticalScrollLayout()
    seeded.applyRetainedMeasurementSeed(
      previousProposal: Self.viewportProposal,
      previousChildSize: .init(width: 10, height: 5)
    )
    let result = measuredViewport(of: seeded, content: content)

    #expect(result.size == cold.size)
    #expect(result.contentMeasures == cold.contentMeasures)
  }

  @Test("The worker proxy seeds from the retained session and saves a measure")
  func retainedSessionSeedsThroughProxy() throws {
    let engine = LayoutEngine()
    let proposal = Self.viewportProposal
    let content = contentNode("RetainedContent", size: .init(width: 40, height: 100))
    let scroll = ResolvedNode(
      identity: testIdentity("Scroll"),
      kind: .view("ScrollView"),
      children: [content],
      layoutBehavior: AnyLayout(verticalScrollLayout()).resolvedBehavior
    )

    let firstContext = LayoutPassContext()
    let firstMeasured = engine.measure(scroll, proposal: proposal, passContext: firstContext)
    let firstPlaced = engine.place(
      scroll,
      measured: firstMeasured,
      in: .init(origin: .zero, size: firstMeasured.measuredSize),
      passContext: firstContext
    )

    let previousFrame = FrameArtifacts(
      resolvedTree: scroll,
      measuredTree: firstMeasured,
      placedTree: firstPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: scroll.identity,
        bounds: .init(origin: .zero, size: firstMeasured.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )

    // The scroll route itself is invalidated on a wheel frame, so retained
    // subtree reuse is denied and the container re-measures — exactly the
    // steady-scroll shape the seed exists for.
    let seededContext = LayoutPassContext(
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: .init(frame: previousFrame),
        invalidatedIdentities: [scroll.identity]
      )
    )
    let seededMeasured = engine.measure(scroll, proposal: proposal, passContext: seededContext)

    let freshContext = LayoutPassContext()
    let freshMeasured = engine.measure(scroll, proposal: proposal, passContext: freshContext)

    #expect(seededMeasured.measuredSize == freshMeasured.measuredSize)
    #expect(
      seededMeasured.childMeasurements.map(\.measuredSize)
        == freshMeasured.childMeasurements.map(\.measuredSize)
    )
    #expect(
      seededContext.workMetrics.measuredNodesComputed
        < freshContext.workMetrics.measuredNodesComputed
    )
  }

  @Test("The shadow seed channel feeds the proxy when no session may serve products")
  func measurementSeedSessionSeedsWithoutRetainedServes() throws {
    // The layout shadow oracle's scratch context: `retainedLayout` is nil so
    // no product-reuse tier can serve, but the production session rides
    // `measurementSeedSession` so the hysteresis seam evaluates the same
    // seeds production did. The seeded fast path must engage (one content
    // measure saved) and the result must equal a cold pass for non-knife-edge
    // content.
    let engine = LayoutEngine()
    let proposal = Self.viewportProposal
    let content = contentNode("ShadowSeedContent", size: .init(width: 40, height: 100))
    let scroll = ResolvedNode(
      identity: testIdentity("ShadowSeedScroll"),
      kind: .view("ScrollView"),
      children: [content],
      layoutBehavior: AnyLayout(verticalScrollLayout()).resolvedBehavior
    )

    let firstContext = LayoutPassContext()
    var firstMeasured = engine.measure(scroll, proposal: proposal, passContext: firstContext)
    // The engine's stored child premeasure ran at the container's finite
    // proposal, so an intrinsic-size child clamps to the viewport and the
    // derived seed would be zero. Real scroll content (text, editors) reports
    // its unclamped wrapped extent; mirror that shape so the seed derives the
    // reserved gutter.
    firstMeasured.childMeasurements[0].measuredSize = .init(width: 20, height: 100)
    let firstPlaced = engine.place(
      scroll,
      measured: firstMeasured,
      in: .init(origin: .zero, size: firstMeasured.measuredSize),
      passContext: firstContext
    )
    let previousFrame = FrameArtifacts(
      resolvedTree: scroll,
      measuredTree: firstMeasured,
      placedTree: firstPlaced,
      semanticSnapshot: .init(),
      drawTree: .init(
        identity: scroll.identity,
        bounds: .init(origin: .zero, size: firstMeasured.measuredSize)
      ),
      rasterSurface: .init(),
      presentationDamage: nil,
      commitPlan: .init()
    )

    let shadowContext = LayoutPassContext(
      retainedLayout: nil,
      measurementSeedSession: RetainedLayoutSession(
        previousFrameIndex: .init(frame: previousFrame),
        invalidatedIdentities: []
      )
    )
    let shadowMeasured = engine.measure(scroll, proposal: proposal, passContext: shadowContext)

    let freshContext = LayoutPassContext()
    let freshMeasured = engine.measure(scroll, proposal: proposal, passContext: freshContext)

    #expect(shadowMeasured.measuredSize == freshMeasured.measuredSize)
    #expect(
      shadowContext.workMetrics.measuredNodesReused == 0,
      "the seed channel must never enable a product serve"
    )
    #expect(
      shadowContext.workMetrics.measuredNodesComputed
        < freshContext.workMetrics.measuredNodesComputed
    )
  }
}
