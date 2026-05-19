@MainActor
package enum ViewGraphDependencyIndex {
  package static func reindex(
    identity: Identity,
    previous: DependencySet,
    current: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<Identity>],
    environmentDependents: inout [ObjectIdentifier: Set<Identity>],
    observableDependents: inout [ObjectIdentifier: Set<Identity>]
  ) {
    remove(
      identity: identity,
      dependencies: previous,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
    insert(
      identity: identity,
      dependencies: current,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents
    )
  }

  package static func remove(
    identity: Identity,
    dependencies: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<Identity>],
    environmentDependents: inout [ObjectIdentifier: Set<Identity>],
    observableDependents: inout [ObjectIdentifier: Set<Identity>]
  ) {
    remove(
      identity,
      from: dependencies.stateSlotReads,
      in: &stateSlotDependents
    )
    remove(
      identity,
      from: dependencies.environmentReads,
      in: &environmentDependents
    )
    remove(
      identity,
      from: dependencies.observableReads,
      in: &observableDependents
    )
  }

  package static func observableDependents(
    triggeredBy identity: Identity,
    nodesByIdentity: [Identity: ViewNode],
    observableDependents: [ObjectIdentifier: Set<Identity>]
  ) -> Set<Identity> {
    guard let dependencies = nodesByIdentity[identity]?.dependencies,
      !dependencies.observableReads.isEmpty
    else {
      return []
    }

    return dependencies.observableReads.reduce(into: Set<Identity>()) { partial, key in
      partial.formUnion(observableDependents[key] ?? [])
    }
  }

  package static func environmentDependents(
    within roots: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>,
    environmentDependents: [ObjectIdentifier: Set<Identity>]
  ) -> Set<Identity> {
    changedKeys.reduce(into: Set<Identity>()) { partial, key in
      let dependents = environmentDependents[key] ?? []
      partial.formUnion(
        dependents.filter { dependent in
          roots.contains { root in
            dependent == root || dependent.isDescendant(of: root)
          }
        }
      )
    }
  }

  private static func insert(
    identity: Identity,
    dependencies: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<Identity>],
    environmentDependents: inout [ObjectIdentifier: Set<Identity>],
    observableDependents: inout [ObjectIdentifier: Set<Identity>]
  ) {
    insert(
      identity,
      into: dependencies.stateSlotReads,
      in: &stateSlotDependents
    )
    insert(
      identity,
      into: dependencies.environmentReads,
      in: &environmentDependents
    )
    insert(
      identity,
      into: dependencies.observableReads,
      in: &observableDependents
    )
  }

  private static func remove<Key: Hashable>(
    _ identity: Identity,
    from keys: Set<Key>,
    in index: inout [Key: Set<Identity>]
  ) {
    for key in keys {
      index[key]?.remove(identity)
      if index[key]?.isEmpty == true {
        index.removeValue(forKey: key)
      }
    }
  }

  private static func insert<Key: Hashable>(
    _ identity: Identity,
    into keys: Set<Key>,
    in index: inout [Key: Set<Identity>]
  ) {
    for key in keys {
      index[key, default: []].insert(identity)
    }
  }
}
