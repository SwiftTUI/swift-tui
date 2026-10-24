import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCAnimationTests {
  @Test func setC187RepeatBoundaryIsExact() {
    let animation = Animation.linear(duration: .seconds(1)).repeatCount(3, autoreverses: true)
    #expect(animation.evaluate(elapsed: .seconds(1)) == 1)
    #expect(animation.evaluate(elapsed: .milliseconds(2500)) == 0.5)
    #expect(animation.evaluate(elapsed: .seconds(3)) == nil)
  }

  @Test func setC188SpeedAndDelayShapeTotalDuration() {
    let fast = Animation.linear(duration: .seconds(1)).speed(2)
    #expect(fast.totalDuration == .milliseconds(500))
    let delayed = fast.delay(.milliseconds(250))
    #expect(delayed.totalDuration == .milliseconds(750))
    #expect(delayed.evaluate(elapsed: .milliseconds(100)) == 0)
    #expect(delayed.evaluate(elapsed: .milliseconds(500)) == 0.5)
  }

  @Test func setC189FrozenSpeedHasNoCompletion() {
    let frozen = Animation.linear(duration: .seconds(1)).speed(0)
    #expect(frozen.totalDuration == nil)
    #expect(frozen.evaluate(elapsed: .seconds(10)) == 0)
  }

  @Test func setC190UndampedSpringHasNoCompletion() {
    let undamped = Animation.spring(Spring(mass: 1, stiffness: 4, damping: 0))
    #expect(undamped.totalDuration == nil)
    #expect(Animation.linear(duration: .seconds(1)).repeatForever().totalDuration == nil)
  }

  @Test func setC191CustomVelocityDelayAndSpeed() {
    let state = AnimationState()
    let plain = Animation(SetCUnitRamp())
    let delayed = plain.delay(.seconds(1))
    #expect(delayed.velocity(elapsed: .milliseconds(500), state: state) == 0)
    let base = plain.velocity(elapsed: .milliseconds(500), state: state)
    let doubled = plain.speed(2).velocity(elapsed: .milliseconds(250), state: state)
    #expect(base != nil && base != 0)
    if let base, let doubled {
      #expect(abs(doubled - 2 * base) < 0.000_001, "base \(base) doubled \(doubled)")
    } else {
      Issue.record("custom velocity must be available before completion")
    }
  }

  @Test func setC192TransitionCompositionArithmetic() {
    let edges = AnyTransition.move(edge: .leading).combined(with: .move(edge: .trailing))
      .insertionModifiers()
    #expect(edges.moveEdges == [.leading, .trailing])
    let resolved = edges.resolvedOffset(edgeBasis: CellSize(width: 8, height: 2))
    #expect(resolved.x == 0 && resolved.y == 0)
    let offsets = AnyTransition.offset(x: 2).combined(with: .offset(x: 3)).insertionModifiers()
    #expect(offsets.offsetX == 5)
    let faded = AnyTransition.opacity.combined(with: .opacity).insertionModifiers()
    #expect(faded.opacity == 0)
    let kept = AnyTransition.offset(x: 2, y: 1).combined(with: .identity).insertionModifiers()
    #expect(kept.offsetX == 2 && kept.offsetY == 1 && kept.opacity == nil)
  }

  @Test func setC193PushCarriesOpacityAndEdges() {
    let push = AnyTransition.push(from: .leading)
    let insertion = push.insertionModifiers()
    let removal = push.removalModifiers()
    #expect(insertion.opacity == 0 && insertion.moveEdge == .leading)
    #expect(removal.opacity == 0 && removal.moveEdge == .trailing)
  }

  @Test func setC194SpringBounceClampAndExactDuration() {
    #expect(Spring(duration: .milliseconds(500), bounce: 1.5).bounce == 1)
    #expect(Spring(mass: 1, stiffness: 4, damping: 1).duration == .seconds(Double.pi))
  }

  @Test func setC195SpringSettlingMatchesAnimationCompletion() {
    let spring = Spring(duration: .milliseconds(500), bounce: 0.3)
    let completion = Animation.spring(spring).totalDuration
    #expect(completion != nil)
    #expect(
      completion == spring.settlingDuration,
      "animation \(String(describing: completion)) vs settling \(spring.settlingDuration)")
  }

  @Test func setC196PeriodicScheduleGridAlignment() {
    let origin = MonotonicInstant.now()
    let schedule = PeriodicTimelineSchedule(from: origin, by: .milliseconds(300))
    var late = schedule.entries(from: origin.advanced(by: .seconds(1)), mode: .normal)
    #expect(late.next() == origin.advanced(by: .milliseconds(1200)))
    #expect(late.next() == origin.advanced(by: .milliseconds(1500)))
    var exact = schedule.entries(from: origin.advanced(by: .milliseconds(600)), mode: .normal)
    #expect(exact.next() == origin.advanced(by: .milliseconds(600)))
    var early = schedule.entries(from: origin.advanced(by: .seconds(-1)), mode: .normal)
    #expect(early.next() == origin)
  }

  @Test func setC197LowFrequencyFloorsAndAligns() {
    let origin = MonotonicInstant.now()
    let schedule = PeriodicTimelineSchedule(from: origin, by: .milliseconds(300))
    var entries = schedule.entries(
      from: origin.advanced(by: .milliseconds(1500)), mode: .lowFrequency)
    #expect(entries.next() == origin.advanced(by: .seconds(2)))
    #expect(entries.next() == origin.advanced(by: .seconds(3)))
  }

  @Test func setC198MillionIterationsNoOverflow() throws {
    let forever = Animation.linear(duration: .milliseconds(1)).repeatForever(autoreverses: false)
    let value = try #require(forever.evaluate(elapsed: .seconds(1000)))
    #expect(value >= 0 && value <= 1)
  }

  @Test func setC199AutoreverseTerminalBoundary() throws {
    let animation = Animation.linear(duration: .seconds(1)).repeatCount(2, autoreverses: true)
    #expect(animation.evaluate(elapsed: .seconds(2)) == nil)
    let nearEnd = try #require(animation.evaluate(elapsed: .milliseconds(1999)))
    #expect(nearEnd >= 0 && nearEnd < 0.01)
  }

  @Test func setC200BezierEndpointsExact() throws {
    let ease = Animation.easeInOut(duration: .seconds(1))
    // `nil` is the completion sentinel: the curve has finished at its duration.
    let nearEnd = try #require(ease.evaluate(elapsed: .milliseconds(999)))
    #expect(nearEnd > 0.99 && nearEnd <= 1)
    #expect(ease.evaluate(elapsed: .seconds(1)) == nil)
    #expect(ease.evaluate(elapsed: .milliseconds(1500)) == nil)
    let instant = Animation.linear(duration: .zero)
    #expect(instant.totalDuration == .zero)
    #expect(instant.evaluate(elapsed: .milliseconds(1)) == nil)
  }
}

/// A linear unit ramp: progress equals elapsed seconds, finished after one.
private struct SetCUnitRamp: CustomAnimation {
  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V? {
    let seconds =
      Double(time.components.seconds)
      + Double(time.components.attoseconds) / 1_000_000_000_000_000_000
    guard seconds < 1 else { return nil }
    return value.scaled(by: seconds)
  }

  func shouldMerge<V: VectorArithmetic>(
    previous: Animation, value: V, time: Duration, context: inout AnimationContext<V>
  ) -> Bool {
    false
  }

  func velocity<V: VectorArithmetic>(
    value: V, time: Duration, context: AnimationContext<V>
  ) -> V? {
    value
  }
}
