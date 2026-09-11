private struct IdentityRestampFrame {
  var node: MeasuredNode
  let resolved: ResolvedNode
  var nextChildIndex: Int
  let descendsIntoChildren: Bool
}

extension MeasuredNode {
  /// Re-stamps a served measured product's identities from the current
  /// resolved tree.
  ///
  /// The measurement-equivalence gate is *structural* by design
  /// (`StructuralEquivalenceLockTests`): a pure `.id` change at the same
  /// structural slot stays layout-reusable, and the graph keeps the node's
  /// `ViewNodeID` across it. Both serve tiers can therefore hand out a product
  /// measured under the previous runtime identities — the measurement cache
  /// when the changed node itself is looked up, and the retained session when
  /// the change sits under a served ancestor whose own identity chain carries
  /// no invalidation. The placed tier already re-syncs its resolved-phase
  /// mirror on exactly this case (`synchronizeRetainedPhaseMetadata`); the
  /// measured product must do the same, or identity-keyed consumers — lazy
  /// scroll-target estimation, viewport-translation equivalence, the layout
  /// shadow oracle that caught both tiers — see a product that lies about
  /// identity.
  ///
  /// The common case (no drift) is proven by a read-only walk and returns
  /// `self` untouched. Shapes whose child measurements are not index-parallel
  /// with the resolved children (windowed lazy products, indexed sources
  /// storing no child measurements) keep their subtree stamps: their reuse is
  /// gated elsewhere and their identities come from element sources, not this
  /// zip.
  package func restampingIdentities(
    from resolved: ResolvedNode,
    recorder: RetainedValidationRecorder? = nil
  ) -> MeasuredNode {
    var work = RetainedValidationWork()
    guard let recorder else {
      // recursion-allowed: one-time dispatch to the generic iterative overload.
      return restampingIdentities(from: resolved, mode: SkipComparisonWork.self, work: &work)
    }
    defer { recorder.merge(work) }
    // recursion-allowed: one-time dispatch to the generic iterative overload.
    return restampingIdentities(from: resolved, mode: CountComparisonWork.self, work: &work)
  }

  private func restampingIdentities<Mode: ComparisonWorkMode>(
    from resolved: ResolvedNode,
    mode: Mode.Type,
    work: inout RetainedValidationWork
  ) -> MeasuredNode {
    // Heap-backed walks; serves run on the frame-tail worker's small stack.
    var drifted = false
    var probe: [(MeasuredNode, ResolvedNode)] = [(self, resolved)]
    while let (cachedNode, currentNode) = probe.popLast() {
      if Mode.isEnabled { work.identityNodesChecked += 1 }
      if cachedNode.identity != currentNode.identity {
        drifted = true
        break
      }
      guard cachedNode.childMeasurements.count == currentNode.children.count else {
        continue
      }
      for index in cachedNode.childMeasurements.indices.reversed() {
        probe.append((cachedNode.childMeasurements[index], currentNode.children[index]))
      }
    }
    guard drifted else {
      return self
    }

    // Iterative post-order rebuild, the `synchronizeRetainedPhaseMetadata`
    // shape: completed children are written back into the parent frame's
    // value-typed `childMeasurements[index]`.

    func makeFrame(_ measured: MeasuredNode, _ resolved: ResolvedNode) -> IdentityRestampFrame {
      if Mode.isEnabled { work.measuredNodesRestamped += 1 }
      var node = measured
      node.identity = resolved.identity
      if var snapshot = node.containerAllocationSnapshot {
        if snapshot.childSizes.count == resolved.children.count {
          for index in snapshot.childSizes.indices {
            if Mode.isEnabled { work.allocationIdentitiesRestamped += 1 }
            snapshot.childSizes[index].identity = resolved.children[index].identity
          }
        }
        if var lazyStack = snapshot.lazyStack,
          lazyStack.childIdentities.count == resolved.children.count
        {
          for index in lazyStack.childIdentities.indices {
            if Mode.isEnabled { work.allocationIdentitiesRestamped += 1 }
            lazyStack.childIdentities[index] = resolved.children[index].identity
          }
          snapshot.lazyStack = lazyStack
        }
        node.containerAllocationSnapshot = snapshot
      }
      return IdentityRestampFrame(
        node: node,
        resolved: resolved,
        nextChildIndex: 0,
        descendsIntoChildren: node.childMeasurements.count == resolved.children.count
      )
    }

    var stack: [IdentityRestampFrame] = [makeFrame(self, resolved)]
    while true {
      let index = stack.count - 1
      if stack[index].descendsIntoChildren,
        stack[index].nextChildIndex < stack[index].node.childMeasurements.count
      {
        let childIndex = stack[index].nextChildIndex
        stack.append(
          makeFrame(
            stack[index].node.childMeasurements[childIndex],
            stack[index].resolved.children[childIndex]
          )
        )
        continue
      }

      let finished = stack.removeLast().node
      guard let parentIndex = stack.indices.last else {
        return finished
      }
      stack[parentIndex].node.childMeasurements[stack[parentIndex].nextChildIndex] = finished
      stack[parentIndex].nextChildIndex += 1
    }
  }
}
