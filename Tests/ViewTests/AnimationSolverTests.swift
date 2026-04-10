import Foundation
import Testing

@testable import Core
@testable import View

@Suite("Animation solvers")
struct AnimationSolverTests {
  // MARK: - Spring solver

  @Test("critically damped spring settles without overshoot")
  func criticallyDampedSpringSettles() throws {
    let solver = SpringSolver(duration: 0.5, bounce: 0.0)

    // At t=0, displacement should be close to 1 (full offset).
    let initial = solver.value(at: 0)
    #expect(initial != nil)
    if let initial { #expect(abs(initial - 1.0) < 0.01) }

    // After enough time, the spring should settle to nil (complete).
    let settled = solver.value(at: 2.0)
    #expect(settled == nil)
  }

  @Test("underdamped spring oscillates before settling")
  func underdampedSpringOscillates() throws {
    let solver = SpringSolver(duration: 0.5, bounce: 0.5)

    // Sample several points — at least one should be negative
    // (overshoot) for a bouncy spring.
    var sampleValues: [Double] = []
    for step in 0..<40 {
      let t = Double(step) * 0.025
      if let value = solver.value(at: t) {
        sampleValues.append(value)
      }
    }
    let hasOvershoot = sampleValues.contains { $0 < 0 }
    #expect(hasOvershoot, "underdamped spring should overshoot zero at least once")
  }

  @Test("overdamped spring does not oscillate")
  func overdampedSpringIsMonotonic() throws {
    let solver = SpringSolver(duration: 0.5, bounce: -0.5)

    var lastValue: Double = .infinity
    var isMonotonic = true
    for step in 0..<20 {
      let t = Double(step) * 0.05
      guard let value = solver.value(at: t) else { break }
      if value > lastValue + 0.001 {
        isMonotonic = false
        break
      }
      lastValue = value
    }
    #expect(isMonotonic, "overdamped spring displacement should not increase")
  }

  // MARK: - Bezier solver

  @Test("linear bezier is the identity function")
  func linearBezierIsIdentity() throws {
    let solver = BezierSolver.linear
    for step in 0...10 {
      let x = Double(step) / 10.0
      let y = solver.progress(for: x)
      #expect(abs(y - x) < 0.01)
    }
  }

  @Test("easeInOut bezier starts slow, ends slow")
  func easeInOutBezierIsSCurve() throws {
    let solver = BezierSolver.easeInOut

    let p25 = solver.progress(for: 0.25)
    let p50 = solver.progress(for: 0.50)
    let p75 = solver.progress(for: 0.75)

    // easeInOut is symmetric: p50 should be 0.5.
    #expect(abs(p50 - 0.5) < 0.01)
    // First quarter: progress slower than linear.
    #expect(p25 < 0.25)
    // Last quarter: progress faster than linear before plateau.
    #expect(p75 > 0.75)
  }

  @Test("bezier endpoints are 0 and 1")
  func bezierEndpointsAreExact() throws {
    let solver = BezierSolver.easeInOut
    #expect(solver.progress(for: 0.0) == 0.0)
    #expect(solver.progress(for: 1.0) == 1.0)
  }
}

@Suite("Animation struct factories")
struct AnimationFactoryTests {
  @Test("linear animation evaluates to linear progress")
  func linearAnimationIsLinear() throws {
    let animation = Animation.linear(duration: .milliseconds(1000))

    let p0 = animation.evaluate(elapsed: .zero)
    let p500 = animation.evaluate(elapsed: .milliseconds(500))

    #expect(p0 != nil)
    #expect(p500 != nil)
    if let p500 { #expect(abs(p500 - 0.5) < 0.02) }
  }

  @Test("smooth snappy bouncy produce distinct animations")
  func springPresetsAreDistinct() throws {
    let smooth = Animation.smooth
    let snappy = Animation.snappy
    let bouncy = Animation.bouncy

    #expect(smooth != snappy)
    #expect(snappy != bouncy)
    #expect(smooth != bouncy)
  }

  @Test("delay modifier postpones progress")
  func delayModifierPostpones() throws {
    let base = Animation.linear(duration: .milliseconds(500))
    let delayed = base.delay(.milliseconds(200))

    let p100 = delayed.evaluate(elapsed: .milliseconds(100))
    #expect(p100 != nil)
    // Before the delay has elapsed, progress should be zero.
    if let p100 { #expect(p100 == 0.0) }
  }

  @Test("speed modifier scales the elapsed time")
  func speedModifierScalesTime() throws {
    let base = Animation.linear(duration: .milliseconds(1000))
    let doubleSpeed = base.speed(2.0)

    // At t=250ms under 2× speed, effective elapsed is 500ms → progress 0.5.
    let progress = doubleSpeed.evaluate(elapsed: .milliseconds(250))
    #expect(progress != nil)
    if let progress {
      #expect(abs(progress - 0.5) < 0.02)
    }

    // At t=600ms under 2× speed, effective elapsed is 1200ms → nil (done).
    let done = doubleSpeed.evaluate(elapsed: .milliseconds(600))
    #expect(done == nil)
  }

  @Test("repeatCount runs the curve N times then completes")
  func repeatCountFinite() throws {
    let base = Animation.linear(duration: .milliseconds(100))
    let repeating = base.repeatCount(3, autoreverses: false)

    // Within each of 3 iterations, progress walks 0 → 1.
    // After the 3rd iteration, evaluate returns nil.
    let mid1 = repeating.evaluate(elapsed: .milliseconds(50))
    #expect(mid1 != nil)
    if let mid1 { #expect(abs(mid1 - 0.5) < 0.02) }

    let start2 = repeating.evaluate(elapsed: .milliseconds(105))
    #expect(start2 != nil)
    if let start2 { #expect(start2 < 0.2) }

    let mid3 = repeating.evaluate(elapsed: .milliseconds(250))
    #expect(mid3 != nil)
    if let mid3 { #expect(abs(mid3 - 0.5) < 0.02) }

    // Past the 3rd iteration: done.
    let done = repeating.evaluate(elapsed: .milliseconds(350))
    #expect(done == nil)
  }

  @Test("repeatCount autoreverse flips odd iterations")
  func repeatCountAutoreverse() throws {
    let base = Animation.linear(duration: .milliseconds(100))
    let repeating = base.repeatCount(2, autoreverses: true)

    // Iteration 0 (forward): progress runs 0 → 1.
    let fwd = repeating.evaluate(elapsed: .milliseconds(50))
    #expect(fwd != nil)
    if let fwd { #expect(abs(fwd - 0.5) < 0.02) }

    // Iteration 1 (reversed): progress runs 1 → 0, so at local t=50ms
    // the reported value should be 0.5.
    let rev = repeating.evaluate(elapsed: .milliseconds(150))
    #expect(rev != nil)
    if let rev { #expect(abs(rev - 0.5) < 0.02) }

    // At local t=75ms into the reversed iteration, progress should be
    // near 0.25 (one quarter of the way back toward 0).
    let revLate = repeating.evaluate(elapsed: .milliseconds(175))
    #expect(revLate != nil)
    if let revLate { #expect(abs(revLate - 0.25) < 0.02) }
  }

  @Test("repeatForever never returns nil")
  func repeatForeverRunsIndefinitely() throws {
    let base = Animation.linear(duration: .milliseconds(100))
    let forever = base.repeatForever(autoreverses: false)

    // A long time in, still reporting a finite progress.
    let late = forever.evaluate(elapsed: .milliseconds(10_000))
    #expect(late != nil)
  }
}

@Suite("Transaction.animation round-trip")
struct TransactionAnimationGetterTests {
  @Test("Transaction.animation getter returns the concrete set animation")
  func transactionAnimationRoundTrip() throws {
    var transaction = Transaction(request: .inherit)

    // Initially nil (inherit → no concrete animation).
    #expect(transaction.animation == nil)

    // Set a concrete animation and read it back.
    let authored = Animation.easeInOut(duration: .milliseconds(300))
    transaction.animation = authored
    #expect(transaction.animation == authored)

    // Clearing routes to .disabled, which the getter reports as nil.
    transaction.animation = nil
    #expect(transaction.animation == nil)
    #expect(transaction.disablesAnimations)
  }

  @Test("Transaction.animation round-trips a custom animation")
  func transactionAnimationRoundTripsCustom() throws {
    var transaction = Transaction(request: .inherit)
    let authored = Animation(LinearRoundTripAnimation(id: "rt-test"))
    transaction.animation = authored
    // Custom animations hash via the wrapped conformance's hash so
    // equality across the box round-trip should hold.
    #expect(transaction.animation == authored)
  }
}

/// Minimal CustomAnimation conformance used by the Transaction
/// round-trip test.  Identical shape to the controller-side test's
/// conformance but lives in the View test target to keep symbol
/// visibility simple.
struct LinearRoundTripAnimation: CustomAnimation {
  let id: String

  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V? {
    value
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}
