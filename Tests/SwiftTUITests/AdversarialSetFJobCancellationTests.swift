import Synchronization
import Testing

@testable import SwiftTUIRuntime

/// Frame-tail job-state and queued-cancellation-waiter contracts
/// (campaign two F4, setF051–setF060). The token admits only
/// queued→started and queued→cancelled-before-start transitions, completes
/// only a started job, resumes every queued waiter on the one winning
/// transition, and — per `swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md`
/// entry 14 — retires a waiter whose task is cancelled WITHOUT cancelling the
/// job, so a cancelled await point is distinct from a job cancellation
/// (`Sources/SwiftTUIRuntime/Rendering/FrameTailJobCancellation.swift:22-165`).
@Suite("set F queued-job cancellation", .serialized)
struct AdversarialSetFJobCancellationTests {
  @Test("setF051 a wait on a started job returns the started state at once")
  func setF051WaitOnStartedReturnsImmediately() async {
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    #expect(await token.waitUntilLeavesQueue() == .started)
  }

  @Test("setF052 a wait on a cancelled job returns the cancelled state at once")
  func setF052WaitOnCancelledReturnsImmediately() async {
    let token = FrameTailJobCancellationToken()
    #expect(token.cancelBeforeStart())
    #expect(await token.waitUntilLeavesQueue() == .cancelledBeforeStart)
  }

  @Test("setF053 a wait on a completed job returns the completed state at once")
  func setF053WaitOnCompletedReturnsImmediately() async {
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    token.markCompleted()
    #expect(await token.waitUntilLeavesQueue() == .completed)
  }

  @Test("setF054 a queued waiter resumes with started when the worker starts the job")
  func setF054QueuedWaiterResumesOnStart() async {
    let token = FrameTailJobCancellationToken()
    let waiter = Task { await token.waitUntilLeavesQueue() }
    await Task.yield()
    #expect(token.markStarted())
    #expect(await waiter.value == .started)
  }

  @Test("setF055 a queued waiter resumes with cancelled when the job is cancelled before start")
  func setF055QueuedWaiterResumesOnCancel() async {
    let token = FrameTailJobCancellationToken()
    let waiter = Task { await token.waitUntilLeavesQueue() }
    await Task.yield()
    #expect(token.cancelBeforeStart())
    #expect(await waiter.value == .cancelledBeforeStart)
  }

  @Test("setF056 a cancelled waiter returns queued and never cancels the job")
  func setF056CancelledWaiterDoesNotCancelJob() async {
    // Entry 14: the queued-cancellation wait is retired by the token's queue
    // exit, never by task cancellation. A waiter whose own task is cancelled
    // while the job is still queued returns the non-terminal queued state, and
    // the job remains fully cancellable afterward.
    let token = FrameTailJobCancellationToken()
    let waiter = Task {
      unsafe withUnsafeCurrentTask { task in
        unsafe task?.cancel()
      }
      return await token.waitUntilLeavesQueue()
    }
    #expect(await waiter.value == .queued)
    #expect(token.cancelBeforeStart())
    #expect(token.currentState == .cancelledBeforeStart)
  }

  @Test("setF057 a cancelled waiter does not consume another waiter's cancellation")
  func setF057CancelledWaiterDoesNotStealTransition() async {
    let token = FrameTailJobCancellationToken()
    let cancelled = Task { await token.waitUntilLeavesQueue() }
    let survivor = Task { await token.waitUntilLeavesQueue() }
    await Task.yield()
    cancelled.cancel()
    _ = await cancelled.value
    #expect(token.cancelBeforeStart())
    #expect(await survivor.value == .cancelledBeforeStart)
  }

  @Test("setF058 start and cancel-before-start have exactly one sequential winner")
  func setF058OneWinnerBetweenStartAndCancel() {
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    #expect(!token.cancelBeforeStart())
    #expect(token.currentState == .started)
  }

  @Test("setF059 completion advances only a started job and is terminal")
  func setF059CompletionAdvancesOnlyStarted() {
    let queued = FrameTailJobCancellationToken()
    queued.markCompleted()
    #expect(queued.currentState == .queued)

    let cancelled = FrameTailJobCancellationToken()
    #expect(cancelled.cancelBeforeStart())
    cancelled.markCompleted()
    #expect(cancelled.currentState == .cancelledBeforeStart)

    let started = FrameTailJobCancellationToken()
    #expect(started.markStarted())
    started.markCompleted()
    started.markCompleted()
    #expect(started.currentState == .completed)
  }

  @Test("setF060 the release latch fires exactly once at queue exit and inline afterward")
  func setF060ReleaseLatchFiresOnceThenInline() {
    let token = FrameTailJobCancellationToken()
    #expect(!token.isReleased)
    let fired = Mutex(0)
    token.onRelease { fired.withLock { $0 += 1 } }
    #expect(fired.withLock { $0 } == 0)
    #expect(token.markStarted())
    #expect(token.isReleased)
    #expect(fired.withLock { $0 } == 1)
    token.markCompleted()
    #expect(fired.withLock { $0 } == 1)
    token.onRelease { fired.withLock { $0 += 1 } }
    #expect(fired.withLock { $0 } == 2)
  }
}
