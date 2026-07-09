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
  /// The wider reconciliation flow still owns matched, moved, and inserted
  /// children. Those operations are intentionally absent from this plan:
  ///
  /// - matched and moved children are preserved by whichever later
  ///   commit/reuse/install path materializes the parent's new child list;
  /// - inserted children are created by that same materialization path; and
  /// - removed children are the only operations that require eager teardown
  ///   before the parent swaps to its new child list.
  static func removalPlan(
    oldChildDescriptors: [ChildDescriptor],
    currentChildCount: Int,
    committedChildren: [ResolvedNode],
    newChildren: [ResolvedNode]
  ) -> ViewGraphStructuralRemovalPlan {
    let operations = diffChildren(
      old: oldChildDescriptors,
      new: newChildren.map(ChildDescriptor.init)
    )

    let removedChildren = operations.compactMap { operation -> ViewGraphStructuralChildRemoval? in
      guard case .removed(let oldIndex) = operation,
        oldIndex >= 0,
        oldIndex < currentChildCount
      else {
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
