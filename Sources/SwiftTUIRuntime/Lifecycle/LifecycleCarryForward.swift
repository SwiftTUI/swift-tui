import SwiftTUICore

/// Repeated ownership transfers are ordered operations, not duplicate effects.
/// A -> B -> A -> B must retain the final move, along with starts and cancels
/// for that task between moves. Other effects keep the existing dedupe policy.
enum LifecycleCarryForward {
  private struct TaskKey: Hashable {
    var identity: Identity
    var descriptorID: String
  }

  static func append(
    _ entries: [LifecycleCommitEntry],
    to previous: inout [LifecycleCommitEntry],
    deduplicatingWithinEntries: Bool = true
  ) {
    let earlier = previous
    var transferred: Set<TaskKey> = []
    for entry in previous + entries {
      if case .taskTransfer(_, let descriptor) = entry.operation {
        transferred.insert(.init(identity: entry.identity, descriptorID: descriptor.id))
      }
    }
    for entry in entries {
      let keepsOrder: Bool
      switch entry.operation {
      case .taskTransfer:
        keepsOrder = true
      case .taskStart(let descriptor), .taskCancel(let descriptor):
        keepsOrder = transferred.contains(
          .init(
            identity: entry.identity, descriptorID: descriptor.id))
      default:
        keepsOrder = false
      }
      let duplicate =
        deduplicatingWithinEntries
        ? previous.contains(entry) : earlier.contains(entry)
      if keepsOrder || !duplicate {
        previous.append(entry)
      }
    }
  }
}
