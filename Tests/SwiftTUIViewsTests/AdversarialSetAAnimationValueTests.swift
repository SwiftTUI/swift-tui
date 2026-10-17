import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Set A's third pass samples pure animation and transaction contracts without a frame clock.
@Suite("Adversarial set A: animation values")
struct AdversarialSetAAnimationValueTests {
  @Test("set A 226: reversing asymmetric Bézier control points reverses time")
  func setA226BezierTimeReflection() {
    // Hypothesis: inverse-parameter solving can make an asymmetric curve depend on playback direction.
    let forward = UnitCurve.bezier(
      startControlPoint: .init(x: 0.15, y: 0.7), endControlPoint: .init(x: 0.65, y: 0.9))
    let reverse = UnitCurve.bezier(
      startControlPoint: .init(x: 0.35, y: 0.1), endControlPoint: .init(x: 0.85, y: 0.3))
    for time in [0.01, 0.13, 0.37, 0.83, 0.99] {
      #expect(abs(forward.value(at: time) + reverse.value(at: 1 - time) - 1) < 0.00001)
    }
  }

  @Test("set A 227: Bézier endpoint velocities retain nonzero authored slopes")
  func setA227BezierEndpointSlopes() {
    // Hypothesis: endpoint clamping or derivative fallback can silently replace a real endpoint slope.
    let curve = UnitCurve.bezier(
      startControlPoint: .init(x: 0.2, y: 0.6), endControlPoint: .init(x: 0.8, y: 0.1))
    #expect(abs(curve.velocity(at: 0) - 3) < 0.000001)
    #expect(abs(curve.velocity(at: 1) - 4.5) < 0.000001)
    #expect(curve.value(at: 0) == 0)
    #expect(curve.value(at: 1) == 1)
  }

  @Test("set A 228: a Bézier curve with a stationary time tangent preserves nearby progress")
  func setA228BezierStationaryTimeTangent() {
    // Hypothesis: an x-error stopping rule is too loose when dx/dt vanishes at the midpoint.
    let curve = UnitCurve.bezier(
      startControlPoint: .init(x: 1, y: 0), endControlPoint: .init(x: 0, y: 1))
    for offset in [-0.001, 0.001] {
      // With parameter t = 1/2 + u, x = 1/2 + 4u³ and y = 1/2 + 3u/2 - 2u³.
      let cube = offset * offset * offset
      let time = 0.5 + 4 * cube
      let expected = 0.5 + 1.5 * offset - 2 * cube
      let actual = curve.value(at: time)
      withKnownIssue("STUI-963: the Bézier inverse stops on x error near a stationary tangent") {
        #expect(
          abs(actual - expected) < 0.00001,
          "time \(time): expected \(expected), actual \(actual)")
      }
    }
  }

  @Test("set A 229: speed and repetition retain submillisecond progress")
  func setA229DurationModifiersPreserveFractionalMilliseconds() throws {
    // Hypothesis: converting adjusted or repeat-local Duration values through milliseconds quantizes motion.
    let base = Animation.linear(duration: .milliseconds(1))
    let dilated = try #require(base.speed(2).evaluate(elapsed: .microseconds(125)))
    let repeated = try #require(
      base.repeatCount(3, autoreverses: false).evaluate(elapsed: .microseconds(1_250)))
    let unmodified = try #require(base.evaluate(elapsed: .microseconds(250)))
    withKnownIssue("STUI-964: playback speed truncates adjusted time to integer milliseconds") {
      #expect(abs(dilated - 0.25) < 0.000001, "sped-up progress: expected 0.25, actual \(dilated)")
    }
    withKnownIssue("STUI-964: repetition rounds local time to integer milliseconds") {
      #expect(
        abs(repeated - 0.25) < 0.000001, "repeated progress: expected 0.25, actual \(repeated)")
    }
    #expect(abs(unmodified - 0.25) < 0.000001)
  }

  @Test("set A 230: autoreverse velocity changes sign after delay and speed adjustment")
  func setA230AutoreverseVelocityUsesElapsedTime() throws {
    // Hypothesis: the value can reverse correctly while the velocity handoff retains its forward sign or rate.
    let animation = Animation.linear(duration: .seconds(2))
      .delay(.milliseconds(250)).speed(2).repeatCount(3, autoreverses: true)
    let value = try #require(animation.evaluate(elapsed: .milliseconds(1_750)))
    let velocity = try #require(
      animation.velocity(
        elapsed: .milliseconds(1_750), state: .init()))
    #expect(abs(value - 0.5) < 0.000001)
    #expect(abs(velocity + 1) < 0.001)
    #expect(animation.totalDuration == .milliseconds(3_250))
  }

  @Test("set A 231: a sped-up custom animation applies the velocity chain rule")
  func setA231CustomVelocityScalesWithPlaybackSpeed() throws {
    // Hypothesis: custom velocity receives adjusted time but is returned without scaling to elapsed-time units.
    let animation = Animation(CountingLinearCurve(rate: 0.25))
      .delay(.milliseconds(100)).speed(3)
    let velocity = try #require(animation.velocity(elapsed: .milliseconds(400), state: .init()))
    let before = try #require(animation.evaluate(elapsed: .milliseconds(390)))
    let after = try #require(animation.evaluate(elapsed: .milliseconds(410)))
    withKnownIssue("STUI-965: custom velocity omits the playback-speed multiplier") {
      #expect(
        abs(velocity - 0.75) < 0.000001,
        "elapsed-time velocity: expected 0.75, actual \(velocity)")
    }
    #expect(abs((after - before) / 0.02 - 0.75) < 0.000001)
  }

  @Test("set A 232: a custom animation's delay does not consume its stateful first sample")
  func setA232DelayedCustomCurveDefersStateMutation() {
    // Hypothesis: evaluating during a delay can run the custom curve and consume state before animation starts.
    let animation = Animation(CountingLinearCurve(rate: 2)).delay(.milliseconds(250))
    var state = AnimationState()
    #expect(animation.evaluate(elapsed: .milliseconds(200), state: &state) == 0)
    #expect(state["calls", as: Int.self] == nil)
    #expect(animation.evaluate(elapsed: .milliseconds(250), state: &state) == 0)
    #expect(state["calls", as: Int.self] == 1)
    #expect(animation.evaluate(elapsed: .milliseconds(500), state: &state) == 0.5)
    #expect(state["calls", as: Int.self] == 2)
  }

  @Test("set A 233: restarting a spring from sampled vector state preserves its future trajectory")
  func setA233SpringRestartPreservesVectorTrajectory() {
    // Hypothesis: vector initial-velocity signs or units can break continuity when an oscillator is restarted.
    let spring = Spring(duration: .milliseconds(800), bounce: 0.3)
    let start = AnimatablePair(-3.0, 4.0)
    let target = AnimatablePair(7.0, -2.0)
    let velocity = AnimatablePair(5.0, -8.0)
    let split = Duration.milliseconds(137)
    let remainder = Duration.milliseconds(223)
    let position = spring.value(
      fromValue: start, toValue: target, initialVelocity: velocity, time: split)
    let speed = spring.velocity(
      fromValue: start, toValue: target, initialVelocity: velocity, time: split)
    let resumed = spring.value(
      fromValue: position, toValue: target, initialVelocity: speed, time: remainder)
    let uninterrupted = spring.value(
      fromValue: start, toValue: target, initialVelocity: velocity, time: split + remainder)
    #expect(abs(resumed.first - uninterrupted.first) < 0.000000001)
    #expect(abs(resumed.second - uninterrupted.second) < 0.000000001)
  }

  @Test("set A 234: uniformly scaling physical spring coefficients leaves motion unchanged")
  func setA234SpringPhysicalScaleInvariance() {
    // Hypothesis: physical normalization can retain absolute mass instead of only stiffness/mass and damping/mass.
    let base = Spring(mass: 2, stiffness: 30, damping: 4)
    let scaled = Spring(mass: 34, stiffness: 510, damping: 68)
    for time in [0.25, 1.0, 3.0] {
      let lhs = base.value(fromValue: 2.0, toValue: -4, initialVelocity: 3, time: .seconds(time))
      let rhs = scaled.value(fromValue: 2.0, toValue: -4, initialVelocity: 3, time: .seconds(time))
      #expect(abs(lhs - rhs) < 0.000000001)
    }
  }

  @Test("set A 235: spring motion remains continuous across critical damping")
  func setA235CriticalDampingLimitIsContinuous() {
    // Hypothesis: switching between underdamped, critical, and overdamped formulas introduces a numerical seam.
    let critical = Spring(mass: 1, stiffness: 25, damping: 10)
    for damping in [9.9999999, 10.0000001] {
      let neighbor = Spring(mass: 1, stiffness: 25, damping: damping)
      for time in [0.1, 0.5, 2.0] {
        let expected = critical.value(
          fromValue: -2.0, toValue: 3, initialVelocity: 4, time: .seconds(time))
        let actual = neighbor.value(
          fromValue: -2.0, toValue: 3, initialVelocity: 4, time: .seconds(time))
        #expect(abs(actual - expected) < 0.000001)
      }
    }
  }

  @Test("set A 236: an undamped spring conserves mechanical energy")
  func setA236UndampedSpringConservesEnergy() {
    // Hypothesis: an incorrect displacement/velocity pair can look oscillatory while gaining or losing energy.
    let spring = Spring(mass: 1, stiffness: 4, damping: 0)
    for time in [0.0, 0.1, 0.7, 3.1] {
      let position = spring.value(
        fromValue: 2.0, toValue: 0, initialVelocity: -3, time: .seconds(time))
      let velocity = spring.velocity(
        fromValue: 2.0, toValue: 0, initialVelocity: -3, time: .seconds(time))
      #expect(abs(0.5 * velocity * velocity + 2 * position * position - 12.5) < 0.00000001)
    }
  }

  @Test("set A 237: equal spring endpoints still respond to an initial velocity")
  func setA237EqualEndpointsRetainVelocityImpulse() {
    // Hypothesis: normalizing by target distance can erase a nonzero impulse when the initial distance is zero.
    let spring = Spring(mass: 1, stiffness: 4, damping: 4)
    let value = spring.value(
      fromValue: 7.0, toValue: 7, initialVelocity: 4, time: .milliseconds(500))
    let velocity = spring.velocity(
      fromValue: 7.0, toValue: 7, initialVelocity: 4, time: .milliseconds(500))
    // The critical impulse is 4t exp(-2t), equal to 2/e at its maximum t = 1/2.
    #expect(abs(value - 7.735758882342885) < 0.000000001)
    #expect(abs(velocity) < 0.000000001)
  }

  @Test("set A 238: a strongly overdamped spring retains its slow restoring mode")
  func setA238OverdampedRootAvoidsCancellation() {
    // Hypothesis: subtracting nearly equal damping roots rounds the slow root to zero and freezes the spring.
    let spring = Spring(mass: 1, stiffness: 4, damping: 1_000_000_000)
    let value = spring.value(
      fromValue: 0.0, toValue: 1, initialVelocity: 0, time: .seconds(100_000_000))
    // The slow root is -4e-9 to far beyond this tolerance; progress is 1 - exp(-0.4).
    #expect(value.isFinite)
    withKnownIssue("STUI-966: overdamped root subtraction eliminates the slow restoring mode") {
      #expect(
        abs(value - 0.3296799539643607) < 0.000001,
        "slow-mode progress: expected 0.3296799539643607, actual \(value)")
    }
  }

  @Test("set A 239: consecutive moves at a nonzero boundary use the last authored target")
  func setA239ConsecutiveMovesKeepAuthoredOrder() {
    // Hypothesis: searching segments by end time can skip or reorder instantaneous moves between timed segments.
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(2, duration: .seconds(1))
      MoveKeyframe(10)
      MoveKeyframe(-2)
      LinearKeyframe(6, duration: .seconds(2))
    }
    #expect(timeline.duration == .seconds(3))
    #expect(timeline.value(time: .milliseconds(999)) == 1.998)
    #expect(timeline.value(time: .seconds(1)) == -2)
    #expect(timeline.value(time: .seconds(2)) == 2)
  }

  @Test("set A 240: a negative segment duration cannot move later segment times backward")
  func setA240NonpositiveKeyframeDurationIsInstantaneous() {
    // Hypothesis: normalization can clamp sampling but leave a negative duration in cumulative track times.
    let timeline = KeyframeTimeline(initialValue: 1.0) {
      LinearKeyframe(4, duration: .seconds(-2))
      LinearKeyframe(8, duration: .seconds(2))
    }
    #expect(timeline.duration == .seconds(2))
    #expect(timeline.value(time: .milliseconds(-1)) == 1)
    #expect(timeline.value(time: .zero) == 4)
    #expect(timeline.value(time: .seconds(1)) == 6)
  }

  @Test("set A 241: unequal cubic durations use time-weighted shared tangents")
  func setA241UnequalCubicDurationsUsePhysicalTangents() {
    // Hypothesis: Catmull-Rom defaults can use frame count instead of elapsed duration for the shared chord.
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      CubicKeyframe(8, duration: .seconds(2))
      CubicKeyframe(14, duration: .seconds(1))
    }
    // Shared velocity = (14 - 0) / 3; evaluate each Hermite midpoint using that velocity.
    #expect(abs(timeline.value(time: .seconds(1)) - 17.0 / 6) < 0.000001)
    #expect(abs(timeline.value(time: .milliseconds(2_500)) - 139.0 / 12) < 0.000001)
  }

  @Test("set A 242: stretching cubic time and reducing authored velocities preserves its shape")
  func setA242CubicTimeDilationPreservesTrajectory() {
    // Hypothesis: authored per-second tangents may be treated as unit-segment tangents when duration changes.
    let original = KeyframeTimeline(initialValue: 4.0) {
      CubicKeyframe(-3, duration: .milliseconds(600), startVelocity: 5, endVelocity: -7)
    }
    let stretched = KeyframeTimeline(initialValue: 4.0) {
      CubicKeyframe(-3, duration: .milliseconds(1_200), startVelocity: 2.5, endVelocity: -3.5)
    }
    for milliseconds in [150, 300, 450] {
      #expect(
        abs(
          original.value(time: .milliseconds(milliseconds))
            - stretched.value(time: .milliseconds(2 * milliseconds))) < 0.000001)
    }
  }

  @Test("set A 243: a shorter duplicate-key-path track keeps its final override")
  func setA243ShortDuplicateTrackHoldsOverride() {
    // Hypothesis: a finished overriding track can stop applying and reveal an earlier still-running track.
    let timeline = KeyframeTimeline(initialValue: Marker(x: 0, y: 9)) {
      KeyframeTrack(\.x) { LinearKeyframe(100, duration: .seconds(2)) }
      KeyframeTrack(\.x) { LinearKeyframe(4, duration: .milliseconds(500)) }
    }
    #expect(timeline.duration == .seconds(2))
    #expect(timeline.value(time: .milliseconds(250)) == Marker(x: 2, y: 9))
    #expect(timeline.value(time: .seconds(1)) == Marker(x: 4, y: 9))
    #expect(timeline.value(time: .seconds(3)) == Marker(x: 4, y: 9))
  }

  @Test("set A 244: a retrigger cannot borrow velocity from another same-typed property")
  func setA244UnmatchedRetriggerTrackStartsAtRest() {
    // Hypothesis: type-based erasure can seed an unmatched key path with a neighboring Double track's velocity.
    let previous = KeyframeTimeline(initialValue: Marker(x: 5, y: 0)) {
      KeyframeTrack(\.y) { LinearKeyframe(100, duration: .seconds(1)) }
    }
    let next = KeyframeTimeline(initialValue: previous.value(time: .milliseconds(500))) {
      KeyframeTrack(\.x) { CubicKeyframe(10, duration: .seconds(1)) }
    }.continuing(from: previous, at: .milliseconds(500))
    #expect(next.value(time: .milliseconds(500)) == Marker(x: 7.5, y: 50))
    #expect(next.value(time: .zero) == Marker(x: 5, y: 50))
  }

  @Test("set A 245: an authored zero start velocity rejects a retrigger seed")
  func setA245ExplicitZeroVelocityIsNotADefault() {
    // Hypothesis: an explicit zero can be mistaken for a missing tangent and overwritten by handoff velocity.
    let previous = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(10, duration: .seconds(1))
    }
    let next = KeyframeTimeline(initialValue: 5.0) {
      CubicKeyframe(-5, duration: .seconds(1), startVelocity: 0)
    }.continuing(from: previous, at: .milliseconds(500))
    #expect(abs(next.value(time: .milliseconds(500))) < 0.000001)
    #expect(next.value(time: .zero) == 5)
  }

  @Test("set A 246: a cubic track preserves the shape of array-backed animatable data")
  func setA246ArrayBackedCubicKeepsCoordinateCount() {
    // Hypothesis: default empty-array zero tangents erase a valid equal-length vector during Hermite addition.
    let start = Coordinates(values: [0, 4])
    let target = Coordinates(values: [10, -2])
    let cubic = KeyframeTimeline(initialValue: start) {
      CubicKeyframe(target, duration: .seconds(1))
    }
    let linear = KeyframeTimeline(initialValue: start) {
      LinearKeyframe(target, duration: .seconds(1))
    }
    #expect(linear.value(time: .milliseconds(500)).values == [5, 1])
    withKnownIssue("STUI-967: empty default cubic tangents erase array-backed coordinates") {
      #expect(cubic.value(time: .milliseconds(500)).values == [5, 1])
    }
    #expect(cubic.value(time: .seconds(1)) == target)

    // Gradient supplies the same published array-backed AnimatableData. Its
    // defensive setter hides the empty result by retaining the target's stops.
    let gradient = KeyframeTimeline(
      initialValue: Gradient(stops: [
        .init(color: .red, location: 0.1), .init(color: .blue, location: 0.9),
      ])
    ) {
      CubicKeyframe(
        Gradient(stops: [
          .init(color: .red, location: 0.3), .init(color: .blue, location: 0.7),
        ]), duration: .seconds(1))
    }
    let locations = gradient.value(time: .milliseconds(500)).stops.map(\.location)
    #expect(locations.count == 2)
    withKnownIssue("STUI-967: a gradient rejects the empty cubic result and keeps its target stops")
    {
      #expect(
        locations.elementsEqual([0.2, 0.8], by: { abs($0 - $1) < 0.000001 }),
        "gradient midpoint locations: expected [0.2, 0.8], actual \(locations)")
    }
  }

  @Test("set A 247: copying a transaction isolates its animation, flags, and keyed values")
  func setA247TransactionCopiesDoNotShareMutations() {
    // Hypothesis: copying keyed transaction storage can alias subsequent mutations or animation suppression.
    var original = Transaction(animation: .easeIn(duration: .seconds(1)))
    original.isContinuous = true
    original.tracksVelocity = true
    original[LabelKey.self] = "original"
    var copy = original
    copy.animation = nil
    copy.isContinuous = false
    copy.tracksVelocity = false
    copy[LabelKey.self] = "copy"
    #expect(original.animation == .easeIn(duration: .seconds(1)))
    #expect(original.isContinuous && original.tracksVelocity)
    #expect(original[LabelKey.self] == "original")
    #expect(copy.disablesAnimations)
    #expect(!copy.isContinuous && !copy.tracksVelocity)
    #expect(copy[LabelKey.self] == "copy")
  }

  @MainActor
  @Test("set A 248: throwing nested transaction scopes restore the enclosing intent and metadata")
  func setA248ThrowingTransactionScopeRestoresContext() {
    // Hypothesis: an exceptional scope exit can leave animation suppression or continuity in task-local context.
    let baselineRequest = AnimationContextStorage.currentRequest
    let baselineKeys = AnimationContextStorage.currentCustomValues
    var outer = Transaction(animation: .linear(duration: .seconds(1)))
    outer.isContinuous = true
    outer.tracksVelocity = true
    outer[LabelKey.self] = "outer"
    withTransaction(outer) {
      do {
        try withTransaction(\.disablesAnimations, true) {
          #expect(AnimationContextStorage.currentRequest == .disabled)
          #expect(AnimationContextStorage.currentCustomValues == outer.customValues)
          try withTransaction(\.isContinuous, false) {
            #expect(!AnimationContextStorage.currentIsContinuous)
            #expect(AnimationContextStorage.currentTracksVelocity)
            throw ScopeFailure.expected
          }
        }
        Issue.record("the nested fixture must throw")
      } catch ScopeFailure.expected {
      } catch {
        Issue.record("unexpected scope failure: \(error)")
      }
      #expect(AnimationContextStorage.currentRequest == outer.request)
      #expect(AnimationContextStorage.currentIsContinuous)
      #expect(AnimationContextStorage.currentTracksVelocity)
      #expect(AnimationContextStorage.currentCustomValues == outer.customValues)
    }
    #expect(AnimationContextStorage.currentRequest == baselineRequest)
    #expect(AnimationContextStorage.currentCustomValues == baselineKeys)
  }

  @Test("set A 249: an explicitly nil transaction value does not fall back to its nonnil default")
  func setA249OptionalTransactionValueRetainsExplicitNil() {
    // Hypothesis: optional unboxing can flatten an authored nil into absence and resurrect the key's default.
    var transaction = Transaction()
    #expect(transaction[OptionalKey.self] == 42)
    transaction[OptionalKey.self] = nil
    #expect(transaction[OptionalKey.self] == nil)
    var copy = transaction
    copy[OptionalKey.self] = 7
    #expect(copy[OptionalKey.self] == 7)
    #expect(transaction[OptionalKey.self] == nil)
  }

  @Test("set A 250: animation state copies and type replacement cannot expose stale values")
  func setA250AnimationStateCopyAndTypeReplacement() {
    // Hypothesis: type-erased state can retain a value under the wrong type or share a mutable copy's storage.
    var original = AnimationState()
    original["payload", as: [Int].self] = [1, 2]
    var copy = original
    copy["payload", as: String.self] = "replacement"
    #expect(copy["payload", as: [Int].self] == nil)
    #expect(copy["payload", as: String.self] == "replacement")
    #expect(original["payload", as: [Int].self] == [1, 2])
    copy["payload", as: String.self] = nil
    #expect(copy["payload", as: String.self] == nil)
    #expect(original["payload", as: [Int].self] == [1, 2])
  }

  private struct CountingLinearCurve: CustomAnimation {
    let rate: Double

    func animate<V: VectorArithmetic>(
      value: V, time: Duration, context: inout AnimationContext<V>
    ) -> V? {
      context.state["calls", as: Int.self] = (context.state["calls", as: Int.self] ?? 0) + 1
      return value.scaled(by: time.totalSeconds * rate)
    }

    func velocity<V: VectorArithmetic>(
      value: V, time: Duration, context: AnimationContext<V>
    ) -> V? {
      value.scaled(by: rate)
    }
  }

  private struct Marker: Equatable {
    var x: Double
    var y: Double
  }

  private struct Coordinates: Animatable, Equatable {
    var values: [Double]

    var animatableData: AnimatableArray<Double> {
      get { .init(values) }
      set { values = newValue.elements }
    }
  }

  private struct LabelKey: TransactionKey {
    static let defaultValue = "default"
  }

  private struct OptionalKey: TransactionKey {
    static let defaultValue: Int? = 42
  }

  private enum ScopeFailure: Error {
    case expected
  }
}
