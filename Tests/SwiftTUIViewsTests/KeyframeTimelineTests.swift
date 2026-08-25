import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Stage K0 of plan 2026-08-25-002: the pure-value keyframe contract.
/// `KeyframeTimeline` has no runtime dependency, so every claim here is a
/// direct sample of the interpolation math.
@Suite("Keyframe timeline")
struct KeyframeTimelineTests {
  /// A two-track value: `y` and `opacity` interpolate independently.
  private struct Marker: Equatable {
    var y: Double = 0
    var opacity: Double = 1
  }

  private static func seconds(_ value: Double) -> Duration {
    .seconds(value)
  }

  // MARK: - Linear

  @Test("a single linear track reaches `to` at its duration and holds it after")
  func linearTrackReachesTarget() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .milliseconds(400))
    }

    #expect(timeline.duration == .milliseconds(400))
    #expect(timeline.value(time: .zero) == 0)
    #expect(abs(timeline.value(time: .milliseconds(200)) - 5) < 1e-9)
    #expect(timeline.value(time: .milliseconds(400)) == 10)
    #expect(timeline.value(time: .seconds(3)) == 10)
  }

  @Test("an easeInOut linear keyframe differs from linear away from the endpoints")
  func easeInOutDiffersFromLinear() {
    let linear = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .seconds(1))
    }
    let eased = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .seconds(1), timingCurve: .easeInOut)
    }

    let quarter = Self.seconds(0.25)
    #expect(abs(linear.value(time: quarter) - 2.5) < 1e-9)
    #expect(eased.value(time: quarter) < linear.value(time: quarter))
    // The midpoint of a symmetric ease coincides with linear.
    #expect(abs(eased.value(time: Self.seconds(0.5)) - 5) < 1e-6)
    #expect(eased.value(time: .seconds(1)) == 10)
  }

  // MARK: - Cubic

  @Test("cubic keyframes are C¹ at an interior keyframe by default")
  func cubicIsSmoothAtInteriorKeyframe() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(-3, duration: .seconds(1))
      CubicKeyframe(1, duration: .seconds(1))
      CubicKeyframe(0, duration: .seconds(1))
    }

    #expect(timeline.duration == .seconds(3))
    #expect(timeline.value(time: .seconds(1)) == -3)
    #expect(timeline.value(time: .seconds(2)) == 1)
    #expect(timeline.value(time: .seconds(3)) == 0)

    // Velocity just before and just after the interior keyframe agree: the
    // Catmull-Rom tangent is shared by the two adjoining segments.
    let epsilon = 1e-4
    func velocity(around t: Double) -> (before: Double, after: Double) {
      let before =
        (timeline.value(time: Self.seconds(t)) - timeline.value(time: Self.seconds(t - epsilon)))
        / epsilon
      let after =
        (timeline.value(time: Self.seconds(t + epsilon)) - timeline.value(time: Self.seconds(t)))
        / epsilon
      return (before, after)
    }
    let atOne = velocity(around: 1)
    #expect(abs(atOne.before - atOne.after) < 1e-2, "\(atOne)")
    let atTwo = velocity(around: 2)
    #expect(abs(atTwo.before - atTwo.after) < 1e-2, "\(atTwo)")
    // The estimate is the slope of the neighbors' chord: (1 - 0) / 2 s.
    #expect(abs(atOne.after - 0.5) < 1e-2, "\(atOne)")
  }

  @Test("cubic keyframes honor explicit start and end velocities")
  func cubicHonorsExplicitVelocities() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(10, duration: .seconds(1), startVelocity: 40, endVelocity: 0)
    }

    let epsilon = 1e-4
    let startSlope = timeline.value(time: Self.seconds(epsilon)) / epsilon
    #expect(abs(startSlope - 40) < 0.1, "start slope \(startSlope)")
    let endSlope =
      (timeline.value(time: .seconds(1)) - timeline.value(time: Self.seconds(1 - epsilon)))
      / epsilon
    #expect(abs(endSlope) < 0.1, "end slope \(endSlope)")
    // A large start velocity overshoots the chord early on.
    #expect(timeline.value(time: Self.seconds(0.25)) > 2.5)
  }

  // MARK: - Spring

  @Test("a spring keyframe with no duration sizes itself by the settling duration and lands")
  func springKeyframeUsesSettlingDuration() {
    let spring = Spring(duration: .milliseconds(500), bounce: 0.3)
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      SpringKeyframe(10, spring: spring)
    }

    #expect(timeline.duration == spring.settlingDuration)
    #expect(timeline.value(time: .zero) == 0)
    // Underdamped: overshoots the target partway through.
    var overshot = false
    var step = 0.0
    while step <= spring.settlingDuration.totalSeconds {
      if timeline.value(time: Self.seconds(step)) > 10 { overshot = true }
      step += 0.01
    }
    #expect(overshot)
    #expect(timeline.value(time: timeline.duration) == 10)
    // Just before the end the spring is within the settling threshold.
    let nearEnd = timeline.value(time: timeline.duration - .milliseconds(1))
    #expect(abs(nearEnd - 10) < 0.01 * 10 + 0.001, "\(nearEnd)")
  }

  @Test("a spring keyframe with an explicit duration ends at `to` regardless of settling")
  func springKeyframeHonorsExplicitDuration() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      SpringKeyframe(10, duration: .milliseconds(100), spring: .bouncy)
      LinearKeyframe(20, duration: .milliseconds(100))
    }

    #expect(timeline.duration == .milliseconds(200))
    // The second segment starts from `10` exactly, not from wherever the
    // truncated spring was.
    #expect(timeline.value(time: .milliseconds(100)) == 10)
    #expect(abs(timeline.value(time: .milliseconds(150)) - 15) < 1e-9)
  }

  // MARK: - Move

  @Test("a move keyframe jumps with zero duration")
  func moveKeyframeJumps() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .milliseconds(100))
      MoveKeyframe(50)
      LinearKeyframe(60, duration: .milliseconds(100))
    }

    #expect(timeline.duration == .milliseconds(200))
    #expect(abs(timeline.value(time: .milliseconds(99)) - 9.9) < 1e-9)
    #expect(timeline.value(time: .milliseconds(100)) == 50)
    #expect(abs(timeline.value(time: .milliseconds(150)) - 55) < 1e-9)
  }

  // MARK: - Multiple tracks

  @Test("the timeline duration is the longest track and a short track holds its last value")
  func multipleTracksHoldAndMax() {
    let timeline = KeyframeTimeline(initialValue: Marker()) {
      KeyframeTrack(\.y) {
        LinearKeyframe(-2, duration: .milliseconds(200))
        LinearKeyframe(0, duration: .milliseconds(200))
      }
      KeyframeTrack(\.opacity) {
        LinearKeyframe(0, duration: .milliseconds(100))
      }
    }

    #expect(timeline.duration == .milliseconds(400))
    let mid = timeline.value(time: .milliseconds(200))
    #expect(mid.y == -2)
    #expect(mid.opacity == 0, "the short track holds its last value")
    let end = timeline.value(time: .milliseconds(400))
    #expect(end == Marker(y: 0, opacity: 0))
    #expect(timeline.value(time: .zero) == Marker())
  }

  @Test("value(progress:) equals value(time:) at the same fraction of the duration")
  func progressMatchesTime() {
    let timeline = KeyframeTimeline(initialValue: Marker()) {
      KeyframeTrack(\.y) {
        CubicKeyframe(-3, duration: .milliseconds(300))
        SpringKeyframe(0, duration: .milliseconds(500), spring: .snappy)
      }
      KeyframeTrack(\.opacity) {
        LinearKeyframe(0.2, duration: .milliseconds(800), timingCurve: .easeOut)
      }
    }

    for progress in stride(from: 0.0, through: 1.0, by: 0.125) {
      let byProgress = timeline.value(progress: progress)
      let byTime = timeline.value(
        time: Self.seconds(timeline.duration.totalSeconds * progress)
      )
      #expect(byProgress == byTime, "progress \(progress)")
    }
  }

  @Test("an Int track steps with truncating scale")
  func intTrackSteps() {
    let timeline = KeyframeTimeline(initialValue: 0) {
      LinearKeyframe(10, duration: .seconds(1))
    }

    // `Int.scale(by:)` truncates toward zero: 10 * 0.35 -> 3.
    #expect(timeline.value(time: Self.seconds(0.35)) == 3)
    #expect(timeline.value(time: Self.seconds(0.99)) == 9)
    #expect(timeline.value(time: .seconds(1)) == 10)
  }

  // MARK: - UnitCurve

  @Test(
    "UnitCurve.velocity(at:) matches a finite difference of value(at:)",
    arguments: [
      UnitCurve.linear, .easeIn, .easeOut, .easeInOut,
      .bezier(startControlPoint: .init(x: 0.2, y: 0.9), endControlPoint: .init(x: 0.7, y: 0.1)),
    ]
  )
  func unitCurveVelocityMatchesFiniteDifference(curve: UnitCurve) {
    let h = 1e-3
    for x in stride(from: 0.05, through: 0.95, by: 0.05) {
      let analytic = curve.velocity(at: x)
      let numeric = (curve.value(at: x + h) - curve.value(at: x - h)) / (2 * h)
      #expect(abs(analytic - numeric) < 1e-3, "x=\(x) analytic=\(analytic) numeric=\(numeric)")
    }
    #expect(curve.value(at: 0) == 0)
    #expect(curve.value(at: 1) == 1)
  }

  @Test("the linear unit curve has unit velocity everywhere, including the endpoints")
  func linearUnitCurveVelocity() {
    for x in [0.0, 0.25, 0.5, 0.75, 1.0] {
      #expect(abs(UnitCurve.linear.velocity(at: x) - 1) < 1e-6, "x=\(x)")
    }
  }

  // MARK: - Spring value type

  @Test(
    "Spring.settlingDuration is where the matching Animation spring solver reports settled",
    arguments: [
      (duration: 0.5, bounce: 0.0),
      (duration: 0.5, bounce: 0.3),
      (duration: 1.2, bounce: 0.15),
      (duration: 0.4, bounce: -0.2),
    ])
  func springSettlingDurationAgreesWithSolver(parameters: (duration: Double, bounce: Double)) {
    let spring = Spring(
      duration: .seconds(parameters.duration),
      bounce: parameters.bounce
    )
    let solver = SpringSolver(duration: parameters.duration, bounce: parameters.bounce)
    let settling = spring.settlingDuration.totalSeconds

    // Settled by the solver's own criterion at the settling instant...
    #expect(solver.value(at: settling) == nil, "solver still live at \(settling)s")
    // ...and it stays inside the threshold from there on (the envelope, not a
    // zero crossing, is what settled).
    var t = settling
    while t < settling + 2 {
      if let live = solver.value(at: t) {
        #expect(abs(live) < 0.001, "solver re-armed at \(t)s with \(live)")
      }
      t += 0.007
    }
    // And it is not settled well before: the spring is still moving.
    #expect(solver.value(at: settling * 0.25) != nil)
  }

  @Test("Spring.value and velocity carry an initial velocity toward the target")
  func springValueWithInitialVelocity() {
    let spring = Spring(duration: .milliseconds(500), bounce: 0)
    let still = spring.value(
      fromValue: 0.0, toValue: 10.0, initialVelocity: 0, time: .milliseconds(50))
    let kicked = spring.value(
      fromValue: 0.0, toValue: 10.0, initialVelocity: 40, time: .milliseconds(50)
    )
    #expect(kicked > still)
    #expect(spring.value(fromValue: 0.0, toValue: 10.0, initialVelocity: 0, time: .zero) == 0)
    let startVelocity = spring.velocity(
      fromValue: 0.0, toValue: 10.0, initialVelocity: 40, time: .zero
    )
    #expect(abs(startVelocity - 40) < 1e-9)
    // `target:` is the from-zero form.
    #expect(
      spring.value(target: 10.0, time: .milliseconds(120))
        == spring.value(fromValue: 0.0, toValue: 10.0, initialVelocity: 0, time: .milliseconds(120))
    )
  }

  @Test("Spring presets and parameter round-trips")
  func springPresets() {
    #expect(Spring.smooth == Spring(bounce: 0))
    #expect(Spring.snappy == Spring(bounce: 0.15))
    #expect(Spring.bouncy == Spring(bounce: 0.3))
    let spring = Spring(duration: .milliseconds(800), bounce: 0.2)
    #expect(abs(spring.bounce - 0.2) < 1e-9)
    #expect(spring.duration == .milliseconds(800))
    let physical = Spring(mass: 1, stiffness: 100, damping: 10)
    #expect(abs(physical.dampingRatio - 0.5) < 1e-9)
  }

  // MARK: - Animation cross-wiring

  @Test("Animation.timingCurve(_:duration:) and .spring(_:) build the matching curves")
  func animationCrossWiring() {
    #expect(
      Animation.timingCurve(.easeInOut, duration: .milliseconds(300))
        == Animation.easeInOut(duration: .milliseconds(300))
    )
    #expect(
      Animation.spring(Spring(duration: .milliseconds(700), bounce: 0.25))
        == Animation.spring(duration: .milliseconds(700), bounce: 0.25)
    )
    #expect(
      Animation.timingCurve(.easeIn, duration: .milliseconds(300))
        != Animation.timingCurve(.easeOut, duration: .milliseconds(300))
    )
  }
}
