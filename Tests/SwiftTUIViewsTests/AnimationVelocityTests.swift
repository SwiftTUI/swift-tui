import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Unit pins for the seeded-velocity evaluation on `Animation` (plan
/// 2026-08-25-002 T4): the sign convention, the `speed(_:)` folding, and the
/// built-in velocity query.
@Suite("Animation seeded velocity")
struct AnimationVelocityTests {
  private static func progress(
    _ animation: Animation,
    at elapsed: Duration,
    initialVelocity: Double?
  ) -> Double? {
    var state = AnimationState()
    return animation.evaluate(elapsed: elapsed, state: &state, initialVelocity: initialVelocity)
  }

  @Test("a positive seeded velocity moves a spring toward its target faster; negative, away first")
  func seededVelocitySign() throws {
    let spring = Animation.spring(duration: .seconds(1), bounce: 0)
    let rest = try #require(Self.progress(spring, at: .milliseconds(40), initialVelocity: nil))
    let forward = try #require(Self.progress(spring, at: .milliseconds(40), initialVelocity: 5))
    let backward = try #require(Self.progress(spring, at: .milliseconds(40), initialVelocity: -5))
    #expect(forward > rest, "\(forward) vs \(rest)")
    #expect(backward < rest, "\(backward) vs \(rest)")
    #expect(backward < 0, "a velocity away from the target dips below the start first")
    // The seeded slope is the velocity itself (progress per second).
    let slope = try #require(
      spring.velocity(elapsed: .zero, state: AnimationState(), initialVelocity: 5))
    #expect(abs(slope - 5) < 0.2, "\(slope)")
  }

  @Test("bezier and custom curves ignore the seeded velocity")
  func bezierIgnoresVelocity() throws {
    let curve = Animation.easeInOut(duration: .milliseconds(400))
    let rest = try #require(Self.progress(curve, at: .milliseconds(100), initialVelocity: nil))
    let seeded = try #require(Self.progress(curve, at: .milliseconds(100), initialVelocity: 9))
    #expect(rest == seeded)
  }

  @Test("speed(_:) folds into the seeded velocity")
  func speedFoldsIntoVelocity() throws {
    let base = Animation.spring(duration: .seconds(1), bounce: 0.2)
    let fast = base.speed(2)
    // A doubled speed at elapsed `e` is the base curve at `2e` released with
    // half the elapsed-time velocity.
    for millis in [10, 50, 120, 300] {
      let fastValue = try #require(
        Self.progress(fast, at: .milliseconds(millis), initialVelocity: 4)
      )
      let baseValue = try #require(
        Self.progress(base, at: .milliseconds(2 * millis), initialVelocity: 2)
      )
      #expect(abs(fastValue - baseValue) < 1e-9, "\(millis) ms: \(fastValue) vs \(baseValue)")
    }
  }

  @Test("the built-in velocity query matches the curve's slope")
  func builtInVelocityQuery() throws {
    let linear = Animation.linear(duration: .seconds(2))
    let slope = try #require(linear.velocity(elapsed: .milliseconds(500), state: AnimationState()))
    #expect(abs(slope - 0.5) < 1e-3, "\(slope)")

    let spring = Animation.spring(duration: .milliseconds(500), bounce: 0)
    let early = try #require(spring.velocity(elapsed: .milliseconds(100), state: AnimationState()))
    #expect(early > 0)
    #expect(
      spring.velocity(elapsed: .seconds(30), state: AnimationState()) == nil,
      "settled curves report nil")
  }

  @Test("a spring released toward its target does not report settled at the zero crossing")
  func seededSpringSurvivesZeroCrossing() {
    // Critically damped, a strong toward-target kick: the displacement
    // crosses zero once, and the crossing must not end the animation.
    let solver = SpringSolver(duration: 0.5, bounce: 0, initialVelocity: 60)
    var crossedZero = false
    var reportedSettledAtCrossing = false
    var t = 0.0
    var previous = 1.0
    while t < 0.3 {
      let sample = solver.displacement(at: t)
      if previous > 0 && sample <= 0 { crossedZero = true }
      if abs(sample) < 0.001 && solver.value(at: t) == nil && abs(solver.velocity(at: t)) > 0.1 {
        reportedSettledAtCrossing = true
      }
      previous = sample
      t += 0.0005
    }
    #expect(crossedZero, "the fixture must actually overshoot")
    #expect(!reportedSettledAtCrossing)
    #expect(solver.value(at: 5) == nil, "and it does settle eventually")
  }
}
