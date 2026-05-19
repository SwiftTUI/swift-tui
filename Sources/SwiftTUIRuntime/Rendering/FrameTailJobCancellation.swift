import SwiftTUICore
import Synchronization

package enum FrameTailJobState: String, Sendable {
  case queued
  case started
  case completed
  case cancelledBeforeStart = "cancelled_before_start"
  case droppedCompleted = "dropped_completed"
}

package struct CancellableRenderOutcome {
  package var artifacts: FrameArtifacts?
  package var runtimeIssues: [RuntimeIssue]
  package var renderGeneration: RenderGeneration
  package var newestDesiredGeneration: RenderGeneration?
  package var tailJobState: FrameTailJobState
  package var tailCancelReason: String?
  package var completedFrameDropDecision: CompletedFrameDropDecision?
}

final class FrameTailJobCancellationToken: Sendable {
  private struct State: Sendable {
    var jobState: FrameTailJobState = .queued
    var nextWaiterID: UInt64 = 0
    var waiters: [UInt64: CheckedContinuation<FrameTailJobState, Never>] = [:]
  }

  private let state = Mutex(State())

  var currentState: FrameTailJobState {
    state.withLock(\.jobState)
  }

  func cancelBeforeStart() -> Bool {
    transitionQueued(to: .cancelledBeforeStart)
  }

  func markStarted() -> Bool {
    if transitionQueued(to: .started) {
      return true
    }

    switch currentState {
    case .queued:
      preconditionFailure("Queued frame-tail token failed to transition.")
    case .cancelledBeforeStart:
      return false
    case .started, .completed, .droppedCompleted:
      return true
    }
  }

  func markCompleted() {
    state.withLock { state in
      if state.jobState == .started {
        state.jobState = .completed
      }
    }
  }

  func waitUntilLeavesQueue() async -> FrameTailJobState {
    if currentState != .queued {
      return currentState
    }

    let waiterIDLock = OSAllocatedUnfairLock<UInt64?>(uncheckedState: nil)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: currentState)
          return
        }

        let immediate = state.withLock { state -> FrameTailJobState? in
          guard state.jobState == .queued else {
            return state.jobState
          }
          let waiterID = state.nextWaiterID
          state.nextWaiterID &+= 1
          state.waiters[waiterID] = continuation
          waiterIDLock.withLockUnchecked { $0 = waiterID }
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
          return
        }
        if Task.isCancelled,
          let waiterID = waiterIDLock.withLockUnchecked({ $0 }),
          let continuation = removeWaiter(id: waiterID)
        {
          continuation.resume(returning: currentState)
        }
      }
    } onCancel: {
      guard let waiterID = waiterIDLock.withLockUnchecked({ $0 }),
        let continuation = removeWaiter(id: waiterID)
      else {
        return
      }
      continuation.resume(returning: currentState)
    }
  }

  private func transitionQueued(
    to newState: FrameTailJobState
  ) -> Bool {
    let waiters = state.withLock { state -> [CheckedContinuation<FrameTailJobState, Never>]? in
      guard state.jobState == .queued else {
        return nil
      }
      state.jobState = newState
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: true)
      return waiters
    }

    guard let waiters else {
      return false
    }
    for waiter in waiters {
      waiter.resume(returning: newState)
    }
    return true
  }

  private func removeWaiter(
    id: UInt64
  ) -> CheckedContinuation<FrameTailJobState, Never>? {
    state.withLock { state in
      state.waiters.removeValue(forKey: id)
    }
  }
}
