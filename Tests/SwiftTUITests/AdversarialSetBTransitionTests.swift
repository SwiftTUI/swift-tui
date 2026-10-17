// Adversarial set B, pass 3: transitions, transactions and curve solvers
// (221–230).
//
// The built-in transitions are value recipes (`TransitionModifiers`) that
// the overlay sampler interpolates in whole cells; curves and springs are
// solved in `Double` and quantized late. These probes sit where the recipe
// and the sampler disagree with SwiftUI's transition semantics (one-row
// moves, composed transitions, `push`), where a transaction field is lost,
// where a curve or schedule is sampled outside the range its solver assumes,
// and where a spring's bounce leaves the documented domain.
import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: transitions and curves")
struct AdversarialSetBTransitionTests {
  // A one-row view removed with `.move(edge: .top)` is off its edge on the
  // last sampled frame: the offset rounds to the whole cell it has crossed.
  @Test func setB221OneRowMoveRemovalLeavesItsEdgeBeforeTheLastFrame() {
    let target = TransitionModifiers(moveEdge: .top)
    let oneRow = AnimationTransitionOverlay.interpolatedRemovalModifiers(
      from: 1, to: target, progress: 0.99, edgeBasis: CellSize(width: 5, height: 1))
    let threeRows = AnimationTransitionOverlay.interpolatedRemovalModifiers(
      from: 1, to: target, progress: 0.99, edgeBasis: CellSize(width: 5, height: 3))
    withKnownIssue(
      "offsets truncate toward zero and progress 1 is never sampled, so a one-row move never moves"
    ) {
      #expect(oneRow.offsetY == -1, "\(String(describing: oneRow.offsetY))")
      #expect(threeRows.offsetY == -3, "\(String(describing: threeRows.offsetY))")
    }
    let half = AnimationTransitionOverlay.interpolatedRemovalModifiers(
      from: 1, to: target, progress: 0.5, edgeBasis: CellSize(width: 5, height: 4))
    #expect(half.offsetY == -2, "\(String(describing: half.offsetY))")
  }

  // `combined(with:)` composes both transitions: two moves travel
  // diagonally and two offsets add; asymmetric halves stay separate.
  @Test func setB222CombinedTransitionsComposeInsteadOfReplacing() {
    let diagonal = AnyTransition.move(edge: .leading).combined(with: .move(edge: .top))
      .insertionModifiers().resolvedOffset(edgeBasis: CellSize(width: 4, height: 2))
    let offsets = AnyTransition.offset(x: 2).combined(with: .offset(x: 3)).removalModifiers()
    withKnownIssue(
      "merging keeps one moveEdge and one offset per axis, so the second transition replaces the first"
    ) {
      #expect(diagonal.x == -4 && diagonal.y == -2, "\(diagonal)")
      #expect(offsets.offsetX == 5, "\(String(describing: offsets.offsetX))")
    }
    let asymmetric = AnyTransition.asymmetric(insertion: .move(edge: .leading), removal: .opacity)
    #expect(asymmetric.insertionModifiers().moveEdge == .leading)
    #expect(asymmetric.insertionModifiers().opacity == nil)
    #expect(asymmetric.removalModifiers().opacity == 0)
    #expect(asymmetric.removalModifiers().moveEdge == nil)
    let mixed = AnyTransition.offset(x: 2).combined(with: .move(edge: .leading))
      .insertionModifiers().resolvedOffset(edgeBasis: CellSize(width: 4, height: 1))
    #expect(mixed.x == -2 && mixed.y == 0, "\(mixed)")
  }

  // `push(from:)` moves in while fading in and moves out toward the opposite
  // edge while fading out.
  @Test func setB223PushTransitionFadesAsWellAsMoves() {
    let push = AnyTransition.push(from: .leading)
    let insertion = push.insertionModifiers()
    let removal = push.removalModifiers()
    #expect(insertion.moveEdge == .leading, "\(String(describing: insertion.moveEdge))")
    #expect(removal.moveEdge == .trailing, "\(String(describing: removal.moveEdge))")
    withKnownIssue("push builds a move-only recipe with no opacity") {
      #expect(insertion.opacity == 0, "\(String(describing: insertion.opacity))")
      #expect(removal.opacity == 0, "\(String(describing: removal.opacity))")
    }
  }

  // `disablesAnimations` and `animation` are independent transaction fields:
  // clearing the flag keeps the carried animation.
  @Test func setB224ClearingDisablesAnimationsKeepsTheCarriedAnimation() {
    var transaction = Transaction(animation: .linear(duration: .seconds(1)))
    #expect(transaction.animation == .linear(duration: .seconds(1)))
    transaction.disablesAnimations = false
    withKnownIssue("the setter rewrites the request to .inherit, dropping the animation") {
      #expect(
        transaction.animation == .linear(duration: .seconds(1)),
        "\(String(describing: transaction.animation))")
    }
    var disabled = Transaction(animation: .linear(duration: .seconds(1)))
    disabled.disablesAnimations = true
    #expect(disabled.disablesAnimations)
    #expect(disabled.animation == nil)
    let bare = Transaction(animation: nil)
    withKnownIssue(
      "Transaction(animation: nil) reads as disablesAnimations == true, where SwiftUI inherits"
    ) {
      #expect(!bare.disablesAnimations, "a nil animation is inherit, not disabled")
    }
  }

  // A Bézier timing curve with control-point x outside 0…1 clamps like
  // SwiftUI's, so eased progress stays monotone.
  @Test func setB225BezierControlPointsOutsideTheUnitRangeStayMonotone() {
    let curve = UnitCurve.bezier(
      startControlPoint: UnitPoint(x: 2, y: 0), endControlPoint: UnitPoint(x: -1, y: 1))
    let samples = stride(from: 0.0, through: 1.0, by: 0.05).map { curve.value(at: $0) }
    let monotone = zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 }
    withKnownIssue(
      "the solver takes raw control points and picks a non-monotone root for x(t) (adjacent to STUI-963)"
    ) {
      #expect(monotone, "\(samples.map { ($0 * 1000).rounded() / 1000 })")
    }
    #expect(abs(curve.value(at: 0) - 0) < 1e-9)
    #expect(abs(curve.value(at: 1) - 1) < 1e-9)
    let clamped = UnitCurve.bezier(
      startControlPoint: UnitPoint(x: 1, y: 0), endControlPoint: UnitPoint(x: 0, y: 1))
    let clampedSamples = stride(from: 0.0, through: 1.0, by: 0.05).map { clamped.value(at: $0) }
    #expect(zip(clampedSamples, clampedSamples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
  }

  // A periodic schedule asked for entries from an instant exactly on its grid
  // emits that instant first.
  @Test func setB226PeriodicScheduleEmitsAnExactGridInstantFirst() throws {
    let schedule = PeriodicTimelineSchedule(
      from: MonotonicInstant(offset: .zero), by: .milliseconds(700))
    var entries = schedule.entries(
      from: MonotonicInstant(offset: .milliseconds(2100)), mode: .normal
    )
    .makeIterator()
    let firstEntry = entries.next()
    let first = try #require(firstEntry)
    withKnownIssue(
      "the grid index is computed in Double seconds, so 2.1/0.7 rounds up to the next tick"
    ) {
      #expect(first == MonotonicInstant(offset: .milliseconds(2100)), "\(first)")
    }
    var aligned = schedule.entries(
      from: MonotonicInstant(offset: .milliseconds(1400)), mode: .normal
    )
    .makeIterator()
    let secondEntry = aligned.next()
    let second = try #require(secondEntry)
    #expect(second == MonotonicInstant(offset: .milliseconds(1400)), "\(second)")
    var between = schedule.entries(
      from: MonotonicInstant(offset: .milliseconds(1500)), mode: .normal
    )
    .makeIterator()
    let betweenEntry = between.next()
    #expect(
      betweenEntry == MonotonicInstant(offset: .milliseconds(2100)),
      "\(String(describing: betweenEntry))")
  }

  // A spring's bounce is bounded at 1: a larger value is clamped to the
  // undamped spring instead of producing divergent or NaN motion.
  @Test func setB227SpringBounceAboveOneIsClamped() async {
    let overshoot: Double = Spring(duration: .milliseconds(500), bounce: 1.5)
      .value(target: 1.0, initialVelocity: 0.0, time: .seconds(2))
    let ratio = Spring(duration: .milliseconds(500), bounce: 2.5).dampingRatio
    let nan: Double = Spring(duration: .milliseconds(500), bounce: 2.5)
      .value(target: 1.0, initialVelocity: 0.0, time: .milliseconds(100))
    withKnownIssue(
      "dampingRatio = 1 - bounce is not clamped: motion diverges and turns NaN past bounce 2 (adjacent to STUI-966)"
    ) {
      #expect(overshoot >= -1 && overshoot <= 2, "\(overshoot)")
      #expect(ratio >= 0, "\(ratio)")
      #expect(nan.isFinite, "\(nan)")
    }
    await withKnownIssue("an Int spring value scales by NaN and traps") {
      await #expect(processExitsWith: .success) {
        let value: Int = Spring(duration: .milliseconds(500), bounce: 2.5)
          .value(target: 10, initialVelocity: 0, time: .milliseconds(100))
        #expect(value >= 0 && value <= 10, "\(value)")
      }
    }
    let valid: Double = Spring(duration: .milliseconds(500), bounce: 0.3)
      .value(target: 1.0, initialVelocity: 0.0, time: .seconds(2))
    #expect(abs(valid - 1) < 0.05, "\(valid)")
  }

  // An undamped spring either completes within its reported total duration
  // or reports no total duration; it does not promise an end it never reaches.
  @Test func setB228UndampedSpringDurationAndCompletionAgree() throws {
    let animation = Animation.spring(duration: .milliseconds(500), bounce: 1)
    let total = animation.totalDuration
    let stillRunning = animation.evaluate(elapsed: .seconds(30)) != nil
    withKnownIssue("a zero-damping spring reports a one second total but never settles") {
      if let total {
        #expect(!stillRunning, "reported total \(total) but still running at 30 s")
      }
    }
    let settling = Spring(duration: .milliseconds(500), bounce: 1).settlingDuration
    #expect(settling <= .seconds(60), "\(settling)")
    let damped = Animation.spring(duration: .milliseconds(500), bounce: 0.2)
    let dampedTotal = try #require(damped.totalDuration)
    withKnownIssue(
      "a damped spring's reported total duration ends before its evaluation settles (adjacent to STUI-966)"
    ) {
      #expect(damped.evaluate(elapsed: dampedTotal + .milliseconds(1)) == nil)
    }
    #expect(damped.evaluate(elapsed: dampedTotal + .seconds(5)) == nil, "it settles eventually")
  }

  // Curve endpoints are exact and the symmetric curves are symmetric.
  @Test func setB229CurveEndpointsAndSymmetryHold() throws {
    #expect(BezierSolver.easeInOut.progress(for: 0) == 0)
    #expect(BezierSolver.easeInOut.progress(for: 1) == 1)
    #expect(BezierSolver.easeIn.progress(for: 0) == 0)
    #expect(BezierSolver.easeOut.progress(for: 1) == 1)
    let linear = Animation.linear(duration: .seconds(1))
    #expect(try #require(linear.evaluate(elapsed: .zero)) == 0)
    #expect(linear.evaluate(elapsed: .seconds(1)) == nil, "complete at the end")
    let nearEnd = try #require(linear.evaluate(elapsed: .seconds(1) - .nanoseconds(1)))
    #expect(abs(nearEnd - 1) < 1e-6, "\(nearEnd)")
    for t in [0.1, 0.25, 0.4] {
      let a = BezierSolver.easeInOut.progress(for: t)
      let b = BezierSolver.easeInOut.progress(for: 1 - t)
      #expect(abs(a + b - 1) < 1e-6, "t=\(t): \(a) + \(b)")
    }
    #expect(Animation.timingCurve(0.42, 0, 1, 1) == .easeIn())
    #expect(Animation.timingCurve(0, 0, 0.58, 1) == .easeOut())
  }

  // Numeric text rolls per ASCII digit column; a non-ASCII digit fades the
  // new glyph in, and a length change pairs columns right-aligned.
  @Test func setB230NumericTextRollsASCIIDigitsAndFadesTheRest() {
    let transition = TextContentTransition(kind: .numericText)
    let arabic = TextRollValue(text: "١٢", transition: transition)
      .rolling(to: TextRollValue(text: "١٣", transition: transition), progress: 0.5)
    #expect(arabic.renderedText == "١٣", "\(arabic.renderedText)")
    let opacities = arabic.renderedColumns().map(\.opacity)
    #expect(opacities == [1, 0.5], "\(opacities)")

    let ascii = TextRollValue(text: "12", transition: transition)
      .rolling(to: TextRollValue(text: "19", transition: transition), progress: 0.5)
    #expect(ascii.renderedText == "16", "\(ascii.renderedText)")

    let shrink = TextRollValue(text: "100", transition: transition)
      .rolling(to: TextRollValue(text: "99", transition: transition), progress: 0.5)
    #expect(shrink.renderedText.count == 2, "\(shrink.renderedText)")
    #expect(shrink.renderedText.allSatisfy { $0.isASCII && $0.isNumber }, "\(shrink.renderedText)")
  }
}
