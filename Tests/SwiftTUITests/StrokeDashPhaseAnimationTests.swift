import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// `dashPhase` is an animatable property, which is how a marching-ants border
/// moves. A border keeps its dash in the draw metadata, and a shape stroke and
/// a rule keep theirs in the draw payload, so the slot reads and writes all
/// three.
@MainActor
@Suite
struct StrokeDashPhaseAnimationTests {
  private static let dashed = StrokeStyle(borderSet: .single, dash: [2, 1])

  enum Carrier: String, CaseIterable, Sendable {
    case border
    case shapeStroke
    case rule
  }

  private func node(
    _ carrier: Carrier,
    stroke: StrokeStyle,
    identity: Identity
  ) -> ResolvedNode {
    switch carrier {
    case .border:
      var drawMetadata = DrawMetadata()
      drawMetadata.layoutBorderStroke = stroke
      return ResolvedNode(
        identity: identity,
        kind: .view("Border"),
        layoutBehavior: .border(
          stroke.borderSet,
          placement: .outset,
          foreground: nil,
          background: nil,
          blend: nil,
          blendPhase: 0,
          sides: .all
        ),
        drawMetadata: drawMetadata
      )
    case .shapeStroke:
      return ResolvedNode(
        identity: identity,
        kind: .view("Shape"),
        drawPayload: .shape(
          ShapePayload(
            geometry: .rectangle,
            operation: .stroke(style: nil, strokeStyle: stroke, strokeBorder: false)
          ))
      )
    case .rule:
      return ResolvedNode(
        identity: identity,
        kind: .view("Divider"),
        drawPayload: .rule(stroke)
      )
    }
  }

  /// Seeds the controller at phase 0, then presents phase 3 under an explicit
  /// animation and samples the linear curve at its midpoint.
  private func interpolated(
    _ carrier: Carrier,
    stroke: StrokeStyle
  ) -> (node: ResolvedNode, pending: Bool) {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)
    // Each call has its own controller, so one name serves every carrier.
    let identity = Identity(components: [.named("dash")])

    var start = stroke
    start.dashPhase = 0
    var end = stroke
    end.dashPhase = 3

    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      node(carrier, stroke: start, identity: identity),
      transaction: .init(),
      timestamp: t0
    )
    var frame = node(carrier, stroke: end, identity: identity)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame, transaction: transaction, timestamp: t0)

    let result = controller.applyInterpolations(
      to: &frame, at: t0.advanced(by: .milliseconds(500)))
    return (frame, result.hasPendingWork)
  }

  @Test("withAnimation interpolates the dash phase", arguments: Carrier.allCases)
  func dashPhaseInterpolates(carrier: Carrier) throws {
    let result = interpolated(carrier, stroke: Self.dashed)
    #expect(result.pending)
    let stroke = try #require(AnimatableSnapshot.dashedStroke(of: result.node))
    // A linear curve from 0 to 3, sampled at its midpoint. A loose "between the
    // endpoints" check would miss a phase that interpolated to 0.01 or 2.99.
    #expect(abs(stroke.dashPhase - 1.5) < 0.06, "got \(stroke.dashPhase)")
    // Only the phase moves.
    #expect(stroke.dash == [2, 1])
    #expect(stroke.borderSet == .single)
  }

  @Test("a solid stroke has no phase to animate", arguments: Carrier.allCases)
  func solidStrokeHasNoSlot(carrier: Carrier) {
    let solid = StrokeStyle(borderSet: .single)
    #expect(
      AnimatableSnapshot.dashedStroke(
        of: node(carrier, stroke: solid, identity: Identity(components: [.named("solid")])))
        == nil)
    // A changing phase on a solid stroke draws nothing, so it starts no
    // animation.
    #expect(!interpolated(carrier, stroke: solid).pending)
  }

  @Test("the dashed set animates too, because it implies a dash")
  func impliedDashAnimates() throws {
    let result = interpolated(.border, stroke: StrokeStyle(borderSet: .dashed))
    #expect(result.pending)
    let stroke = try #require(AnimatableSnapshot.dashedStroke(of: result.node))
    #expect(abs(stroke.dashPhase - 1.5) < 0.06, "got \(stroke.dashPhase)")
  }

  @Test("an animating phase leaves a border's layout behavior as it was")
  func phaseStaysOutOfLayout() {
    let identity = Identity(components: [.named("layout")])
    let resting = node(.border, stroke: Self.dashed, identity: identity)
    let moving = interpolated(.border, stroke: Self.dashed).node
    // The phase lives in the draw metadata, so the layout behavior is not just
    // equivalent for measurement: it is equal.
    #expect(moving.layoutBehavior == resting.layoutBehavior)
    #expect(moving.layoutBehavior.isEquivalentForMeasurement(to: resting.layoutBehavior))
  }

  @Test("the phase is not a layout-affecting animation")
  func phaseIsNotLayoutAffecting() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)
    let identity = Identity(components: [.named("not-layout")])
    var end = Self.dashed
    end.dashPhase = 3
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      node(.border, stroke: Self.dashed, identity: identity),
      transaction: .init(), timestamp: t0)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      node(.border, stroke: end, identity: identity), transaction: transaction, timestamp: t0)
    #expect(!controller.hasLayoutAffectingPropertyAnimation)
  }
}
