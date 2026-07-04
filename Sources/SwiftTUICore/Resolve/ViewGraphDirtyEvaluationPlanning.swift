struct ViewGraphDirtyEvaluationPlanningInput {
  var hasRoot: Bool
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
      !input.graphLocalDirtyNodeIDs.isEmpty
    else {
      return nil
    }

    // Live invalidated nodes are unioned into `graphLocalDirtyNodeIDs` by
    // the caller before planning (inter-rail reconciliation, F10 slice 2),
    // so the dirty set is authoritative here.
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

  /// The next node on the evaluation-ancestry walk. Capture-hosted island
  /// content has no `parent` link to its host; crossing the seam via
  /// `evaluationHost` keeps the walk going so an island-interior dirty node
  /// hoists to an evaluator whose body re-run re-captures the island by value.
  /// Evaluating such a node in place would strand its output: the host's
  /// committed snapshot stays fresh across the seam (see
  /// `ViewNode.invalidateCachedSnapshots`), so nothing would stitch the new
  /// content into the frame.
  private static func evaluationAncestor(of node: ViewNode) -> ViewNode? {
    node.parent ?? node.evaluationHost
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

      var ancestor = evaluationAncestor(of: node)
      var hasDirtyAncestor = false
      var visitedAncestors: Set<ObjectIdentifier> = []

      while let current = ancestor {
        let currentID = ObjectIdentifier(current)
        guard visitedAncestors.insert(currentID).inserted else {
          break
        }
        // Defer only to ancestors this plan will actually evaluate (queued
        // graph-local dirty work). A node can be dirty without being queued —
        // `invalidate` marks reuse denial without scheduling — and deferring
        // to such an ancestor would strand the descendant's re-evaluation.
        if current.isDirty, graphLocalDirtyNodeIDs.contains(current.viewNodeID) {
          hasDirtyAncestor = true
          break
        }
        ancestor = evaluationAncestor(of: current)
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

  /// The nearest evaluator whose re-evaluation both reaches `node` and
  /// stitches into the committed frame. Walks the full chain to the graph
  /// root; every island-seam crossing (parent-less node reached only via
  /// `evaluationHost`) resets the candidate, because an evaluator below a
  /// seam re-resolves in place without the host re-capturing its output —
  /// the committed snapshot above the seam would stay stale. The surviving
  /// candidate is the first evaluator above the last seam.
  private static func stitchableEvaluatorTarget(
    startingAt node: ViewNode
  ) -> ViewNode? {
    var candidate: ViewNode? = node.hasEvaluator ? node : nil
    var child = node
    var visited: Set<ObjectIdentifier> = []
    while true {
      let crossesSeam = child.parent == nil && child.evaluationHost != nil
      guard let ancestor = evaluationAncestor(of: child) else {
        break
      }
      guard visited.insert(ObjectIdentifier(ancestor)).inserted else {
        break
      }
      if crossesSeam {
        candidate = nil
      }
      if candidate == nil, ancestor.hasEvaluator {
        candidate = ancestor
      }
      child = ancestor
    }
    return candidate
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
      current = evaluationAncestor(of: candidate)
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
      return stitchableEvaluatorTarget(startingAt: lifecycleOwner)
    }
    return stitchableEvaluatorTarget(startingAt: dirtyNode)
  }
}
