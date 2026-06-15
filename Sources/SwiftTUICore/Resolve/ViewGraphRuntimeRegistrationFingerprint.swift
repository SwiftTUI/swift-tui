@MainActor
package struct RuntimeRegistrationNodeFingerprint: Equatable, Sendable {
  package var viewNodeID: ViewNodeID
  package var subtreeRoot: Identity
  package var resolvedIdentity: Identity
  package var mutationGeneration: UInt64
}

package struct RuntimeRegistrationGraphFingerprint: Equatable, Sendable {
  package var entriesByNodeID: [ViewNodeID: RuntimeRegistrationNodeFingerprint]

  package init(
    entriesByNodeID: [ViewNodeID: RuntimeRegistrationNodeFingerprint] = [:]
  ) {
    self.entriesByNodeID = entriesByNodeID
  }
}

package struct RuntimeRegistrationPublicationDelta: Equatable, Sendable {
  package var removalRoots: [Identity]
  package var restorationRoots: [Identity]

  package var isEmpty: Bool {
    removalRoots.isEmpty && restorationRoots.isEmpty
  }
}

extension RuntimeRegistrationGraphFingerprint {
  package func publicationDelta(
    to current: RuntimeRegistrationGraphFingerprint
  ) -> RuntimeRegistrationPublicationDelta {
    var removalRoots: Set<Identity> = []
    var restorationRoots: Set<Identity> = []
    let allNodeIDs = Set(entriesByNodeID.keys).union(current.entriesByNodeID.keys)

    for nodeID in allNodeIDs {
      let previousEntry = entriesByNodeID[nodeID]
      let currentEntry = current.entriesByNodeID[nodeID]
      guard previousEntry != currentEntry else {
        continue
      }
      if let previousEntry {
        removalRoots.insert(previousEntry.subtreeRoot)
        removalRoots.insert(previousEntry.resolvedIdentity)
      }
      if let currentEntry {
        removalRoots.insert(currentEntry.subtreeRoot)
        removalRoots.insert(currentEntry.resolvedIdentity)
        restorationRoots.insert(currentEntry.subtreeRoot)
        restorationRoots.insert(currentEntry.resolvedIdentity)
      }
    }

    return RuntimeRegistrationPublicationDelta(
      removalRoots: coalescedSubtreeRoots(removalRoots),
      restorationRoots: coalescedSubtreeRoots(restorationRoots)
    )
  }
}

private func coalescedSubtreeRoots(
  _ identities: Set<Identity>
) -> [Identity] {
  let sortedIdentities = identities.sorted { lhs, rhs in
    if lhs.components.count != rhs.components.count {
      return lhs.components.count < rhs.components.count
    }
    return lhs < rhs
  }
  var roots: [Identity] = []
  for identity in sortedIdentities {
    if roots.contains(where: { existing in
      identity == existing || identity.isDescendant(of: existing)
    }) {
      continue
    }
    roots.append(identity)
  }
  return roots
}
