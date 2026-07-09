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

  package static func environmentDependents(
    within roots: Set<Identity>,
    changedKeys: Set<ObjectIdentifier>,
    environmentDependents: [ObjectIdentifier: Set<ViewNodeID>],
    identityByNodeID: [ViewNodeID: Identity]
  ) -> Set<ViewNodeID> {
    // Keep the precise reader `ViewNodeID`s end to end. `Identity` is needed only
    // to scope readers to the changed subtree(s), resolved here via the forward
    // O(1) `identityByNodeID` lookup. The previous implementation mapped each
    // reader to its `Identity` and then tried to recover a node with a
    // nondeterministic `identityByNodeID.first(where:)` reverse scan; under
    // identity aliasing (duplicate `.id`, unstable `ForEach` ids) that scan could
    // return an aliased sibling and silently drop the genuine `@Environment`
    // reader — leaving it on stale environment until a full re-resolve — and also
    // collapsed two aliased readers into one. Filtering the original IDs in place
    // is both O(1) per dependent and aliasing-correct (every genuine reader is
    // kept).
    changedKeys.reduce(into: Set<ViewNodeID>()) { partial, key in
      partial.formUnion(
        (environmentDependents[key] ?? []).filter { viewNodeID in
          guard let identity = identityByNodeID[viewNodeID] else {
            return false
          }
          return roots.contains { root in
            identity == root || identity.isDescendant(of: root)
          }
        }
      )
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
