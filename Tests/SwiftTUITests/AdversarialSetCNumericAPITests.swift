import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 2: public APIs that build a `Duration` (or an
/// `Int`) from a caller `Double`. `Duration.seconds(_:)` traps on NaN,
/// infinity and magnitudes past its `Int128` attosecond range.
@MainActor
@Suite(.serialized)
struct AdversarialSetCNumericAPITests {
  @Test func setC217NegativeStiffnessSpringConstructs() async {
    await #expect(processExitsWith: .success) {
      let spring = Spring(mass: 1, stiffness: -4, damping: 1)
      _ = spring.dampingRatio
    }
  }

  @Test func setC218MasslessSpringSettlingDurationIsFinite() async {
    await #expect(processExitsWith: .success) {
      let spring = Spring(mass: 0, stiffness: 4, damping: 1)
      _ = spring.settlingDuration
    }
  }

  @Test func setC219KeyframeTimelineNaNProgressIsFinite() async {
    await #expect(processExitsWith: .success) {
      let timeline = KeyframeTimeline(initialValue: 0.0) {
        LinearKeyframe(1.0, duration: .seconds(1))
      }
      _ = timeline.value(progress: .nan)
    }
  }

  @Test func setC220KeyframeTimelineHugeProgressIsFinite() async {
    await #expect(processExitsWith: .success) {
      let timeline = KeyframeTimeline(initialValue: 0.0) {
        LinearKeyframe(1.0, duration: .seconds(1))
      }
      _ = timeline.value(progress: 1e30)
    }
  }

  @Test func setC221InfiniteToastDurationStaysVisible() async {
    await #expect(processExitsWith: .success) {
      try await setCToastDurationProbe(.infinity, name: "221")
    }
  }

  @Test func setC222HugeToastDurationStaysVisible() async {
    await #expect(processExitsWith: .success) {
      try await setCToastDurationProbe(1e21, name: "222")
    }
  }

  // Pin: `nan > 0` is false, so a NaN duration arms no deadline.
  @Test func setC223NaNToastDurationArmsNoDeadline() async {
    await #expect(processExitsWith: .success) {
      try await setCToastDurationProbe(.nan, name: "223")
    }
  }

  @Test func setC224HugeScaleTransitionAnimates() async {
    await #expect(processExitsWith: .success) {
      try await MainActor.run {
        let box = SetCNumericBox()
        let h = try StressRuntimeHarness(
          rootIdentity: testIdentity("setC224"),
          size: .init(width: 20, height: 4)
        ) { SetCScaleTransitionRoot(box: box) }
        defer { h.shutdown() }
        let clock = SetCNumericClock()
        h.runLoop.frameClock = { clock.now }
        let controller = h.runLoop.renderer.internalAnimationController
        let show = try #require(box.show)
        try withAnimationSinks(controller) {
          withAnimation(.linear(duration: .seconds(1))) { show.wrappedValue = true }
          _ = try h.render()
          clock.now = clock.now.advanced(by: .milliseconds(300))
          _ = try h.render()
        }
      }
    }
  }

  // MARK: - Wave 4 FW-I regressions (STUI-1304, STUI-742, STUI-758, STUI-790)

  /// STUI-1304: a spring whose natural frequency is NaN (a negative or NaN
  /// stiffness) has a zero period and the capped settling time; an infinite
  /// frequency keeps its zero period, and a non-positive mass keeps the
  /// solver's 0.001 floor.
  @Test func nonFiniteSpringFrequencyHasDefinedDurations() {
    for spring in [
      Spring(mass: 1, stiffness: -4, damping: 1),
      Spring(mass: 1, stiffness: -.infinity, damping: 1),
      Spring(mass: 1, stiffness: .nan, damping: 1),
    ] {
      #expect(spring.duration == .zero)
      #expect(spring.settlingDuration == .seconds(60))
    }
    #expect(Spring(mass: 1, stiffness: .infinity, damping: 1).duration == .zero)
    #expect(Spring(mass: 1, stiffness: 4, damping: 1).duration == .seconds(Double.pi))
    #expect(
      Spring(mass: -1, stiffness: 4, damping: 1).duration
        == .seconds(2 * Double.pi / (4 / 0.001).squareRoot()))
  }

  /// STUI-1304: a NaN progress samples the timeline's start, progress beyond
  /// either end clamps to that end, and an in-range progress is unchanged.
  @Test func keyframeTimelineProgressSaturates() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
      LinearKeyframe(1.0, duration: .seconds(1))
    }
    #expect(timeline.value(progress: .nan) == timeline.value(time: .zero))
    #expect(timeline.value(progress: 1e30) == 1.0)
    #expect(timeline.value(progress: .infinity) == 1.0)
    #expect(timeline.value(progress: -1e30) == 0.0)
    #expect(timeline.value(progress: -.infinity) == 0.0)
    #expect(timeline.value(progress: 0.25) == 0.25)
  }

  /// STUI-742: `repeatCount(.max)` has a saturated total duration whose
  /// components are readable, and its iterations still evaluate.
  @Test func repeatCountMaxSaturatesTotalDuration() throws {
    let long = Animation.linear(duration: .seconds(100)).repeatCount(.max, autoreverses: false)
    #expect(long.totalDuration == SaturatingConversion.durationBound)
    let short = Animation.linear(duration: .seconds(1)).repeatCount(.max, autoreverses: false)
    let total = try #require(short.totalDuration)
    #expect(total == SaturatingConversion.durationBound)
    #expect(total.components.seconds == Int64(1) << 62)
    let iteration = try #require(short.evaluate(elapsed: .milliseconds(1_500)))
    #expect(abs(iteration - 0.5) < 1e-9)
    #expect(Animation.linear(duration: .seconds(1)).repeatCount(3).totalDuration == .seconds(3))
  }

  /// STUI-742: a NaN, infinite or huge speed evaluates without trapping. NaN
  /// never advances, an infinite or huge speed completes at once, and a
  /// negative one holds the start.
  @Test func extremeAnimationSpeedsEvaluate() {
    let base = Animation.linear(duration: .seconds(1))
    #expect(base.speed(.nan).evaluate(elapsed: .seconds(1)) == 0)
    #expect(base.speed(.infinity).evaluate(elapsed: .seconds(1)) == nil)
    #expect(base.speed(1e300).evaluate(elapsed: .seconds(1)) == nil)
    #expect(base.speed(-1e300).evaluate(elapsed: .seconds(1)) == 0)
    #expect(base.speed(-.infinity).evaluate(elapsed: .seconds(1)) == 0)
    #expect(abs((base.speed(2).evaluate(elapsed: .milliseconds(250)) ?? 0) - 0.5) < 1e-9)
    #expect(base.speed(.infinity).totalDuration == .zero)
  }

  /// STUI-742: an undamped spring with zero natural frequency has an infinite
  /// period; repeating it saturates instead of trapping.
  @Test func zeroFrequencySpringRepeatSaturates() {
    let animation = Animation.interpolatingSpring(stiffness: 0, damping: 0).repeatCount(2)
    #expect(animation.totalDuration == SaturatingConversion.durationBound)
    _ = animation.evaluate(elapsed: .seconds(1))
  }

  /// STUI-742: delays add with saturation, so the total stays readable.
  @Test func hugeDelaysSaturate() throws {
    let animation = Animation.linear(duration: .seconds(1))
      .delay(.seconds(Int64.max)).delay(.seconds(Int64.max))
    let total = try #require(animation.totalDuration)
    #expect(total == SaturatingConversion.durationBound)
    #expect(total.components.seconds == Int64(1) << 62)
    #expect(animation.evaluate(elapsed: .seconds(1)) == 0)
  }

  /// STUI-758: the toast's deadline. `nil`, a non-positive value, NaN,
  /// infinity and a finite value beyond the representable bound arm none;
  /// any other value is that many seconds.
  @Test func toastDurationsMapToDeadlines() {
    #expect(toastAutoDismissDelay(seconds: nil) == nil)
    #expect(toastAutoDismissDelay(seconds: 3) == .seconds(3))
    #expect(toastAutoDismissDelay(seconds: 0.01) == .seconds(0.01))
    #expect(toastAutoDismissDelay(seconds: 1e18) == .seconds(1e18))
    for none in [0, -1, -0.0, .nan, .infinity, -.infinity, 1e21, Double(Int64(1) << 62)] {
      #expect(toastAutoDismissDelay(seconds: none) == nil, "\(none)")
    }
  }

  /// STUI-790: a huge scale saturates the scaled rect around its anchor; a
  /// non-finite anchor or scale leaves the rect unchanged.
  @Test func extremeTransitionScaleSaturatesAroundTheAnchor() {
    let rect = CellRect(origin: .init(x: 5, y: 5), size: .init(width: 4, height: 2))
    let huge = scaledTransitionRect(rect, scale: 1e300, anchor: .center)
    #expect(
      huge.size
        == CellSize(width: SaturatingConversion.upperBound, height: SaturatingConversion.upperBound)
    )
    #expect(huge.origin.x < rect.origin.x && huge.maxX > rect.maxX)
    #expect(huge.origin.y < rect.origin.y && huge.maxY > rect.maxY)
    for anchor in [
      UnitPoint(x: .nan, y: 0.5), UnitPoint(x: 0.5, y: .infinity),
      UnitPoint(x: -.infinity, y: .nan),
    ] {
      #expect(scaledTransitionRect(rect, scale: 2, anchor: anchor) == rect)
    }
    #expect(scaledTransitionRect(rect, scale: .nan, anchor: .center) == rect)
    let far = scaledTransitionRect(rect, scale: 2, anchor: UnitPoint(x: 1e300, y: -1e300))
    #expect(far.size == CellSize(width: 8, height: 4))
  }

  /// STUI-790: in-range scales and anchors give exactly the original formula.
  @Test func transitionScaleIsUnchangedInRange() {
    func original(_ rect: CellRect, _ scale: Double, _ anchor: UnitPoint) -> CellRect {
      let magnitude = abs(scale)
      let width = max(Int((Double(rect.size.width) * magnitude).rounded()), 0)
      let height = max(Int((Double(rect.size.height) * magnitude).rounded()), 0)
      let anchorX = Double(rect.origin.x) + anchor.x * Double(rect.size.width)
      let anchorY = Double(rect.origin.y) + anchor.y * Double(rect.size.height)
      return CellRect(
        origin: CellPoint(
          x: Int((anchorX - anchor.x * Double(width)).rounded()),
          y: Int((anchorY - anchor.y * Double(height)).rounded())),
        size: CellSize(width: width, height: height))
    }
    var compared = 0
    for rect in [
      CellRect(origin: .zero, size: .init(width: 1, height: 1)),
      CellRect(origin: .init(x: -7, y: 3), size: .init(width: 13, height: 5)),
      CellRect(origin: .init(x: 40, y: -2), size: .init(width: 80, height: 24)),
    ] {
      for scale in [0, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3.7, -0.5, 1000] {
        for anchor in [
          UnitPoint.topLeading, .center, .bottomTrailing, UnitPoint(x: -0.3, y: 1.4),
          UnitPoint(x: 0.33, y: 0.66),
        ] {
          #expect(
            scaledTransitionRect(rect, scale: scale, anchor: anchor)
              == original(rect, scale, anchor))
          compared += 1
        }
      }
    }
    #expect(compared == 165)
  }

  /// STUI-790 neighbours: an offset transition past either end of its
  /// progress, and a matched-geometry rect with a non-finite anchor or an
  /// extreme size, saturate instead of trapping.
  @Test func extremeTransitionOffsetsAndMatchedRectsSaturate() {
    let removal = AnimationTransitionOverlay.interpolatedRemovalModifiers(
      from: 1, to: TransitionModifiers(offsetX: Int.max, offsetY: Int.min), progress: 1.5)
    #expect(removal.offsetX == SaturatingConversion.upperBound)
    #expect(removal.offsetY == SaturatingConversion.lowerBound)
    let from = CellRect(origin: .zero, size: .init(width: 2, height: 1))
    let to = CellRect(origin: .init(x: 10, y: 0), size: .init(width: Int.max, height: 1))
    let overshoot = PlacedAnimationOverlaySampling.interpolatedMatchedRect(
      from: from, to: to, properties: [.position, .size], anchor: .center, progress: 1.5)
    #expect(overshoot.size == CellSize(width: SaturatingConversion.upperBound, height: 1))
    let unanchored = PlacedAnimationOverlaySampling.interpolatedMatchedRect(
      from: from, to: to, properties: [.position, .size], anchor: UnitPoint(x: .nan, y: 0),
      progress: 0.5)
    #expect(unanchored == to)
  }
}

/// Mounts a toast with `duration` beside a 10 ms toast whose own deadline is
/// the readiness signal: both bars' tasks start at one commit, so the probe's
/// task has run its duration conversion before the short sleep resumes.
@MainActor
private func setCToastDurationProbe(_ duration: Double, name: String) async throws {
  let signal = MainActorConditionSignal()
  let box = SetCNumericBox()
  box.signal = signal
  let h = try StressRuntimeHarness(
    rootIdentity: testIdentity("setC\(name)"),
    size: .init(width: 40, height: 8)
  ) { SetCToastRoot(duration: duration, box: box) }
  defer { h.shutdown() }
  #expect(h.frame.contains("probe toast"))
  await signal.wait { !box.shortShown }
  _ = try h.render()
  #expect(h.frame.contains("probe toast"))
}

@MainActor
private final class SetCNumericBox {
  var shortShown = true
  var signal: MainActorConditionSignal?
  var show: Binding<Bool>?

  var shortBinding: Binding<Bool> {
    Binding(
      get: { self.shortShown },
      set: {
        self.shortShown = $0
        self.signal?.notify()
      })
  }
}

@MainActor
private final class SetCNumericClock { var now = MonotonicInstant.now() }

private struct SetCToastRoot: View {
  let duration: Double
  let box: SetCNumericBox

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("base")
        .toast("probe toast", isPresented: .constant(true), duration: duration)
      Text("short base")
        .toast("short toast", isPresented: box.shortBinding, duration: 0.01)
    }
  }
}

private struct SetCScaleTransitionRoot: View {
  @State private var shown = false
  let box: SetCNumericBox

  var body: some View {
    box.show = $shown
    return VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      if shown {
        Text("scaled").transition(.scale(scale: 1e300))
      }
    }
  }
}
