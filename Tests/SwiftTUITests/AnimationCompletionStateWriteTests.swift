import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

/// H3 — a `@State` write from a `withAnimation` completion closure must reach
/// the live state location, not a detached seed box.
///
/// `withAnimation(_:completionCriteria:_:completion:)`'s documentation promises
/// this: the completion is `@MainActor` specifically so it "lets the closure
/// write view state directly".
///
/// The mechanism is `State.wrappedValue`'s setter:
///
/// ```swift
/// nonmutating set {
///   if let location = activeLocation() { location.setValue(newValue) }
///   else { box.updateSeedValue(newValue) }      // detached seed
/// }
/// ```
///
/// `activeLocation()` returns nil when `AuthoringContextStorage.current` is
/// nil, so a write executed outside any authoring scope silently updates the
/// *seed* — the value a fresh node would start from — instead of the live slot.
/// Nothing invalidates and the visible state never changes, which is
/// indistinguishable from the write not happening. This is the same class
/// `AuthoringContextStorage.current`'s own comment describes for `.task`
/// closures ("the WASI Game-of-Life freeze").
///
/// `AnimationController.fireOrDeferCompletion` and its deferred drain both
/// invoke the registered closure **bare**, with no authoring scope restored,
/// so the wrapping has to happen at registration time — which is what
/// `ImperativeAuthoringContextSnapshot` exists for and what toolbar and key
/// handlers already do.
///
/// Reduced from a live FIXME in `swift-tui-examples`' `counter` example,
/// where `activeRipple = false` from a completion closure "seems to execute,
/// but does not appear to set the state". The demo's `.background` and
/// `ConditionalContent` shape is incidental and is omitted here.
///
/// **Determinism note.** This test does *not* pump frames waiting for an
/// animation to drain. Driving `render()` in a loop while a `.linear`
/// animation is live does not terminate — the animation keeps requesting
/// frames, so the pump spins. Instead a probe sink captures the closure
/// `withAnimation` actually registers, and the test fires it bare, exactly as
/// `fireOrDeferCompletion` does. That covers both halves of the contract: the
/// registration-time wrapping and the context-free invocation.
@MainActor
struct AnimationCompletionStateWriteTests {
  @Test("a @State write from a withAnimation completion reaches the live location")
  func stateWriteFromAnimationCompletionReachesLiveLocation() throws {
    let sink = CapturingCompletionSink()

    let harness = try AnimationCompletionStorage.withSink(sink) {
      try StressRuntimeHarness(
        rootIdentity: testIdentity("AnimationCompletionStateWrite"),
        size: .init(width: 40, height: 6)
      ) {
        CompletionWritesStateView()
      }
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("armed=false"))

    // The button action runs `withAnimation { armed = true } completion: {
    // armed = false }`. The sink captures whatever closure withAnimation
    // registered — scoped or bare.
    try AnimationCompletionStorage.withSink(sink) {
      _ = try harness.clickText("Arm")
    }
    #expect(harness.frame.contains("armed=true"), "the arming write itself must land")

    let registered = try #require(
      sink.lastClosure,
      "withAnimation must register a completion closure"
    )

    // Fire it the way AnimationController does: bare, no authoring scope.
    registered()
    _ = try harness.render()

    #expect(
      harness.frame.contains("armed=false"),
      """
      the completion closure's `armed = false` never reached the live state \
      location; it degraded to a detached seed write, so nothing invalidated \
      and the visible state never changed. Frame:
      \(harness.frame)
      """
    )
  }

  /// Guards the diagnosis rather than the symptom: the same write performed
  /// *inside* an authoring scope must land. If this ever fails too, the cause
  /// is not the missing authoring context and the analysis above is wrong.
  @Test("the same write inside an authoring scope does land")
  func sameWriteInsideAuthoringScopeLands() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AnimationCompletionStateWriteControl"),
      size: .init(width: 40, height: 6)
    ) {
      CompletionWritesStateView()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Arm")
    #expect(harness.frame.contains("armed=true"))

    // "Disarm" performs the identical write from a button action, which runs
    // inside an authoring scope.
    _ = try harness.clickText("Disarm")
    #expect(
      harness.frame.contains("armed=false"),
      "control: an ordinary action-scoped write must land\n\(harness.frame)"
    )
  }
}

/// Captures the closure `withAnimation` registers, so a test can fire it the
/// way the controller does.
@MainActor
private final class CapturingCompletionSink: AnimationCompletionSink {
  var lastClosure: (@MainActor @Sendable () -> Void)?

  func registerCompletion(
    batchID: AnimationBatchID,
    barrier _: AnimationCompletionBarrier = .logicallyComplete,
    closure: @escaping @MainActor @Sendable () -> Void
  ) {
    lastClosure = closure
  }
}

private struct CompletionWritesStateView: View {
  @State private var armed = false

  var body: some View {
    VStack(spacing: 0) {
      Text("armed=\(armed ? "true" : "false")")
      Button("Arm") {
        withAnimation(.linear(duration: .milliseconds(1))) {
          armed = true
        } completion: {
          armed = false
        }
      }
      Button("Disarm") {
        armed = false
      }
    }
  }
}
