@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The Android one-ripple-per-launch defect (counter demo, 2026-08-16).
///
/// ``RunLoop/run()`` installs the animation / transition / completion sinks as
/// **task-locals of its own task**, so every registration the loop drives
/// inherits them — including registrations made inside a `.task` body, because
/// an unstructured `Task` copies the creating task's locals.
///
/// ``RunLoop/processPendingEventsSynchronously(from:renderedFrames:)`` is the
/// one re-entry point that runs OUTSIDE that task: the Android host reaches it
/// from the JNI `send_input` call on the Android main thread, with no enclosing
/// `Task` to inherit from. Every sink then read `nil`, and because
/// `withAnimation` registers through optional chaining, both registrations were
/// dropped in silence — the authored curve never reached the controller (the
/// default played instead) and the completion closure was never registered, so
/// `releaseBatch` had nothing to fire. In the counter demo that wedged the
/// "one ripple at a time" guard closed for the life of the process.
///
/// This test drives the same shape: a frame acquired through the synchronous
/// re-entry mounts a view whose `.task` registers an animation with a
/// completion. Off the fix, both sinks are `nil` and the completion never
/// fires.
///
/// **Determinism.** The animation is a function of which instant a frame
/// answers, so the test owns ``RunLoop/frameClock`` and advances it by hand
/// rather than sleeping past a real deadline; the `.task` body signals through
/// an `AsyncEvent` rather than being polled for.
@MainActor
struct SynchronousReentryRegistrationScopeTests {
  @Test("a synchronously re-entered frame carries the run loop's registration sinks")
  func synchronousReentryInstallsRegistrationSinks() async throws {
    let probe = SyncReentryProbeLog()
    SyncReentryProbeLog.current = probe
    defer { SyncReentryProbeLog.current = nil }

    let rootIdentity = testIdentity("SyncReentryRegistrationScope")
    let surface = RecordingPresentationSurface(surfaceSize: .init(width: 32, height: 6))
    let scheduler = FrameScheduler()
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    )
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: DefaultRenderer(),
      presentationSurface: surface,
      terminalInputReader: InjectedTerminalInputReader(),
      scheduler: scheduler,
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      proposal: .init(width: 32, height: 6),
      viewBuilder: { value, _ in
        SyncReentryFixture(showsProbe: value == 1)
      }
    )
    focusTracker.invalidator = scheduler

    let clock = SyncReentryFrameClock()
    runLoop.frameClock = { clock.now }

    // Boot frame: the probe is not mounted yet.
    var renderedFrames = 0
    scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let eventPump = runLoop.makeEventPump()
    defer { eventPump.cancel() }

    // The Android seam: a frame driven through the synchronous re-entry point,
    // from a context that has installed nothing. It mounts the probe, whose
    // `.task` registers the animation and its completion.
    stateContainer.replace(with: 1)
    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try runLoop.processPendingEventsSynchronously(
      from: eventPump,
      renderedFrames: &renderedFrames
    )

    // The `.task` body runs on its own turn and signals when it has registered.
    await probe.didRegister.wait()

    #expect(
      probe.sawCompletionSink,
      """
      the `.task` body saw no completion sink, so `withAnimation`'s completion \
      closure was dropped by optional chaining and can never fire.
      """
    )
    #expect(
      probe.sawRegistrationSink,
      """
      the `.task` body saw no animation-registration sink, so the authored \
      `Animation` never reached the controller and the default curve played.
      """
    )

    // End-to-end: the registered completion must actually fire. One frame
    // starts the animation and the next answers an instant well past its 1 ms
    // schedule, so this converges in two — the iteration bound only keeps a
    // regression from looping, it is not the mechanism under test.
    for _ in 0..<8 where probe.completionCount == 0 {
      clock.advance(by: .milliseconds(50))
      scheduler.requestDeadline(clock.now)
      _ = try runLoop.processPendingEventsSynchronously(
        from: eventPump,
        renderedFrames: &renderedFrames
      )
    }

    #expect(
      probe.completionCount == 1,
      "the withAnimation completion registered under the synchronous re-entry must fire"
    )
  }
}

/// A hand-advanced ``RunLoop/frameClock`` source.
@MainActor
private final class SyncReentryFrameClock {
  private(set) var now = MonotonicInstant.now()

  func advance(by duration: Duration) {
    now = now.advanced(by: duration)
  }
}

@MainActor
private final class SyncReentryProbeLog {
  static var current: SyncReentryProbeLog?

  let didRegister = AsyncEvent()
  var sawCompletionSink = false
  var sawRegistrationSink = false
  var completionCount = 0
}

private struct SyncReentryFixture: View {
  let showsProbe: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("root")
      if showsProbe {
        SyncReentryProbeView()
      }
    }
    .frame(width: 32, height: 6, alignment: .topLeading)
  }
}

/// The counter demo's ripple, reduced: state animated from a `.task` armed at
/// mount, whose completion is the only thing that reports the animation ended.
private struct SyncReentryProbeView: View {
  @State private var progress: Double = 0

  var body: some View {
    Text("probe")
      .opacity(progress)
      .task {
        @MainActor in
        let log = SyncReentryProbeLog.current
        log?.sawCompletionSink = AnimationCompletionStorage.effectiveSink != nil
        log?.sawRegistrationSink = AnimationRegistrationStorage.effectiveSink != nil
        withAnimation(.linear(duration: .milliseconds(1))) {
          progress = 1
        } completion: {
          SyncReentryProbeLog.current?.completionCount += 1
        }
        log?.didRegister.fire()
      }
  }
}
