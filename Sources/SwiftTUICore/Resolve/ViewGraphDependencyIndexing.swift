@MainActor
package enum ViewGraphDependencyIndex {
  package static func reindex(
    viewNodeID: ViewNodeID,
    previous: DependencySet,
    current: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<ViewNodeID>],
    environmentDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableKeyPathDependents: inout [ObservableKeyPathKey: Set<ViewNodeID>]
  ) {
    remove(
      viewNodeID: viewNodeID,
      dependencies: previous,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents,
      observableKeyPathDependents: &observableKeyPathDependents
    )
    insert(
      viewNodeID: viewNodeID,
      dependencies: current,
      stateSlotDependents: &stateSlotDependents,
      environmentDependents: &environmentDependents,
      observableDependents: &observableDependents,
      observableKeyPathDependents: &observableKeyPathDependents
    )
  }

  package static func remove(
    viewNodeID: ViewNodeID,
    dependencies: DependencySet,
    stateSlotDependents: inout [StateSlotKey: Set<ViewNodeID>],
    environmentDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableKeyPathDependents: inout [ObservableKeyPathKey: Set<ViewNodeID>]
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
    remove(
      viewNodeID,
      from: dependencies.observableKeyPathReads,
      in: &observableKeyPathDependents
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

  /// Returns the key-path-narrowed co-reader set for an observation change, or
  /// `nil` when narrowing would be unsafe (the caller then falls back to the
  /// object-token union). Narrowing applies only when the firing node is itself
  /// key-path-attributed for each object it read, AND every object co-reader of
  /// that object is key-path-attributed (no object-only reader such as an
  /// `@Environment`-injected observable could be skipped). When it applies, the
  /// result is the co-readers that recorded one of the firing node's key paths —
  /// so a `\.hot` firing dirties `\.hot` peers but not `\.cold`/`\.rare` peers.
  package static func keyPathNarrowedObservableDependents(
    triggeredBy viewNodeID: ViewNodeID,
    nodesByNodeID: [ViewNodeID: ViewNode],
    observableDependents: [ObjectIdentifier: Set<ViewNodeID>],
    observableKeyPathDependents: [ObservableKeyPathKey: Set<ViewNodeID>]
  ) -> Set<ViewNodeID>? {
    guard let dependencies = nodesByNodeID[viewNodeID]?.dependencies,
      !dependencies.observableReads.isEmpty
    else {
      return []
    }

    var result = Set<ViewNodeID>()
    for object in dependencies.observableReads {
      let firingKeyPaths = dependencies.observableKeyPathReads
        .filter { $0.object == object }
        .map(\.keyPath)
      // The firing node must itself name the key path it read on this object;
      // an object-only firing read (e.g. `@Environment`) cannot be narrowed.
      guard !firingKeyPaths.isEmpty else {
        return nil
      }

      var keyPathAttributed = Set<ViewNodeID>()
      for (key, nodes) in observableKeyPathDependents where key.object == object {
        keyPathAttributed.formUnion(nodes)
      }
      // Every object co-reader must be key-path-attributed, else narrowing could
      // skip an object-only reader of the same object.
      guard (observableDependents[object] ?? []).isSubset(of: keyPathAttributed) else {
        return nil
      }

      for keyPath in firingKeyPaths {
        result.formUnion(
          observableKeyPathDependents[
            ObservableKeyPathKey(object: object, keyPath: keyPath)
          ] ?? []
        )
      }
    }
    return result
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
    observableDependents: inout [ObjectIdentifier: Set<ViewNodeID>],
    observableKeyPathDependents: inout [ObservableKeyPathKey: Set<ViewNodeID>]
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
    insert(
      viewNodeID,
      into: dependencies.observableKeyPathReads,
      in: &observableKeyPathDependents
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
