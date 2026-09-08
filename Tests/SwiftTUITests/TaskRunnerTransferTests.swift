@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite("Task runner ownership transfer", .timeLimit(.minutes(1)))
struct TaskRunnerTransferTests {
  private let identity = Identity(components: ["TransferredTask"])
  private let descriptor = TaskDescriptor(id: "load", priority: .medium)
  private let source = ViewNodeID(rawValue: 41)
  private let destination = ViewNodeID(rawValue: 42)

  @Test("deferred commits preserve repeated transfers and cancellation order")
  func carriedTransferSequence() async {
    let runner = TaskRunner()
    let task = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) { await suspendUntilCancelled() })
    let outward = LifecycleCommitEntry(
      viewNodeID: destination, identity: identity,
      operation: .taskTransfer(from: source, descriptor: descriptor))
    let inward = LifecycleCommitEntry(
      viewNodeID: source, identity: identity,
      operation: .taskTransfer(from: destination, descriptor: descriptor))
    var carried: [LifecycleCommitEntry] = []
    LifecycleCarryForward.append([outward], to: &carried)
    LifecycleCarryForward.append([inward], to: &carried)
    LifecycleCarryForward.append([outward], to: &carried)
    #expect(carried == [outward, inward, outward])
    let coordinator = LifecycleCoordinator(taskRunner: runner)
    coordinator.applyCommittedFrame(
      plan: .init(lifecycle: carried), currentLifecycleRegistry: .init(),
      currentTaskRegistry: .init())
    #expect(!task.isCancelled)
    #expect(runner.activeTaskCount == 1)
    coordinator.applyCommittedFrame(
      plan: .init(lifecycle: [
        .init(
          viewNodeID: destination, identity: identity, operation: .taskCancel(descriptor))
      ]),
      currentLifecycleRegistry: .init(), currentTaskRegistry: .init())
    #expect(task.isCancelled)
    await task.value
    #expect(runner.activeTaskCount == 0)
  }

  @Test("task starts and cancels between transfers retain their position")
  func carriedReplacementSequence() {
    let cancel = LifecycleCommitEntry(
      viewNodeID: source, identity: identity, operation: .taskCancel(descriptor))
    let start = LifecycleCommitEntry(
      viewNodeID: source, identity: identity, operation: .taskStart(descriptor))
    let transfer = LifecycleCommitEntry(
      viewNodeID: destination, identity: identity,
      operation: .taskTransfer(from: source, descriptor: descriptor))
    let reverse = LifecycleCommitEntry(
      viewNodeID: source, identity: identity,
      operation: .taskTransfer(from: destination, descriptor: descriptor))
    var carried = [cancel, start, transfer, reverse]
    LifecycleCarryForward.append([cancel, start, transfer], to: &carried)
    #expect(carried == [cancel, start, transfer, reverse, cancel, start, transfer])
  }

  @Test("completion follows repeated transfers without restarting")
  func completionAfterTransfers() async {
    let runner = TaskRunner()
    var starts = 0
    let task = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) { starts += 1 })
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    runner.transfer(from: destination, to: source, identity: identity, matching: descriptor)
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    await task.value
    #expect(starts == 1)
    #expect(!task.isCancelled)
    #expect(runner.activeTaskCount == 0)
  }

  @Test("a suspended task cancels under its new owner")
  func cancellationAfterTransfer() async {
    let runner = TaskRunner()
    let entered = AsyncStream<Void>.makeStream()
    var resume: CheckedContinuation<Void, Never>?
    let task = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {
        await withCheckedContinuation {
          resume = $0
          entered.continuation.yield(())
          entered.continuation.finish()
        }
      })
    for await _ in entered.stream {}
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    runner.cancel(viewNodeID: source)
    #expect(!task.isCancelled)
    runner.cancel(viewNodeID: destination, matching: descriptor)
    #expect(task.isCancelled)
    #expect(runner.activeTaskCount == 0)
    resume?.resume()
    await task.value
  }

  @Test("late completion cannot remove a replacement after transfer")
  func staleCompletionAfterTransfer() async {
    let runner = TaskRunner()
    let entered = AsyncStream<Void>.makeStream()
    var resume: CheckedContinuation<Void, Never>?
    let old = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {
        await withCheckedContinuation {
          resume = $0
          entered.continuation.yield(())
          entered.continuation.finish()
        }
      })
    for await _ in entered.stream {}
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    let replacement = runner.start(
      viewNodeID: destination, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) { await suspendUntilCancelled() })
    #expect(old.isCancelled)
    resume?.resume()
    await old.value
    #expect(runner.activeTaskCount == 1)
    #expect(!replacement.isCancelled)
    runner.cancelAll()
    await replacement.value
  }

  @Test("transfer checks full descriptor and identity and leaves sibling tasks owned")
  func exactOwnershipOnly() async {
    let runner = TaskRunner()
    let sibling = TaskDescriptor(id: "sibling", priority: .medium)
    let first = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {})
    let second = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: sibling) {})
    runner.transfer(
      from: source, to: destination, identity: Identity(components: ["Other"]),
      matching: descriptor)
    runner.transfer(
      from: source, to: destination, identity: identity,
      matching: TaskDescriptor(id: descriptor.id, priority: .high))
    runner.cancel(viewNodeID: destination)
    #expect(!first.isCancelled)
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    runner.cancel(viewNodeID: source)
    #expect(!first.isCancelled)
    #expect(second.isCancelled)
    await first.value
    await second.value
    #expect(runner.activeTaskCount == 0)
  }

  @Test("a destination collision retires the source without overwriting live work")
  func destinationCollision() async {
    let runner = TaskRunner()
    let first = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {})
    let second = runner.start(
      viewNodeID: destination, identity: Identity(components: ["Other"]),
      registration: TaskRegistration(descriptor: descriptor) {})
    runner.transfer(from: source, to: destination, identity: identity, matching: descriptor)
    #expect(first.isCancelled)
    #expect(!second.isCancelled)
    #expect(runner.activeTaskCount == 1)
    await first.value
    await second.value
    #expect(runner.activeTaskCount == 0)
  }

  @Test("a priority replacement cancels the handle occupying the descriptor slot")
  func changedPriorityReplacesHandle() async {
    let runner = TaskRunner()
    let first = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(descriptor: descriptor) {})
    let replacement = runner.start(
      viewNodeID: source, identity: identity,
      registration: TaskRegistration(
        descriptor: TaskDescriptor(id: descriptor.id, priority: .high)
      ) {})
    #expect(first.isCancelled)
    #expect(!replacement.isCancelled)
    await first.value
    await replacement.value
    #expect(runner.activeTaskCount == 0)
  }
}
