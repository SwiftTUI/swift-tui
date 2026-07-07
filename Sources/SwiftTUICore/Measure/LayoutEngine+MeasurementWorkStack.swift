extension LayoutEngine {
  package func measureIterative(
    _ resolved: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    var work: [MeasurementWorkItem] = [.measure(resolved, proposal)]
    var results: [MeasuredNode] = []
    var localMetrics = LayoutWorkMetrics()

    while let item = work.popLast() {
      localMetrics.measurementWorkStackSteps += 1

      switch item {
      case .measure(let node, let proposal):
        scheduleMeasurement(
          of: node,
          proposal: proposal,
          passContext: passContext,
          localMetrics: &localMetrics,
          work: &work,
          results: &results
        )
      case .finishNode(let node, let originalProposal, let effectiveProposal, let childCount):
        let childMeasurements = popMeasurements(from: &results, count: childCount)
        results.append(
          makeMeasuredNode(
            for: node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            childMeasurements: childMeasurements,
            selectedChildIndex: nil,
            passContext: passContext
          )
        )
      case .finishSafeAreaInsetAdornment(
        let node,
        let originalProposal,
        let effectiveProposal,
        let edge,
        let spacing,
        let safeArea
      ):
        let insetMeasurement = popMeasurement(from: &results)
        let consumedInsets = safeAreaInsetConsumedInsets(
          edge: edge,
          contentSize: insetMeasurement.measuredSize,
          spacing: spacing,
          safeArea: safeArea
        )
        let baseProposal = inset(effectiveProposal, by: consumedInsets)
        work.append(
          .finishSafeAreaInset(
            node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            insetMeasurement: insetMeasurement
          )
        )
        work.append(.measure(node.children[0], baseProposal))
      case .finishSafeAreaInset(
        let node,
        let originalProposal,
        let effectiveProposal,
        let insetMeasurement
      ):
        let baseMeasurement = popMeasurement(from: &results)
        results.append(
          makeMeasuredNode(
            for: node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            childMeasurements: [baseMeasurement, insetMeasurement],
            selectedChildIndex: nil,
            passContext: passContext
          )
        )
      case .finishDecorationPrimary(
        let node,
        let originalProposal,
        let effectiveProposal,
        let primaryIndex
      ):
        let primaryMeasurement = popMeasurement(from: &results)
        let decorationProposal = ProposedSize(
          width: .finite(primaryMeasurement.measuredSize.width),
          height: .finite(primaryMeasurement.measuredSize.height)
        )
        let decorationIndices = node.children.indices.filter { $0 != primaryIndex }
        work.append(
          .finishDecoration(
            node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            primaryIndex: primaryIndex,
            primaryMeasurement: primaryMeasurement,
            decorationIndices: Array(decorationIndices)
          )
        )
        for index in decorationIndices.reversed() {
          work.append(.measure(node.children[index], decorationProposal))
        }
      case .finishDecoration(
        let node,
        let originalProposal,
        let effectiveProposal,
        let primaryIndex,
        let primaryMeasurement,
        let decorationIndices
      ):
        let decorationMeasurements = popMeasurements(
          from: &results,
          count: decorationIndices.count
        )
        var measuredChildren = [MeasuredNode?](repeating: nil, count: node.children.count)
        measuredChildren[primaryIndex] = primaryMeasurement
        for (index, measurement) in zip(decorationIndices, decorationMeasurements) {
          measuredChildren[index] = measurement
        }
        results.append(
          makeMeasuredNode(
            for: node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            childMeasurements: measuredChildren.compactMap { $0 },
            selectedChildIndex: nil,
            passContext: passContext
          )
        )
      case .finishViewThatFitsChildren(
        let node,
        let originalProposal,
        let effectiveProposal,
        let axes,
        let childCount
      ):
        let childMeasurements = popMeasurements(from: &results, count: childCount)
        guard !node.children.isEmpty else {
          results.append(
            makeMeasuredNode(
              for: node,
              originalProposal: originalProposal,
              effectiveProposal: effectiveProposal,
              childMeasurements: childMeasurements,
              selectedChildIndex: nil,
              passContext: passContext
            )
          )
          break
        }

        let fitProbe = proposalByRelaxingAxes(effectiveProposal, axes: axes)
        work.append(
          .finishViewThatFitsProbe(
            node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            axes: axes,
            childMeasurements: childMeasurements,
            probeIndex: 0
          )
        )
        work.append(.measure(node.children[0], fitProbe))
      case .finishViewThatFitsProbe(
        let node,
        let originalProposal,
        let effectiveProposal,
        let axes,
        let childMeasurements,
        let probeIndex
      ):
        let idealMeasurement = popMeasurement(from: &results)
        if fits(idealMeasurement.measuredSize, within: effectiveProposal, axes: axes)
          || probeIndex == node.children.indices.last
        {
          results.append(
            makeMeasuredNode(
              for: node,
              originalProposal: originalProposal,
              effectiveProposal: effectiveProposal,
              childMeasurements: childMeasurements,
              selectedChildIndex: probeIndex,
              passContext: passContext
            )
          )
        } else {
          let nextIndex = probeIndex + 1
          let fitProbe = proposalByRelaxingAxes(effectiveProposal, axes: axes)
          work.append(
            .finishViewThatFitsProbe(
              node,
              originalProposal: originalProposal,
              effectiveProposal: effectiveProposal,
              axes: axes,
              childMeasurements: childMeasurements,
              probeIndex: nextIndex
            )
          )
          work.append(.measure(node.children[nextIndex], fitProbe))
        }
      case .finishStackIdeal(
        let node,
        let originalProposal,
        let effectiveProposal,
        let children,
        let axis,
        let spacing,
        let childCount
      ):
        let idealMeasurements = popMeasurements(from: &results, count: childCount)
        scheduleStackAfterIdealMeasurements(
          node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          spacing: spacing,
          idealMeasurements: idealMeasurements,
          passContext: passContext,
          work: &work,
          results: &results
        )
      case .stackAllocateStep(
        let node,
        let originalProposal,
        let effectiveProposal,
        let children,
        let axis,
        var state
      ):
        let measurement = popMeasurement(from: &results)
        let childIndex = state.plan.order[state.position]
        state.measurements[childIndex] = measurement
        // Spacers never absorb their offer themselves — their committed
        // size is the allocated value (forced at completion), so charge
        // that; everyone else charges the actual measured response.
        let consumed =
          isSpacer(children[childIndex])
          ? state.allocatedMainSizes[childIndex]
          : mainDimension(of: measurement.measuredSize, for: axis)
        state.remainingMain = max(0, state.remainingMain - consumed)
        state.position += 1
        continueStackAllocation(
          node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          state: state,
          passContext: passContext,
          work: &work,
          results: &results
        )
      case .finishStackAllocationBatch(
        let node,
        let originalProposal,
        let effectiveProposal,
        let children,
        let axis,
        var state,
        let batchPositions
      ):
        // Batch consumption was charged at scheduling time (unbounded
        // children size exactly to their offer); only merge results.
        let batchMeasurements = popMeasurements(from: &results, count: batchPositions.count)
        for (offset, position) in batchPositions.enumerated() {
          state.measurements[state.plan.order[position]] = batchMeasurements[offset]
        }
        continueStackAllocation(
          node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          state: state,
          passContext: passContext,
          work: &work,
          results: &results
        )
      case .finishStackReconciliation(
        let node,
        let originalProposal,
        let effectiveProposal,
        _,
        _,
        var measurements,
        let replacementIndices
      ):
        let replacements = popMeasurements(from: &results, count: replacementIndices.count)
        for (index, measurement) in zip(replacementIndices, replacements) {
          measurements[index] = measurement
        }
        results.append(
          makeMeasuredNode(
            for: node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            childMeasurements: measurements,
            selectedChildIndex: nil,
            passContext: passContext
          )
        )
      }
    }

    precondition(results.count == 1, "measurement work stack left \(results.count) roots")
    passContext?.updateWorkMetrics {
      $0.measurementWorkStackSteps += localMetrics.measurementWorkStackSteps
      $0.measuredNodesComputed += localMetrics.measuredNodesComputed
      $0.measuredNodesReused += localMetrics.measuredNodesReused
    }
    return results[0]
  }

  private func scheduleMeasurement(
    of node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?,
    localMetrics: inout LayoutWorkMetrics,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    let hasInvalidatedIndexedDescendant = hasInvalidatedIndexedDescendant(
      for: node,
      passContext: passContext
    )

    if let retained = retainedMeasurement(
      for: node,
      proposal: proposal,
      retainedLayout: passContext?.retainedLayout,
      hasInvalidatedIndexedDescendant: hasInvalidatedIndexedDescendant
    ) {
      localMetrics.measuredNodesReused += retained.subtreeNodeCount
      results.append(retained)
      return
    }

    if !hasInvalidatedIndexedDescendant,
      let cached = cache?.lookup(resolved: node, proposal: proposal)
    {
      localMetrics.measuredNodesReused += cached.subtreeNodeCount
      results.append(cached)
      return
    }

    localMetrics.measuredNodesComputed += 1

    if let boundary = node.layoutRealizedContent {
      let measured = MeasuredNode(
        viewNodeID: node.viewNodeID,
        identity: node.identity,
        proposal: proposal,
        measuredSize: boundary.sizingPolicy.measuredSize(for: proposal),
        childMeasurements: [],
        containerAllocationSnapshot: nil
      )
      cache?.store(measured, for: node)
      results.append(measured)
      return
    }

    let effectiveProposal = proposalApplyingFixedSizeMetadata(
      node.layoutMetadata,
      to: proposal
    )

    switch node.layoutBehavior {
    case .intrinsic, .overlay, .offset, .position:
      scheduleChildren(
        node.children,
        proposal: effectiveProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .stack(let axis, let spacing, horizontalAlignment: _, verticalAlignment: _),
      .lazyStack(let axis, let spacing, horizontalAlignment: _, verticalAlignment: _):
      let children = stackChildren(for: node)
      let idealProposal = stackProposal(
        axis: axis,
        main: .unspecified,
        cross: crossDimension(of: effectiveProposal, for: axis)
      )
      scheduleChildren(
        children,
        proposal: idealProposal,
        finish: .finishStackIdeal(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          spacing: spacing,
          childCount: children.count
        ),
        work: &work
      )
    case .padding(let insets):
      let childProposal = inset(effectiveProposal, by: insets)
      scheduleChildren(
        node.children,
        proposal: childProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .safeAreaIgnoring(let insets):
      let childProposal = outset(effectiveProposal, by: insets)
      scheduleChildren(
        node.children,
        proposal: childProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      guard node.children.count >= 2 else {
        scheduleChildren(
          node.children,
          proposal: effectiveProposal,
          finish: .finishNode(
            node,
            originalProposal: proposal,
            effectiveProposal: effectiveProposal,
            childCount: node.children.count
          ),
          work: &work
        )
        return
      }

      let insetProposal = safeAreaInsetAdornmentProposal(
        effectiveProposal,
        edge: edge
      )
      work.append(
        .finishSafeAreaInsetAdornment(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          edge: edge,
          spacing: spacing,
          safeArea: safeArea
        )
      )
      work.append(.measure(node.children[1], insetProposal))
    case .border(let set, let placement, _, _, _, _, let sides):
      let insets = borderLayoutInsets(
        set: set,
        placement: placement,
        sides: sides
      )
      let childProposal = inset(effectiveProposal, by: insets)
      scheduleChildren(
        node.children,
        proposal: childProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .frame(let width, let height, _):
      let childProposal = ProposedSize(
        width: width.map(ProposedDimension.finite) ?? effectiveProposal.width,
        height: height.map(ProposedDimension.finite) ?? effectiveProposal.height
      )
      scheduleChildren(
        node.children,
        proposal: childProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let childProposal = ProposedSize(
        width: flexibleFrameChildProposalDimension(
          proposal: effectiveProposal.width,
          min: minW,
          ideal: idealW,
          max: maxW
        ),
        height: flexibleFrameChildProposalDimension(
          proposal: effectiveProposal.height,
          min: minH,
          ideal: idealH,
          max: maxH
        )
      )
      scheduleChildren(
        node.children,
        proposal: childProposal,
        finish: .finishNode(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          childCount: node.children.count
        ),
        work: &work
      )
    case .decoration(let primaryIndex, _):
      guard node.children.indices.contains(primaryIndex) else {
        scheduleChildren(
          node.children,
          proposal: effectiveProposal,
          finish: .finishNode(
            node,
            originalProposal: proposal,
            effectiveProposal: effectiveProposal,
            childCount: node.children.count
          ),
          work: &work
        )
        return
      }

      work.append(
        .finishDecorationPrimary(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          primaryIndex: primaryIndex
        )
      )
      work.append(.measure(node.children[primaryIndex], effectiveProposal))
    case .viewThatFits(let axes):
      scheduleChildren(
        node.children,
        proposal: effectiveProposal,
        finish: .finishViewThatFitsChildren(
          node,
          originalProposal: proposal,
          effectiveProposal: effectiveProposal,
          axes: axes,
          childCount: node.children.count
        ),
        work: &work
      )
    case .custom(let handle):
      guard
        passContext?.enterCustomLayoutCompatibilityBoundary(
          identity: node.identity,
          debugName: handle.debugName,
          phase: .measurement
        ) ?? true
      else {
        results.append(
          MeasuredNode(
            viewNodeID: node.viewNodeID,
            identity: node.identity,
            proposal: proposal,
            measuredSize: .zero,
            childMeasurements: [],
            containerAllocationSnapshot: nil
          )
        )
        return
      }
      defer {
        passContext?.exitCustomLayoutCompatibilityBoundary()
      }

      let childMeasurements = handle.measureChildren(
        engine: self,
        node: node,
        proposal: effectiveProposal,
        passContext: passContext
      )
      let measured = makeMeasuredNode(
        for: node,
        originalProposal: proposal,
        effectiveProposal: effectiveProposal,
        childMeasurements: childMeasurements,
        selectedChildIndex: nil,
        passContext: passContext
      )
      results.append(measured)
    }
  }

}
