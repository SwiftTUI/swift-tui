@MainActor
package enum ViewGraphDependencyIndex {
  package static func reindex(
    viewNodeID: ViewNodeID,
    previous: DependencySet,
    current: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<ViewNodeID>],
    environmentDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>]
  ) {
    remove(
      viewNodeID: viewNodeID,
      dependencies: previous,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
    insert(
      viewNodeID: viewNodeID,
      dependencies: current,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
  }

  package static func remove(
    viewNodeID: ViewNodeID,
    dependencies: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<ViewNodeID>],
    environmentDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>]
  ) {
    remove(
      viewNodeID,
      from: dependencies.stateSlotReads,
      in: &stateSlotDependents
    )
    remove(
      viewNodeID,
      from: dependencies.environmentReads,
      in: &environmentDependents
    )
    remove(
      viewNodeID,
      from: dependencies.observableReads,
      in: &observableDependents
    )
  }

  package static func observableDependents(
    triggeredBy viewNodeID: ViewNodeID,
    nodesByNodeID: [ViewNodeID: ViewNode],
    observableDependents: [ObjectIdentifier: Set<ViewNodeID>]
  ) -> Set<ViewNodeID> {
    guard let dependencies = nodesByNodeID[viewNodeID]?.dependencies,
      !dependencies.observableReads.isEmpty
    else {
      return []
    }

    return dependencies.observableReads.reduce(into: Set<ViewNodeID>()) { partial, key in
      partial.formUnion(observableDependents[key] ?? [])
    }
  }

  package static func environmentDependents(
    within roots: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>,
    environmentDependents: [ObjectIdentifier: Set<ViewNodeID>],
    identityByNodeID: [ViewNodeID: Identity]
  ) -> Set<ViewNodeID> {
    changedKeys.reduce(into: Set<Identity>()) { partial, key in
      let dependents = (environmentDependents[key] ?? [])
        .compactMap { identityByNodeID[$0] }
      partial.formUnion(
        dependents.filter { dependent in
          roots.contains { root in
            dependent == root || dependent.isDescendant(of: root)
          }
        }
      )
    }.reduce(into: Set<ViewNodeID>()) { partial, identity in
      guard
        let viewNodeID = identityByNodeID.first(where: { $0.value == identity })?.key
      else {
        return
      }
      partial.insert(viewNodeID)
    }
  }

  private static func insert(
    viewNodeID: ViewNodeID,
    dependencies: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<ViewNodeID>],
    environmentDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>]
  ) {
    insert(
      viewNodeID,
      into: dependencies.stateSlotReads,
      in: &stateSlotDependents
    )
    insert(
      viewNodeID,
      into: dependencies.environmentReads,
      in: &environmentDependents
    )
    insert(
      viewNodeID,
      into: dependencies.observableReads,
      in: &observableDependents
    )
  }

  private static func remove<Key: Hashable>(
    _ viewNodeID: ViewNodeID,
    from keys: Set<Key>,
    in index: inout [Key: Set<ViewNodeID>]
  ) {
    for key in keys {
      index[key]?.remove(viewNodeID)
      if index[key]?.isEmpty == true {
        index.removeValue(forKey: key)
      }
    }
  }

  private static func insert<Key: Hashable>(
    _ viewNodeID: ViewNodeID,
    into keys: Set<Key>,
    in index: inout [Key: Set<ViewNodeID>]
  ) {
    for key in keys {
      index[key, default: []].insert(viewNodeID)
    }
  }
}
