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
  /// `plan` is `nil` when there is no plannable dirty work — or when any
  /// frontier node was target-less (`droppedTargetlessNodeCount > 0`), in
  /// which case the caller must escalate to a full root evaluation: a plan
  /// covering less than the queued dirty work would strand the dropped
  /// node's re-evaluation, and `finalizeFrame` wipes the dirty rails
  /// afterwards, losing the work for the session (F160).
  static func targetPlan(
    input: ViewGraphDirtyEvaluationPlanningInput
  ) -> (plan: ViewGraphDirtyEvaluationTargetPlan?, droppedTargetlessNodeCount: Int) {
    guard input.hasRoot,
      !input.graphLocalDirtyNodeIDs.isEmpty
    else {
      return (nil, 0)
    }

    // Live invalidated nodes are unioned into `graphLocalDirtyNodeIDs` by
    // the caller before planning (inter-rail reconciliation, F10 slice 2),
    // so the dirty set is authoritative here.
    let dirtyFrontier = dirtyFrontierNodes(
      graphLocalDirtyNodeIDs: input.graphLocalDirtyNodeIDs,
      nodesByNodeID: input.nodesByNodeID
    )

    guard !dirtyFrontier.isEmpty else {
      return (nil, 0)
    }

    var targetNodes: [ViewNode] = []
    var targetIdentities: Set<Identity> = []
    var droppedTargetlessNodeCount = 0
    for node in dirtyFrontier {
      let target = evaluatorTarget(
        for: node,
        nodesByNodeID: input.nodesByNodeID,
        lifecycleEvaluationOwnersByNodeID: input.lifecycleEvaluationOwnersByNodeID
      )
      guard let target else {
        // No stitchable evaluator anywhere on this node's chain. Count it
        // (recorded unconditionally — the path should be rare and every hit
        // was, pre-F160, a silently lost re-evaluation) and escalate below.
        droppedTargetlessNodeCount += 1
        SoundnessProbeConfiguration.recordPlannerTargetlessFrontierEscalation(
          "dirty frontier node \(node.identity) has no stitchable evaluator target"
        )
        continue
      }
      guard targetIdentities.insert(target.identity).inserted else {
        // Deduplicated onto an already-planned target — covered, not dropped.
        continue
      }
      targetNodes.append(target)
    }

    guard droppedTargetlessNodeCount == 0 else {
      return (nil, droppedTargetlessNodeCount)
    }
    return (ViewGraphDirtyEvaluationTargetPlan(targetNodes: targetNodes), 0)
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
