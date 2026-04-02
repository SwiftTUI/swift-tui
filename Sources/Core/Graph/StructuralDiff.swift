package enum ChildDiffOp: Equatable, Sendable {
  case matched(oldIndex: Int, newIndex: Int)
  case inserted(newIndex: Int)
  case removed(oldIndex: Int)
}

package func diffChildren(
  old: [ChildDescriptor],
  new: [ChildDescriptor]
) -> [ChildDiffOp] {
  var oldIndicesByDescriptor: [ChildDescriptor: [Int]] = [:]
  for (index, descriptor) in old.enumerated() {
    oldIndicesByDescriptor[descriptor, default: []].append(index)
  }

  var operations: [ChildDiffOp] = []

  for (newIndex, descriptor) in new.enumerated() {
    if var candidateIndices = oldIndicesByDescriptor[descriptor],
      let oldIndex = candidateIndices.first
    {
      candidateIndices.removeFirst()
      if candidateIndices.isEmpty {
        oldIndicesByDescriptor.removeValue(forKey: descriptor)
      } else {
        oldIndicesByDescriptor[descriptor] = candidateIndices
      }
      operations.append(.matched(oldIndex: oldIndex, newIndex: newIndex))
    } else {
      operations.append(.inserted(newIndex: newIndex))
    }
  }

  let removedIndices = oldIndicesByDescriptor.values
    .flatMap { $0 }
    .sorted()
  for oldIndex in removedIndices {
    operations.append(.removed(oldIndex: oldIndex))
  }

  return operations
}
