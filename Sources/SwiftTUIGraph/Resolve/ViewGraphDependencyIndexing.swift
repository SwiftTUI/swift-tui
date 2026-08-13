@MainActor
package enum ViewGraphDependencyIndex {
  // The whole `DependencyIndex` group crosses as ONE `inout` value: the caller's
  // stored group property is a single class ivar, and passing its four fields as
  // four simultaneous `inout` projections is a dynamic exclusivity violation
  // once the field accessors are `_modify` coroutines (class-property access
  // enforcement is per stored property, not per sub-path).
  package static func reindex(
    viewNodeID: ViewNodeID,
    previous: DependencySet,
    current: DependencySet,
    index: inout ViewGraph.DependencyIndex
  ) {
    remove(
      viewNodeID: viewNodeID,
      dependencies: previous,
      index: &index
    )
    insert(
      viewNodeID: viewNodeID,
      dependencies: current,
      index: &index
    )
  }

  package static func remove(
    viewNodeID: ViewNodeID,
    dependencies: DependencySet,
    index: inout ViewGraph.DependencyIndex
  ) {
    remove(
      viewNodeID,
      from: dependencies.stateSlotReads,
      in: &index.stateSlotDependents
    )
    remove(
      viewNodeID,
      from: dependencies.environmentReads,
      in: &index.environmentDependents
    )
    remove(
      viewNodeID,
      from: dependencies.observableReads,
      in: &index.observableDependents
    )
    remove(
      viewNodeID,
      from: dependencies.environmentWrites,
      in: &index.environmentKeyWriters
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
          isScoped(viewNodeID, within: roots, identityByNodeID: identityByNodeID)
        }
      )
    }
  }

  private static func isScoped(
    _ viewNodeID: ViewNodeID,
    within roots: Set<Identity>,
    identityByNodeID: [ViewNodeID: Identity]
  ) -> Bool {
    guard let identity = identityByNodeID[viewNodeID] else {
      return false
    }
    return roots.contains { root in
      identity == root || identity.isDescendant(of: root)
    }
  }

  private static func insert(
    viewNodeID: ViewNodeID,
    dependencies: DependencySet,
    index: inout ViewGraph.DependencyIndex
  ) {
    insert(
      viewNodeID,
      into: dependencies.stateSlotReads,
      in: &index.stateSlotDependents
    )
    insert(
      viewNodeID,
      into: dependencies.environmentReads,
      in: &index.environmentDependents
    )
    insert(
      viewNodeID,
      into: dependencies.observableReads,
      in: &index.observableDependents
    )
    insert(
      viewNodeID,
      into: dependencies.environmentWrites,
      in: &index.environmentKeyWriters
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
