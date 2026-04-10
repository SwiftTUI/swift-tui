package enum ChildDiffOp: Equatable, Sendable {
  case matched(oldIndex: Int, newIndex: Int)
  case moved(oldIndex: Int, newIndex: Int)
  case inserted(newIndex: Int)
  case removed(oldIndex: Int)
}

/// Computes the minimal set of operations needed to turn `old` into `new`,
/// using `CollectionDifference.inferringMoves()` to detect reorders.
///
/// Operations are emitted in a stable but unspecified order.  Consumers
/// that care about ordering must inspect individual cases rather than
/// assuming a particular sequence.  The current downstream consumer
/// (`applyStructuralChildDiff`) only acts on `.removed`, so the ordering
/// is immaterial for teardown correctness.  `.moved` is surfaced as a
/// signal for future animation work; today it carries the same semantics
/// as `.matched` (no subtree teardown, no spawn) and consumers can treat
/// it as a no-op.
package func diffChildren(
  old: [ChildDescriptor],
  new: [ChildDescriptor]
) -> [ChildDiffOp] {
  let difference = new.difference(from: old).inferringMoves()

  var removedOldIndices: Set<Int> = []
  var insertedNewIndices: Set<Int> = []
  var operations: [ChildDiffOp] = []

  for change in difference {
    switch change {
    case .remove(let offset, _, let associatedWith):
      removedOldIndices.insert(offset)
      if let newOffset = associatedWith {
        operations.append(.moved(oldIndex: offset, newIndex: newOffset))
      } else {
        operations.append(.removed(oldIndex: offset))
      }

    case .insert(let offset, _, let associatedWith):
      insertedNewIndices.insert(offset)
      if associatedWith != nil {
        // The move was already recorded on the paired `.remove`; do not
        // double-emit.
        continue
      }
      operations.append(.inserted(newIndex: offset))
    }
  }

  // Pair surviving indices on both sides as `.matched` operations.  Walk
  // `old` and `new` in lockstep, skipping any position touched by a
  // removal (old) or insertion (new).  Every remaining pair is a position
  // that exists in both lists with an identical descriptor.
  var oldIndex = 0
  var newIndex = 0
  while oldIndex < old.count, newIndex < new.count {
    if removedOldIndices.contains(oldIndex) {
      oldIndex += 1
      continue
    }
    if insertedNewIndices.contains(newIndex) {
      newIndex += 1
      continue
    }
    operations.append(.matched(oldIndex: oldIndex, newIndex: newIndex))
    oldIndex += 1
    newIndex += 1
  }

  return operations
}
