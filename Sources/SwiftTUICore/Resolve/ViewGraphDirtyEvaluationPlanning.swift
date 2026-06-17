struct ViewGraphDirtyEvaluationPlanningInput {
  var hasRoot: Bool
  var invalidatedNodeIDs: Set<ViewNodeID>
  var graphLocalDirtyNodeIDs: Set<ViewNodeID>
  var nodesByNodeID: [ViewNodeID: ViewNode]
  var lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
}

struct ViewGraphDirtyEvaluationTargetPlan {
  var targetNodes: [ViewNode]
}

@MainActor
enum ViewGraphDirtyEvaluationPlanner {
  static func targetPlan(
    input: ViewGraphDirtyEvaluationPlanningInput
  ) -> ViewGraphDirtyEvaluationTargetPlan? {
    guard input.hasRoot,
      !input.graphLocalDirtyNodeIDs.isEmpty,
      !input.invalidatedNodeIDs.isEmpty
    else {
      return nil
    }

    // Every invalidated node that still exists in the graph must be tracked
    // as graph-local dirty. Missing node ids cannot produce a
    // dirty frontier and are safe to ignore.
    let graphKnownInvalidated = input.invalidatedNodeIDs.filter {
      input.nodesByNodeID[$0] != nil
    }
    guard graphKnownInvalidated.isSubset(of: input.graphLocalDirtyNodeIDs) else {
      return nil
    }

    let dirtyFrontier = dirtyFrontierNodes(
      graphLocalDirtyNodeIDs: input.graphLocalDirtyNodeIDs,
      nodesByNodeID: input.nodesByNodeID
    )

    guard !dirtyFrontier.isEmpty else {
      return nil
    }

    var targetNodes: [ViewNode] = []
    var targetIdentities: Set<Identity> = []
    for node in dirtyFrontier {
      let target = evaluatorTarget(
        for: node,
        nodesByNodeID: input.nodesByNodeID,
        lifecycleEvaluationOwnersByNodeID: input.lifecycleEvaluationOwnersByNodeID
      )
      guard let target,
        targetIdentities.insert(target.identity).inserted
      else {
        continue
      }
      targetNodes.append(target)
    }

    return ViewGraphDirtyEvaluationTargetPlan(targetNodes: targetNodes)
  }

  private static func dirtyFrontierNodes(
    graphLocalDirtyNodeIDs: Set<ViewNodeID>,
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) -> [ViewNode] {
    var frontier: [ViewNode] = []
    var frontierNodeIDs: Set<ViewNodeID> = []

    for viewNodeID in graphLocalDirtyNodeIDs {
      guard let node = nodesByNodeID[viewNodeID],
        node.isDirty
      else {
        continue
      }

      var ancestor = node.parent
      var hasDirtyAncestor = false
      var visitedAncestors: Set<ObjectIdentifier> = []

      while let current = ancestor {
        let currentID = ObjectIdentifier(current)
        guard visitedAncestors.insert(currentID).inserted else {
          break
        }
        if current.isDirty {
          hasDirtyAncestor = true
          break
        }
        ancestor = current.parent
      }

      guard !hasDirtyAncestor,
        frontierNodeIDs.insert(node.viewNodeID).inserted
      else {
        continue
      }

      frontier.append(node)
    }

    return frontier.sorted { lhs, rhs in
      if lhs.identity.components.count == rhs.identity.components.count {
        return lhs.identity < rhs.identity
      }
      return lhs.identity.components.count < rhs.identity.components.count
    }
  }

  private static func nearestEvaluatorAncestor(
    of node: ViewNode
  ) -> ViewNode? {
    var current = node.parent
    var visited: Set<ObjectIdentifier> = []
    while let ancestor = current {
      let id = ObjectIdentifier(ancestor)
      guard visited.insert(id).inserted else {
        return nil
      }
      if ancestor.hasEvaluator {
        return ancestor
      }
      current = ancestor.parent
    }
    return nil
  }

  private static func lifecycleEvaluationOwnerAncestor(
    of node: ViewNode,
    nodesByNodeID: [ViewNodeID: ViewNode],
    lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
  ) -> ViewNode? {
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []

    while let candidate = current {
      let candidateID = ObjectIdentifier(candidate)
      guard visited.insert(candidateID).inserted else {
        return nil
      }
      if let ownerNodeID = lifecycleEvaluationOwnersByNodeID[candidate.viewNodeID],
        let ownerNode = nodesByNodeID[ownerNodeID]
      {
        return ownerNode
      }
      current = candidate.parent
    }

    return nil
  }

  private static func evaluatorTarget(
    for dirtyNode: ViewNode,
    nodesByNodeID: [ViewNodeID: ViewNode],
    lifecycleEvaluationOwnersByNodeID: [ViewNodeID: ViewNodeID]
  ) -> ViewNode? {
    if let lifecycleOwner = lifecycleEvaluationOwnerAncestor(
      of: dirtyNode,
      nodesByNodeID: nodesByNodeID,
      lifecycleEvaluationOwnersByNodeID: lifecycleEvaluationOwnersByNodeID
    ) {
      return lifecycleOwner.hasEvaluator
        ? lifecycleOwner
        : nearestEvaluatorAncestor(of: lifecycleOwner)
    }
    return dirtyNode.hasEvaluator ? dirtyNode : nearestEvaluatorAncestor(of: dirtyNode)
  }
}
