import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

/// The stuck-ripple absorbing state (counter demo, 2026-08-06): a
/// `withAnimation { } completion:` closure and a same-frame `onChange`
/// lifecycle action used to share one frame-commit station with no resolve
/// between them. The completion's guard-flag write (`activeRipple = false`)
/// was immediately overwritten by the `onChange` re-raise (`= true`) before
/// any resolve observed the intermediate `false`, so the flag committed
/// "unchanged", the guarded branch never unmounted, its one-shot mount
/// animation never re-armed, and every later press was absorbed by the
/// raised guard. Only a restart healed it.
///
/// SwiftUI is structurally immune: a completion's write, the body
/// re-evaluation it causes, and the resulting unmount commit as ONE
/// main-actor unit before the next input action can run (native probe:
/// 12/12 immune under an 8 ms press burst).
///
/// The framework fix defers committed-frame animation completions past the
/// lifecycle dispatch of the frame they ride with: `onChange` observes
/// pre-completion state, the completion's writes then get their own resolve
/// before any later lifecycle action can read them. Either serialization is
/// race-free; sharing one station was not.
///
/// **Determinism.** The PTY repro fired ~40% per boundary because it had to
/// phase-align a real-time press burst against the animation deadline. This
/// test controls the frame pump instead: completions only fire via a frame's
/// animation tick, so letting the deadline expire WITHOUT rendering and then
/// dispatching press+release with no render in between forces one frame that
/// both plans the `onChange` and crosses the deadline — the collision frame,
/// every run. The seed animation is armed from `onAppear` (same commit
/// station as the demo's one-shot `.task`, but synchronous).
///
/// **Why the deadline waits are real sleeps, not virtual time.** The
/// animation clock is the injectable `RunLoop.frameClock`, but warping it
/// cannot cross an in-flight deadline on its own: a deadline-triggered frame
/// pins its instant to the STORED deadline (`deriveFrameInstant`), and stored
/// deadlines derive from pre-warp instants, so a mid-test clock jump
/// desynchronizes from every armed deadline instead of crossing it. The
/// sleeps are wall-clock deadline passage with the pump halted — there is no
/// concurrent work to race, so they are not timeout-driven synchronisation
/// (they are counted in the sync-policy baseline as such; see
/// `Scripts/check_test_sync_policies.sh`).
///
/// Crossing the deadline takes the sleep AND `armPostSleepDeadline`: the
/// stale armed deadline would otherwise remain the frame's instant no matter
/// how long the sleep was. Arming a fresh one makes the post-sleep instant
/// the latest due deadline, and therefore the instant the frame animates at.
@MainActor
struct AnimationCompletionLifecycleOrderTests {
  @Test("a same-frame onChange cannot swallow a withAnimation completion's guard-flag write")
  func sameFrameOnChangeDoesNotSwallowCompletionWrite() async throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompletionOnChangeRace"),
      size: .init(width: 44, height: 8)
    ) {
      CompletionOnChangeRaceFixture()
    }
    defer { harness.shutdown() }

    // `RunLoop.run()` installs the renderer's controller as the task-local
    // animation sinks for its entire task tree; the harness drives
    // `renderPendingFrames` directly, so the fixture's `onAppear`-scoped
    // `withAnimation` needs the same installation or its registration
    // silently drops (F116: task-local sinks exclusively).
    let controller = harness.runLoop.renderer.internalAnimationController
    func interact<Result>(_ operation: () throws -> Result) rethrows -> Result {
      try AnimationRegistrationStorage.withSink(controller) {
        try TransitionRegistrationStorage.withSink(controller) {
          try AnimationCompletionStorage.withSink(controller) {
            try operation()
          }
        }
      }
    }

    #expect(harness.frame.contains("ripple=off"))

    // Seed: the press raises the guard flag at commit; the next frame mounts
    // the layer, whose onAppear registers the animated write + completion.
    try interact { _ = try harness.clickText("Bump") }
    #expect(harness.frame.contains("count=1"))
    #expect(
      harness.frame.contains("ripple=on"),
      """
      the seed press must leave the ripple branch mounted with its animation \
      in flight. If it is already off, the batch retained nothing (the \
      completion fired on the next tick) and this test cannot reach the \
      collision station. Frame:
      \(harness.frame)
      """
    )

    // Let the completion deadline expire without pumping a frame. The margin
    // over the 1 s animation only needs to be positive; more is safer.
    try await Task.sleep(for: .milliseconds(1500))
    armPostSleepDeadline(harness)

    // The colliding press: both events dispatch before one render, so the
    // same frame carries the count change (planning its onChange) AND
    // crosses the completion deadline at its animation tick.
    let bump = try #require(harness.point(forText: "Bump"))
    try interact {
      #expect(
        harness.runLoop.handle(
          RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: bump)))
        ) == nil
      )
      #expect(
        harness.runLoop.handle(
          RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: bump)))
        ) == nil
      )
      _ = try harness.render()
      _ = try harness.render()
    }

    #expect(harness.frame.contains("count=2"), "the colliding press's action must land")
    #expect(
      harness.frame.contains("ripple=off"),
      """
      absorbing stuck state: the completion's guard-flag lowering was \
      swallowed by the same frame's onChange re-raise, so the guarded branch \
      never unmounted. Frame:
      \(harness.frame)
      """
    )

    // The guard must re-arm cleanly: a later press re-raises the flag, the
    // branch re-mounts fresh, and its new animation's completion lowers it
    // again once the deadline passes.
    try interact { _ = try harness.clickText("Bump") }
    #expect(harness.frame.contains("count=3"))
    #expect(
      harness.frame.contains("ripple=on"),
      "a fresh press after the collision must re-mount the ripple branch\n\(harness.frame)"
    )
    try await Task.sleep(for: .milliseconds(1500))
    armPostSleepDeadline(harness)
    try interact {
      _ = try harness.render()
      _ = try harness.render()
    }
    #expect(
      harness.frame.contains("ripple=off"),
      "the re-armed ripple's own completion must lower the guard\n\(harness.frame)"
    )
  }

  /// Arms a deadline at the instant the preceding sleep reached, so the frame
  /// driven next answers *that* instant.
  ///
  /// A frame animates at `deriveFrameInstant` — `triggeredDeadline ?? consumedAt`
  /// — so a frame woken by a deadline armed before the sleep animates at that
  /// STALE deadline, one 33 ms cadence step past the animation's start,
  /// however long the sleep was. Sleeping therefore does not cross a 1 s
  /// completion deadline by itself. `consumeReadyFrame` triggers on the LATEST
  /// due deadline, so arming one now makes the post-sleep instant the frame's
  /// instant and the elapsed sleep becomes the animation's elapsed time.
  ///
  /// This was invisible until the synchronous frame driver was fixed to thread
  /// its `frameInstant` into the render (`RunLoop+Rendering.swift`): it used to
  /// let `renderArtifacts` default the instant to `.now()`, so animation always
  /// advanced at wall-clock speed under this driver regardless of the frame's
  /// own instant — and no pinned `frameClock` could reach it.
  private func armPostSleepDeadline<Content: View>(
    _ harness: StressRuntimeHarness<Content>
  ) {
    harness.runLoop.scheduler.requestDeadline(.now())
  }
}

/// The counter demo's shape, reduced: a guard flag raised by `onChange`,
/// a branch mounted by the flag, a one-shot animation armed at mount whose
/// completion lowers the flag. `progress` is parent-owned so the re-raise
/// path can reset it before a re-mount re-animates it.
@MainActor
private struct CompletionOnChangeRaceFixture: View {
  @State private var count = 0
  @State private var activeRipple = false
  @State private var progress: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Bump") { count += 1 }
      Text("count=\(count)")
      Text(activeRipple ? "ripple=on" : "ripple=off")
      if activeRipple {
        Text("layer")
          .opacity(progress)
          .onAppear {
            withAnimation(.linear(duration: .milliseconds(1000))) {
              progress = 1
            } completion: {
              activeRipple = false
            }
          }
      }
    }
    .frame(width: 44, height: 8, alignment: .topLeading)
    .onChange(of: count) {
      if !activeRipple {
        progress = 0
        activeRipple = true
      }
    }
  }
}
