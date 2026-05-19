import SwiftTUICore
import SwiftTUIViews

enum AnimationCompletionScheduling {
  enum StrandedBatchDecision {
    case ignore
    case schedule(AnimationBatchID, MonotonicInstant)
    case dropCompletion(AnimationBatchID)
  }

  struct PendingDrainPartition {
    var drainedBatchIDs: [AnimationBatchID]
    var nextDeadline: MonotonicInstant?
  }

  static func strandedBatchDecision(
    for transaction: TransactionSnapshot,
    timestamp: MonotonicInstant,
    registeredAnimations: [AnimationBox: Animation],
    batchRefCounts: [AnimationBatchID: Int],
    completionClosures: [AnimationBatchID: @Sendable () -> Void],
    pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant]
  ) -> StrandedBatchDecision {
    // A single withAnimation scope opens at most one completion-bearing batch
    // per resolve pass. If no retained animation claimed it, park the completion
    // until the requested animation duration elapses.
    guard let batchID = transaction.animationBatchID else { return .ignore }
    guard batchRefCounts[batchID] == nil else { return .ignore }
    guard completionClosures[batchID] != nil else { return .ignore }
    guard pendingEmptyBatchCompletions[batchID] == nil else { return .ignore }

    let drainDelay: Duration?
    switch transaction.animationRequest {
    case .animate(let box):
      if let animation = registeredAnimations[box] {
        drainDelay = animation.totalDuration
      } else {
        // A transaction can be built directly with an unregistered box; keep the
        // existing snap/immediate-completion behavior for that defensive path.
        drainDelay = .zero
      }
    case .disabled, .inherit:
      drainDelay = .zero
    }

    guard let drainDelay else {
      // Repeat-forever animations have no logical completion time. Drop the
      // closure so later frames do not keep revisiting it indefinitely.
      return .dropCompletion(batchID)
    }

    return .schedule(batchID, timestamp.advanced(by: drainDelay))
  }

  static func partitionPendingDrains(
    _ pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant],
    at timestamp: MonotonicInstant
  ) -> PendingDrainPartition {
    // Keep the scheduler pointed at the earliest still-pending deadline while
    // returning every completion whose deadline has already elapsed.
    var drainedBatchIDs: [AnimationBatchID] = []
    var nextDeadline: MonotonicInstant?

    for (batchID, deadline) in pendingEmptyBatchCompletions {
      if deadline <= timestamp {
        drainedBatchIDs.append(batchID)
      } else if let currentDeadline = nextDeadline {
        if deadline < currentDeadline {
          nextDeadline = deadline
        }
      } else {
        nextDeadline = deadline
      }
    }

    return PendingDrainPartition(
      drainedBatchIDs: drainedBatchIDs,
      nextDeadline: nextDeadline
    )
  }
}
