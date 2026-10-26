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
    await setCKnownAsync(setCNEW7) {
      await #expect(processExitsWith: .success) {
        let spring = Spring(mass: 1, stiffness: -4, damping: 1)
        _ = spring.dampingRatio
      }
    }
  }

  @Test func setC218MasslessSpringSettlingDurationIsFinite() async {
    await #expect(processExitsWith: .success) {
      let spring = Spring(mass: 0, stiffness: 4, damping: 1)
      _ = spring.settlingDuration
    }
  }

  @Test func setC219KeyframeTimelineNaNProgressIsFinite() async {
    await setCKnownAsync(setCNEW8) {
      await #expect(processExitsWith: .success) {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
          LinearKeyframe(1.0, duration: .seconds(1))
        }
        _ = timeline.value(progress: .nan)
      }
    }
  }

  @Test func setC220KeyframeTimelineHugeProgressIsFinite() async {
    await setCKnownAsync(setCNEW8) {
      await #expect(processExitsWith: .success) {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
          LinearKeyframe(1.0, duration: .seconds(1))
        }
        _ = timeline.value(progress: 1e30)
      }
    }
  }

  @Test func setC221InfiniteToastDurationStaysVisible() async {
    await setCKnownAsync(setCNEW9) {
      await #expect(processExitsWith: .success) {
        try await setCToastDurationProbe(.infinity, name: "221")
      }
    }
  }

  @Test func setC222HugeToastDurationStaysVisible() async {
    await setCKnownAsync(setCNEW9) {
      await #expect(processExitsWith: .success) {
        try await setCToastDurationProbe(1e21, name: "222")
      }
    }
  }

  // Pin: `nan > 0` is false, so a NaN duration arms no deadline.
  @Test func setC223NaNToastDurationArmsNoDeadline() async {
    await #expect(processExitsWith: .success) {
      try await setCToastDurationProbe(.nan, name: "223")
    }
  }

  @Test func setC224HugeScaleTransitionAnimates() async {
    await setCKnownAsync(setCRES1) {
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

private let setCNEW7 = Comment(
  rawValue:
    "NEW-7: Spring(mass:stiffness:damping:) with a negative stiffness traps "
    + "constructing the spring; the NaN natural period passes max(NaN, 1e-9) "
    + "and Duration.seconds(NaN) traps (Spring.swift:52-55); contract: SwiftUI "
    + "Spring init, FW-E caller-value contract")
private let setCNEW8 = Comment(
  rawValue:
    "NEW-8: KeyframeTimeline.value(progress:) traps for a NaN or out-of-range "
    + "progress; it builds Duration.seconds(duration * progress) unchecked "
    + "(KeyframeTimeline.swift:64-67); contract: SwiftUI "
    + "KeyframeTimeline.value(progress:)")
private let setCNEW9 = Comment(
  rawValue:
    "NEW-9: a toast with duration .infinity or 1e21 terminates the process "
    + "when its bar task starts; the task guards duration > 0 and then traps in "
    + "Duration.seconds(duration) (ToastPresentation.swift:836-839); contract: "
    + "ToastPresentation.swift:525-528, 543-544 (how many seconds the toast "
    + "stays visible)")
private let setCRES1 = Comment(
  rawValue:
    "FW-E residual (recorded, unfiled): a .transition(.scale(scale: 1e300)) "
    + "insertion traps sampling the overlay; scaledTransitionRect converts "
    + "Double(width) * scale with Int(_:) "
    + "(PlacedAnimationOverlay.swift:317-318), on FW-E's unswept "
    + "PlacedAnimationOverlay list; contract: FW-E caller-value contract; "
    + "adjacent STUI-741")
