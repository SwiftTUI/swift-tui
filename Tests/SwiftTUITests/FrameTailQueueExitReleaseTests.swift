import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Pins the cancel-free frame-tail seam (`swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md` entry
/// 14): the queued-cancellation signal wait is retired by the token's queue
/// exit through `PendingFrameWaitReleasing`, never by cancelling a task, so
/// no cancel can land concurrently with a first schedule or resume-enqueue.
@Suite(.serialized)
struct FrameTailQueueExitReleaseTests {
  @Test("queue-exit release fires exactly once when the worker starts the job")
  func queueExitReleaseFiresOnWorkerStart() {
    let token = FrameTailJobCancellationToken()
    let firedCount = Mutex(0)

    #expect(!token.isReleased)
    token.onRelease {
      firedCount.withLock { $0 += 1 }
    }
    #expect(firedCount.withLock { $0 } == 0)

    #expect(token.markStarted())
    #expect(token.isReleased)
    #expect(firedCount.withLock { $0 } == 1)

    token.markCompleted()
    #expect(firedCount.withLock { $0 } == 1)
  }

  @Test("queue-exit release fires on cancel-before-start")
  func queueExitReleaseFiresOnCancelBeforeStart() {
    let token = FrameTailJobCancellationToken()
    let firedCount = Mutex(0)

    token.onRelease {
      firedCount.withLock { $0 += 1 }
    }
    #expect(token.cancelBeforeStart())
    #expect(token.isReleased)
    #expect(firedCount.withLock { $0 } == 1)
  }

  @Test("late queue-exit registration fires inline")
  func queueExitReleaseFiresInlineAfterExit() {
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())

    let firedCount = Mutex(0)
    token.onRelease {
      firedCount.withLock { $0 += 1 }
    }
    #expect(firedCount.withLock { $0 } == 1)
  }

  @Test("scheduler pending-frame wait returns when the release trips")
  func schedulerPendingFrameWaitReturnsOnRelease() async {
    // No pending frame and no armed deadline: without the release, this wait
    // parks in the request-waiter registry until a frame request arrives.
    let scheduler = FrameScheduler()
    let token = FrameTailJobCancellationToken()

    let waiter = Task {
      await scheduler.waitForPendingFrame(at: .now(), releasedBy: token)
    }
    #expect(token.markStarted())
    await waiter.value

    #expect(!scheduler.hasPendingFrame(at: .now()))
  }

  @Test("layout stage completes when the signal waiter honors only the release")
  @MainActor
  func layoutStageCompletesWhenSignalWaiterHonorsOnlyTheRelease() async {
    // The signal closure never returns on its own — it parks until the
    // queue-exit release resumes it, exactly like the run loop's
    // pending-frame wait in a quiescent app. Under the pre-entry-14 design
    // this deadlocked: the task group's loser child sat in a cancel-blind
    // continuation, and the group could not exit after `cancelAll()`.
    let renderer = DefaultRenderer()
    let outcome = await renderer.renderAsyncCancellable(
      Text("release-driven"),
      context: .init(identity: testIdentity("FrameTailQueueExitReleaseRoot")),
      proposal: .init(width: 20, height: 3),
      awaitQueuedCancellationSignal: { release in
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          release.onRelease {
            continuation.resume()
          }
        }
      },
      shouldCancelQueued: { false }
    )

    #expect(outcome.artifacts != nil)
    #expect(outcome.tailJobState == .completed)
    #expect(outcome.tailCancelReason == nil)
  }

  @Test("pre-start cancel still wins while the job is queued")
  @MainActor
  func preStartCancelStillWinsWhileQueued() async {
    // The redesign must not weaken the cancel path itself: a signal that
    // fires while the job is queued, with a policy that says cancel, still
    // produces cancelled-before-start — now with no task cancellation.
    let renderer = DefaultRenderer()
    let outcome = await renderer.renderAsyncCancellable(
      Text("cancelled-before-start"),
      context: .init(identity: testIdentity("FrameTailQueueExitCancelRoot")),
      proposal: .init(width: 20, height: 3),
      awaitQueuedCancellationSignal: { _ in },
      shouldCancelQueued: { true }
    )

    #expect(outcome.tailJobState == .cancelledBeforeStart)
    #expect(outcome.artifacts == nil)
  }

  @Test("a pre-start cancel with prepared-graph layout leaves the aborted head untouched")
  @MainActor
  func preStartCancelSparesThePreparedGraphHead() async {
    // The layout task is never cancelled (entry 14). When the cancel decision
    // wins while the job is queued, the caller aborts and discards the
    // prepared head — and the orphaned layout task drains on its own later.
    // Its prepared-graph branch (layout-realized content: GeometryReader)
    // must claim the job before touching the head: without the claim it
    // materialized the discarded head's prepared state and trapped on
    // `materializePreparedState`'s spent-head precondition (the csvui
    // cell-editor crash at 0.8.3).
    let renderer = DefaultRenderer()
    let outcome = await renderer.renderAsyncCancellable(
      GeometryReader { _ in
        Text("prepared-graph")
      },
      context: .init(identity: testIdentity("FrameTailPreparedGraphCancelRoot")),
      proposal: .init(width: 20, height: 3),
      awaitQueuedCancellationSignal: { _ in },
      shouldCancelQueued: { true }
    )
    #expect(outcome.tailJobState == .cancelledBeforeStart)
    #expect(outcome.artifacts == nil)

    // Drain the orphaned layout task: it must bail without touching the
    // aborted head. The yields plus the follow-up render's suspension points
    // guarantee the orphan got its main-actor slots before the test ends.
    for _ in 0..<8 {
      await Task.yield()
    }
    let followUp = await renderer.renderAsyncCancellable(
      GeometryReader { _ in
        Text("after-cancel")
      },
      context: .init(identity: testIdentity("FrameTailPreparedGraphCancelRoot")),
      proposal: .init(width: 20, height: 3),
      awaitQueuedCancellationSignal: { release in
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          release.onRelease {
            continuation.resume()
          }
        }
      },
      shouldCancelQueued: { false }
    )
    #expect(followUp.artifacts != nil)
    #expect(followUp.tailJobState == .completed)
  }
}
