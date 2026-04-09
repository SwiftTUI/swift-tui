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
}
