struct ViewGraphStructuralChildRemoval {
  var oldIndex: Int
  var committedSnapshot: ResolvedNode?
}

struct ViewGraphStructuralRemovalPlan {
  var removedChildren: [ViewGraphStructuralChildRemoval]
}

enum ViewGraphStructuralReconciler {
  /// Produces the structural child removals that need explicit subtree teardown.
  ///
  /// The wider reconciliation flow still owns inserted children and any
  /// matched/moved child that keeps its identity — those are materialized by
  /// the later commit/reuse/install path. Two operation shapes require eager
  /// teardown here:
  ///
  /// - `.removed` children are positionally diffed out of the new list; and
  /// - `.matched`/`.moved` children whose `identity` changed even though the
  ///   descriptor matched. `ChildDescriptor.==` keys on structural path,
  ///   entity, and type — never `identity` — so a departed node that a sibling
  ///   replaced at the same structural slot with a different identity (the
  ///   `replacingIdentity`-with-no-entity family: navigation activations)
  ///   matches its replacement and is never planned for removal. Its
  ///   replacement resolves to a fresh view node, orphaning the old node so
  ///   its action/lifecycle registrations never evict. Planning the old node's
  ///   teardown here lets `applyStructuralChildDiff`'s spare guards (retained
  ///   node ids, visited hosted-detached anchors, entity-routed deferral,
  ///   `sparingVisitedNodes`) keep any genuinely reused or re-adopted node.
  static func removalPlan(
    oldChildDescriptors: [ChildDescriptor],
    currentChildCount: Int,
    committedChildren: [ResolvedNode],
    newChildren: [ResolvedNode]
  ) -> ViewGraphStructuralRemovalPlan {
    let newDescriptors = newChildren.map(ChildDescriptor.init)
    let operations = diffChildren(
      old: oldChildDescriptors,
      new: newDescriptors
    )

    let removedChildren = operations.compactMap { operation -> ViewGraphStructuralChildRemoval? in
      let oldIndex: Int
      switch operation {
      case .removed(let index):
        oldIndex = index
      case .matched(let old, let new), .moved(let old, let new):
        guard oldChildDescriptors.indices.contains(old),
          newDescriptors.indices.contains(new),
          oldChildDescriptors[old].identity != newDescriptors[new].identity
        else {
          return nil
        }
        oldIndex = old
      case .inserted:
        return nil
      }

      guard oldIndex >= 0, oldIndex < currentChildCount else {
        return nil
      }

      return ViewGraphStructuralChildRemoval(
        oldIndex: oldIndex,
        committedSnapshot: committedChildren.indices.contains(oldIndex)
          ? committedChildren[oldIndex]
          : nil
      )
    }

    return ViewGraphStructuralRemovalPlan(removedChildren: removedChildren)
  }
}
