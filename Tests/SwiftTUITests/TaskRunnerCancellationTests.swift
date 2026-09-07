import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite("Task runner cancellation", .timeLimit(.minutes(1)))
struct TaskRunnerCancellationTests {
  @Test("releasing the owner before actor entry skips the user operation")
  func ownerReleaseBeforeStart() async throws {
    var runner: TaskRunner? = TaskRunner()
    weak let weakRunner = runner
    var didRun = false
    let task = try #require(runner).start(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: Identity(components: ["released-owner"]),
      registration: TaskRegistration(descriptor: TaskDescriptor(id: "work", priority: .medium)) {
        didRun = true
      }
    )

    // Releasing the only owner cannot yield this actor to the queued work.
    runner = nil
    #expect(weakRunner == nil)
    #expect(task.isCancelled)
    await task.value
    #expect(!didRun)
  }

  @Test("releasing the owner cancels an operation suspended in user code")
  func ownerReleaseAfterSuspension() async throws {
    var runner: TaskRunner? = TaskRunner()
    weak let weakRunner = runner
    let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let cancellationObserved = Mutex(false)
    var resumeOperation: CheckedContinuation<Void, Never>?
    var continuedWithoutCancellation = false
    let task = try #require(runner).start(
      viewNodeID: ViewNodeID(rawValue: 1),
      identity: Identity(components: ["suspended-owner"]),
      registration: TaskRegistration(descriptor: TaskDescriptor(id: "work", priority: .medium)) {
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            resumeOperation = continuation
            entered.continuation.yield(())
            entered.continuation.finish()
          }
          continuedWithoutCancellation = !Task.isCancelled
        } onCancel: {
          cancellationObserved.withLock { $0 = true }
        }
      }
    )

    var entry = entered.stream.makeAsyncIterator()
    _ = await entry.next()
    runner = nil
    #expect(weakRunner == nil)
    #expect(task.isCancelled)
    #expect(cancellationObserved.withLock { $0 })

    // Resume independently of cancellation so a missing owner cleanup fails
    // assertions instead of leaving the regression waiting forever.
    resumeOperation?.resume()
    await task.value
    #expect(!continuedWithoutCancellation)
  }

  @Test("cancellation before actor entry skips the user operation", arguments: [false, true])
  func cancellationBeforeStart(cancelAll: Bool) async {
    let runner = TaskRunner()
    let nodeID = ViewNodeID(rawValue: 1)
    var didRun = false
    let task = runner.start(
      viewNodeID: nodeID,
      identity: Identity(components: ["cancelled-owner"]),
      registration: TaskRegistration(descriptor: TaskDescriptor(id: "work", priority: .medium)) {
        didRun = true
      }
    )
    // No suspension has occurred on this actor, so the queued task cannot
    // have entered the closure before its owner retires it.
    if cancelAll {
      runner.cancelAll()
    } else {
      runner.cancel(viewNodeID: nodeID)
    }
    await task.value
    #expect(!didRun)
    #expect(runner.activeTaskCount == 0)
  }

  @Test("a replacement skips retired work and runs the current operation")
  func replacementBeforeStart() async {
    let runner = TaskRunner()
    let nodeID = ViewNodeID(rawValue: 1)
    let identity = Identity(components: ["replaced-owner"])
    var operations: [String] = []
    let retired = runner.start(
      viewNodeID: nodeID,
      identity: identity,
      registration: TaskRegistration(descriptor: TaskDescriptor(id: "work", priority: .medium)) {
        operations.append("retired")
      }
    )
    let current = runner.start(
      viewNodeID: nodeID,
      identity: identity,
      registration: TaskRegistration(descriptor: TaskDescriptor(id: "work", priority: .medium)) {
        operations.append("current")
      }
    )
    await retired.value
    await current.value
    #expect(operations == ["current"])
    #expect(runner.activeTaskCount == 0)
  }
}
