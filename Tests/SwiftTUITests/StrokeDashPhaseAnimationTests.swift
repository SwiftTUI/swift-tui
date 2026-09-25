@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
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

  // MARK: - Trim

  /// Seeds the controller with a trim of `0...0.2`, presents `0...1` under an
  /// explicit animation, and samples the linear curve at its midpoint.
  private func interpolatedTrim(from start: StrokeTrim?, to end: StrokeTrim?) -> (
    node: ResolvedNode, pending: Bool
  ) {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1000))
    controller.register(animation)
    let identity = Identity(components: [.named("trim")])
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      node(.shapeStroke, stroke: StrokeStyle().trimmed(to: start), identity: identity),
      transaction: .init(), timestamp: t0)
    var frame = node(.shapeStroke, stroke: StrokeStyle().trimmed(to: end), identity: identity)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame, transaction: transaction, timestamp: t0)
    let result = controller.applyInterpolations(
      to: &frame, at: t0.advanced(by: .milliseconds(500)))
    return (frame, result.hasPendingWork)
  }

  @Test("withAnimation interpolates a trim, which is how an outline draws itself on")
  func trimInterpolates() throws {
    let result = interpolatedTrim(
      from: StrokeTrim(from: 0, to: 0.2), to: StrokeTrim(from: 0, to: 1))
    #expect(result.pending)
    let trim = try #require(AnimatableSnapshot.strokeStyle(of: result.node)?.trim)
    #expect(abs(trim.from) < 0.02, "got \(trim.from)")
    #expect(abs(trim.to - 0.6) < 0.03, "got \(trim.to)")
  }

  @Test("a stroke that stays untrimmed starts no trim animation")
  func untrimmedStrokeStartsNoTrimAnimation() {
    #expect(!interpolatedTrim(from: nil, to: nil).pending)
  }

  /// A shape resolves the whole outline as no trim at all, so a draw-on that
  /// ends at `to: 1` and an undraw that starts there cross that boundary.
  @Test("a trim interpolates to and from the whole outline, which a stroke carries as no trim")
  func trimInterpolatesAcrossWholeOutline() throws {
    let (drawOnNode, drawOnPending) = interpolatedTrim(
      from: StrokeTrim(from: 0, to: 0), to: nil)
    #expect(drawOnPending)
    let drawOn = try #require(AnimatableSnapshot.strokeStyle(of: drawOnNode)?.trim)
    #expect(abs(drawOn.from) < 0.02, "got \(drawOn.from)")
    #expect(abs(drawOn.to - 0.5) < 0.03, "got \(drawOn.to)")

    let (undrawNode, undrawPending) = interpolatedTrim(
      from: nil, to: StrokeTrim(from: 0, to: 0))
    #expect(undrawPending)
    let undraw = try #require(AnimatableSnapshot.strokeStyle(of: undrawNode)?.trim)
    #expect(abs(undraw.to - 0.5) < 0.03, "got \(undraw.to)")
  }

  /// The documented Ring: `Circle().trim(from: 0, to: progress).stroke()` under
  /// `withAnimation`, driven by a real click through the run loop and sampled
  /// on a virtual frame clock.
  @Test(
    "a draw-on ring animates through the run loop, including to and from the whole outline",
    arguments: TrimRun.allCases)
  func ringTrimAnimatesThroughRunLoop(run: TrimRun) throws {
    let rootIdentity = testIdentity("RingTrimRunLoop")
    let clock = VirtualFrameClock(MonotonicInstant(offset: .seconds(100)))
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 20, height: 11))
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
      proposal: .init(width: 20, height: 11),
      viewBuilder: { _, _ in RingTrimFixture(start: run.start, end: run.end) }
    )
    runLoop.frameClock = { [clock] in clock.now }
    var renderedFrames = 0
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    let startDots = Self.brailleDots(in: surface.frames.last ?? "")

    let firstLine = try #require(surface.frames.last?.split(separator: "\n").first)
    let button = try #require(firstLine.firstRange(of: "go"))
    let point = Point(
      x: Double(firstLine.distance(from: firstLine.startIndex, to: button.lowerBound)), y: 0)
    let controller = runLoop.renderer.internalAnimationController
    try withAnimationSinks(controller) {
      #expect(runLoop.handle(.input(.mouse(.init(kind: .down(.primary), location: point)))) == nil)
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      #expect(runLoop.handle(.input(.mouse(.init(kind: .up(.primary), location: point)))) == nil)
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    }
    #expect(controller.activeAnimationCount > 0)

    // Each step lands on an overdue animation deadline, so the frame samples
    // the curve at the stepped clock.
    clock.advance(by: .milliseconds(500))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    let midpointDots = Self.brailleDots(in: surface.frames.last ?? "")

    clock.advance(by: .milliseconds(600))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    let endDots = Self.brailleDots(in: surface.frames.last ?? "")
    #expect(controller.activeAnimationCount == 0)

    // The ring grows or shrinks by the trimmed share of its outline, so the
    // linear midpoint is strictly between the two ends.
    let (low, high) = (min(startDots, endDots), max(startDots, endDots))
    #expect(high > low, "start \(startDots), end \(endDots)")
    #expect(
      midpointDots > low && midpointDots < high, "\(startDots) -> \(midpointDots) -> \(endDots)")
  }

  enum TrimRun: String, CaseIterable, Sendable {
    /// `0 -> 0.75`, which never reaches the whole outline.
    case partial
    /// `0 -> 1`, the documented draw-on.
    case drawOn
    /// `0.5 -> 1`.
    case finish
    /// `1 -> 0`.
    case undraw

    var start: Double {
      switch self {
      case .partial, .drawOn: 0
      case .finish: 0.5
      case .undraw: 1
      }
    }

    var end: Double {
      switch self {
      case .partial: 0.75
      case .drawOn, .finish: 1
      case .undraw: 0
      }
    }
  }

  /// Braille dots lit in a presented frame.
  private static func brailleDots(in frame: String) -> Int {
    frame.unicodeScalars.reduce(0) { total, scalar in
      (0x2800...0x28FF).contains(scalar.value)
        ? total + Int(scalar.value - 0x2800).nonzeroBitCount : total
    }
  }
}

@MainActor
private struct RingTrimFixture: View {
  let start: Double
  let end: Double
  @State private var finished = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        withAnimation(.linear(duration: .milliseconds(1_000))) { finished = true }
      }
      Circle()
        .trim(from: 0, to: finished ? end : start)
        .stroke()
        .frame(width: 20, height: 10)
    }
  }
}
