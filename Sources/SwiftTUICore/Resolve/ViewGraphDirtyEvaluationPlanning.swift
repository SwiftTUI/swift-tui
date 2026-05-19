struct ViewGraphDirtyEvaluationPlanningInput {
  var hasRoot: Bool
  var invalidatedIdentities: Set<Identity>
  var graphLocalDirtyIdentities: Set<Identity>
  var nodesByIdentity: [Identity: ViewNode]
  var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
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
      !input.graphLocalDirtyIdentities.isEmpty,
      !input.invalidatedIdentities.isEmpty
    else {
      return nil
    }

    // Every invalidated identity that has a node in the graph must be tracked
    // as graph-local dirty. Identities without graph nodes cannot produce a
    // dirty frontier and are safe to ignore.
    let graphKnownInvalidated = input.invalidatedIdentities.filter {
      input.nodesByIdentity[$0] != nil
    }
    guard graphKnownInvalidated.isSubset(of: input.graphLocalDirtyIdentities) else {
      return nil
    }

    let dirtyFrontier = dirtyFrontierNodes(
      graphLocalDirtyIdentities: input.graphLocalDirtyIdentities,
      nodesByIdentity: input.nodesByIdentity
    )

    guard !dirtyFrontier.isEmpty else {
      return nil
    }

    var targetNodes: [ViewNode] = []
    var targetIdentities: Set<Identity> = []
    for node in dirtyFrontier {
      let target = evaluatorTarget(
        for: node,
        nodesByIdentity: input.nodesByIdentity,
        lifecycleEvaluationOwnersByIdentity: input.lifecycleEvaluationOwnersByIdentity
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
    graphLocalDirtyIdentities: Set<Identity>,
    nodesByIdentity: [Identity: ViewNode]
  ) -> [ViewNode] {
    var frontier: [ViewNode] = []
    var frontierIdentities: Set<Identity> = []

    for identity in graphLocalDirtyIdentities {
      guard let node = nodesByIdentity[identity],
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
        frontierIdentities.insert(node.identity).inserted
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
    nodesByIdentity: [Identity: ViewNode],
    lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
  ) -> ViewNode? {
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []

    while let candidate = current {
      let candidateID = ObjectIdentifier(candidate)
      guard visited.insert(candidateID).inserted else {
        return nil
      }
      if let ownerIdentity = lifecycleEvaluationOwnersByIdentity[candidate.identity],
        let ownerNode = nodesByIdentity[ownerIdentity]
      {
        return ownerNode
      }
      current = candidate.parent
    }

    return nil
  }

  private static func evaluatorTarget(
    for dirtyNode: ViewNode,
    nodesByIdentity: [Identity: ViewNode],
    lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
  ) -> ViewNode? {
    if let lifecycleOwner = lifecycleEvaluationOwnerAncestor(
      of: dirtyNode,
      nodesByIdentity: nodesByIdentity,
      lifecycleEvaluationOwnersByIdentity: lifecycleEvaluationOwnersByIdentity
    ) {
      return lifecycleOwner.hasEvaluator
        ? lifecycleOwner
        : nearestEvaluatorAncestor(of: lifecycleOwner)
    }
    return dirtyNode.hasEvaluator ? dirtyNode : nearestEvaluatorAncestor(of: dirtyNode)
  }
}
