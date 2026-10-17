import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Adversarial set B, animation tracks (051–060). The September–October 2026
// keyframe, trim and repeat fixes (STUI-605, STUI-612, STUI-627, STUI-900)
// all sat at a seam between two segments: a zero-length keyframe, a move after
// a spring, a retrigger outside the previous run, an exact period multiple.
// These cases sample exactly on those seams with the math as the oracle.
@Suite("Adversarial set B: animation tracks")
struct AdversarialSetBAnimationTests {
  private struct Marker: Equatable {
    var y: Double = 0
    var opacity: Double = 1
  }

  @Test func setB051ZeroDurationTimelineHoldsItsEndValue() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      MoveKeyframe(5)
    }
    #expect(timeline.duration == .zero)
    #expect(timeline.value(time: .zero) == 5)
    #expect(timeline.value(time: .milliseconds(-1)) == 0)
    #expect(timeline.value(progress: 0.5) == 5)
    #expect(timeline.value(progress: -1) == 5)
  }

  @Test func setB052TwoTrackSamplingOutsideTheRunClampsPerTrack() {
    let timeline = KeyframeTimeline(initialValue: Marker()) {
      KeyframeTrack(\.y) { LinearKeyframe(4, duration: .seconds(1)) }
      KeyframeTrack(\.opacity) { LinearKeyframe(0, duration: .seconds(2)) }
    }
    #expect(timeline.duration == .seconds(2))
    #expect(timeline.value(time: .milliseconds(-1)) == Marker())
    let atOne = timeline.value(time: .seconds(1))
    #expect(atOne.y == 4)
    #expect(abs(atOne.opacity - 0.5) < 1e-9)
    #expect(timeline.value(time: .seconds(5)) == Marker(y: 4, opacity: 0))
    #expect(timeline.value(progress: 1.5) == timeline.value(time: .seconds(3)))
  }

  @Test func setB053SingleCubicKeyframeIsASmoothstep() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(10, duration: .seconds(1))
    }
    for (t, expected) in [(0.25, 1.5625), (0.5, 5.0), (0.75, 8.4375)] {
      let value = timeline.value(time: .seconds(t))
      #expect(abs(value - expected) < 1e-9, "t=\(t) value=\(value)")
    }
    #expect(timeline.value(time: .seconds(1)) == 10)
    let epsilon = 1e-6
    let startSlope = timeline.value(time: .seconds(epsilon)) / epsilon
    let endSlope = (10 - timeline.value(time: .seconds(1 - epsilon))) / epsilon
    #expect(abs(startSlope) < 1e-3, "start slope \(startSlope)")
    #expect(abs(endSlope) < 1e-3, "end slope \(endSlope)")
  }

  @Test func setB054ConsecutiveZeroDurationKeyframesResolveAtTheBoundary() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(1, duration: .seconds(1))
      LinearKeyframe(2, duration: .zero)
      LinearKeyframe(3, duration: .zero)
      LinearKeyframe(4, duration: .seconds(1))
    }
    #expect(timeline.duration == .seconds(2))
    #expect(abs(timeline.value(time: .milliseconds(999)) - 0.999) < 1e-9)
    #expect(timeline.value(time: .seconds(1)) == 3)
    #expect(abs(timeline.value(time: .milliseconds(1500)) - 3.5) < 1e-9)
    let negative = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(5, duration: .seconds(-1))
      LinearKeyframe(6, duration: .seconds(1))
    }
    #expect(negative.duration == .seconds(1))
    #expect(negative.value(time: .zero) == 5)
    #expect(abs(negative.value(time: .milliseconds(500)) - 5.5) < 1e-9)
  }

  @Test func setB055CubicLinearCubicChainIsContinuousInSlope() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(10, duration: .seconds(1))
      LinearKeyframe(20, duration: .seconds(1))
      CubicKeyframe(0, duration: .seconds(1))
    }
    let epsilon = 1e-6
    func slope(_ t: Double) -> Double {
      (timeline.value(time: .seconds(t + epsilon)) - timeline.value(time: .seconds(t - epsilon)))
        / (2 * epsilon)
    }
    #expect(timeline.value(time: .seconds(1)) == 10)
    #expect(timeline.value(time: .seconds(2)) == 20)
    for boundary in [1.0, 2.0] {
      let before = slope(boundary - 1e-4)
      let after = slope(boundary + 1e-4)
      #expect(abs(before - 10) < 0.05, "before \(boundary): \(before)")
      #expect(abs(after - 10) < 0.05, "after \(boundary): \(after)")
    }
    #expect(abs(timeline.value(time: .seconds(epsilon)) / epsilon) < 1e-3)
    #expect(abs(timeline.value(time: .seconds(3 - epsilon)) / epsilon) < 1e-3)
  }

  @Test func setB056SpringThenMoveDoesNotLeakVelocityAcrossTheMove() {
    let spring = Spring()
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      SpringKeyframe(10, duration: .milliseconds(500), spring: spring)
      MoveKeyframe(20)
      LinearKeyframe(30, duration: .seconds(1))
    }
    #expect(timeline.duration == .milliseconds(1500))
    let sampled = timeline.value(time: .milliseconds(499))
    let reference = spring.value(
      fromValue: 0.0, toValue: 10, initialVelocity: 0, time: .milliseconds(499))
    #expect(abs(sampled - reference) < 1e-9, "\(sampled) vs \(reference)")
    #expect(timeline.value(time: .milliseconds(500)) == 20)
    #expect(abs(timeline.value(time: .milliseconds(1000)) - 25) < 1e-9)
    // A retrigger continues at the velocity the display had at that instant:
    // the spring's own velocity mid-spring, and the linear's slope at the move.
    let epsilon = 1e-6
    for retrigger in [250, 500] {
      let at = Duration.milliseconds(retrigger)
      let displayed = timeline.value(time: at)
      let displayedSlope = (timeline.value(time: at + .seconds(epsilon)) - displayed) / epsilon
      let next = KeyframeTimeline(initialValue: displayed) {
        CubicKeyframe(0, duration: .seconds(1))
      }.continuing(from: timeline, at: at)
      #expect(next.value(time: .zero) == displayed)
      let seededSlope = (next.value(time: .seconds(epsilon)) - displayed) / epsilon
      #expect(
        abs(seededSlope - displayedSlope) < 0.05,
        "retrigger \(retrigger)ms: displayed \(displayedSlope) seeded \(seededSlope)")
    }
  }

  @Test func setB057RetriggerOutsideThePreviousRunSeedsNoVelocity() {
    let previous = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .seconds(1))
    }
    let next = KeyframeTimeline(initialValue: 10.0) {
      SpringKeyframe(0, spring: Spring(duration: .milliseconds(400), bounce: 0.3))
    }
    for retrigger in [Duration.seconds(1), .seconds(2), .milliseconds(-5)] {
      let seeded = next.continuing(from: previous, at: retrigger)
      for ms in [0, 50, 200, 400] {
        let a = seeded.value(time: .milliseconds(ms))
        let b = next.value(time: .milliseconds(ms))
        #expect(abs(a - b) < 1e-9, "retrigger=\(retrigger) ms=\(ms) \(a) vs \(b)")
      }
    }
    let inside = next.continuing(from: previous, at: .milliseconds(500))
    #expect(abs(inside.value(time: .milliseconds(50)) - next.value(time: .milliseconds(50))) > 0.1)
    let authored = KeyframeTimeline(initialValue: 10.0) {
      CubicKeyframe(0, duration: .seconds(1), startVelocity: 3)
    }.continuing(from: previous, at: .milliseconds(500))
    let epsilon = 1e-6
    let slope = (authored.value(time: .seconds(epsilon)) - 10) / epsilon
    #expect(abs(slope - 3) < 1e-2, "authored start velocity must survive seeding: \(slope)")
  }

  @Test func setB058RepeatForeverAutoreversesAtExactPeriodMultiples() throws {
    let animation = Animation.linear(duration: .milliseconds(100)).repeatForever(autoreverses: true)
    for (ms, expected) in [(0, 0.0), (100, 1.0), (200, 0.0), (300, 1.0), (1000, 0.0), (150, 0.5)] {
      let value = try #require(animation.evaluate(elapsed: .milliseconds(ms)), "ms=\(ms)")
      #expect(abs(value - expected) < 1e-9, "ms=\(ms) value=\(value)")
    }
    #expect(animation.totalDuration == nil)
    let forward = Animation.linear(duration: .milliseconds(100)).repeatForever(autoreverses: false)
    let wrapped = try #require(forward.evaluate(elapsed: .milliseconds(100)))
    #expect(abs(wrapped) < 1e-9)
    let none = Animation.linear(duration: .milliseconds(100)).repeatCount(0, autoreverses: false)
    #expect(none.evaluate(elapsed: .zero) == nil)
    #expect(none.totalDuration == .zero)
  }

  @Test func setB059SpeedZeroNegativeSpeedAndDelayNeverProduceProgress() throws {
    let frozen = Animation.linear(duration: .seconds(1)).speed(0)
    for ms in [0, 1000, 10_000] {
      let value = try #require(frozen.evaluate(elapsed: .milliseconds(ms)), "ms=\(ms)")
      #expect(value == 0, "ms=\(ms) value=\(value)")
    }
    let reversed = Animation.linear(duration: .seconds(1)).speed(-1)
    for ms in [0, 500, 5000] {
      let value = try #require(reversed.evaluate(elapsed: .milliseconds(ms)), "ms=\(ms)")
      #expect(value == 0, "ms=\(ms) value=\(value)")
    }
    #expect(reversed.velocity(elapsed: .milliseconds(500), state: .init()) == 0)
    let delayed = Animation.linear(duration: .seconds(1)).delay(.milliseconds(200)).speed(2)
    #expect(delayed.evaluate(elapsed: .milliseconds(100)) == 0)
    #expect(delayed.evaluate(elapsed: .milliseconds(200)) == 0)
    let late = try #require(delayed.evaluate(elapsed: .milliseconds(699)))
    #expect(abs(late - 0.998) < 1e-3, "\(late)")
    #expect(delayed.evaluate(elapsed: .milliseconds(700)) == nil)
    #expect(delayed.totalDuration == .milliseconds(700))
    let repeating = Animation.linear(duration: .milliseconds(100)).delay(.milliseconds(500))
      .repeatForever(autoreverses: false)
    #expect(repeating.evaluate(elapsed: .milliseconds(250)) == 0)
    #expect(repeating.velocity(elapsed: .milliseconds(250), state: .init()) == 0)
    let afterDelay = try #require(repeating.evaluate(elapsed: .milliseconds(550)))
    #expect(abs(afterDelay - 0.5) < 1e-9)
  }

  @MainActor
  @Test func setB060DashPhaseWrapsAndNestedTrimsCompose() throws {
    let pattern = try #require(StrokeDashPattern(dash: [2, 1], phase: 7))
    #expect(pattern.isOn(at: 0))
    #expect(!pattern.isOn(at: 1))
    #expect(pattern.isOn(at: 2))
    let negative = try #require(StrokeDashPattern(dash: [2, 1], phase: -7))
    #expect(!negative.isOn(at: 0))
    #expect(negative.isOn(at: 1))
    let gapOnly = try #require(StrokeDashPattern(dash: [0, 2], phase: 0))
    for step in 0..<60 {
      #expect(!gapOnly.isOn(at: Double(step) / 10), "position \(Double(step) / 10)")
    }
    let dashOnly = try #require(StrokeDashPattern(dash: [2, 0], phase: 0))
    for step in 0..<60 {
      #expect(dashOnly.isOn(at: Double(step) / 10), "position \(Double(step) / 10)")
    }
    let odd = try #require(StrokeDashPattern(dash: [0, 0, 2], phase: 0))
    #expect(odd.isOn(at: 0.5))
    #expect(odd.isOn(at: 1.9))
    #expect(!odd.isOn(at: 2.5))
    #expect(!odd.isOn(at: 3.9))
    #expect(odd.isOn(at: 4.1))
    let nested = Circle().trim(from: 0, to: 0.5).trim(from: 0.5, to: 1)
    #expect(abs(nested.trimStart - 0.25) < 1e-12)
    #expect(abs(nested.trimEnd - 0.5) < 1e-12)
    let reversed = Circle().trim(from: 0, to: 0.5).trim(from: 0.6, to: 0.4)
    #expect(abs(reversed.trimStart - 0.3) < 1e-12)
    #expect(abs(reversed.trimEnd - 0.2) < 1e-12)
    #expect(StrokeTrim(from: reversed.trimStart, to: reversed.trimEnd).isEmpty)
  }
}
