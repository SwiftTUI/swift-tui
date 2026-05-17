private enum MeasurementWorkItem {
  case measure(ResolvedNode, ProposedSize)
  case finishNode(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    childCount: Int
  )
  case finishSafeAreaInsetAdornment(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    edge: Edge,
    spacing: Int,
    safeArea: EdgeInsets
  )
  case finishSafeAreaInset(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    insetMeasurement: MeasuredNode
  )
  case finishDecorationPrimary(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    primaryIndex: Int
  )
  case finishDecoration(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    primaryIndex: Int,
    primaryMeasurement: MeasuredNode,
    decorationIndices: [Int]
  )
  case finishViewThatFitsChildren(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axes: AxisSet,
    childCount: Int
  )
  case finishViewThatFitsProbe(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axes: AxisSet,
    childMeasurements: [MeasuredNode],
    probeIndex: Int
  )
  case finishStackIdeal(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    spacing: Int?,
    childCount: Int
  )
  case finishStackAllocated(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    childCount: Int,
    allocatedMainSizes: [Int]
  )
  case finishStackReconciliation(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    measurements: [MeasuredNode],
    replacementIndices: [Int]
  )
}

extension LayoutEngine {
  package func measureIterative(
    _ resolved: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    var work: [MeasurementWorkItem] = [.measure(resolved, proposal)]
    var results: [MeasuredNode] = []

    while let item = work.popLast() {
      passContext?.updateWorkMetrics {
        $0.measurementWorkStackSteps += 1
      }

      switch item {
      case .measure(let node, let proposal):
        scheduleMeasurement(
          of: node,
          proposal: proposal,
          passContext: passContext,
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
      case .finishStackAllocated(
        let node,
        let originalProposal,
        let effectiveProposal,
        let children,
        let axis,
        let childCount,
        let allocatedMainSizes
      ):
        var allocatedMeasurements = popMeasurements(from: &results, count: childCount)
        for index in children.indices where isSpacer(children[index]) {
          allocatedMeasurements[index].measuredSize = settingMainDimension(
            of: allocatedMeasurements[index].measuredSize,
            for: axis,
            to: allocatedMainSizes[index]
          )
        }
        guard case .unspecified = crossDimension(of: effectiveProposal, for: axis) else {
          results.append(
            makeMeasuredNode(
              for: node,
              originalProposal: originalProposal,
              effectiveProposal: effectiveProposal,
              childMeasurements: allocatedMeasurements,
              selectedChildIndex: nil,
              passContext: passContext
            )
          )
          break
        }

        scheduleStackCrossReconciliation(
          node,
          originalProposal: originalProposal,
          effectiveProposal: effectiveProposal,
          children: children,
          axis: axis,
          measurements: allocatedMeasurements,
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
    return results[0]
  }

  private func scheduleMeasurement(
    of node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?,
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
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += retained.subtreeNodeCount
      }
      results.append(retained)
      return
    }

    if !hasInvalidatedIndexedDescendant,
      let cached = cache?.lookup(resolved: node, proposal: proposal)
    {
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += cached.subtreeNodeCount
      }
      results.append(cached)
      return
    }

    passContext?.updateWorkMetrics {
      $0.measuredNodesComputed += 1
    }

    if let boundary = node.layoutDependentContent {
      let measured = MeasuredNode(
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

  private func scheduleStackAfterIdealMeasurements(
    _ node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    spacing: Int?,
    idealMeasurements: [MeasuredNode],
    passContext: LayoutPassContext?,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    guard case .finite(let proposedMain) = mainDimension(of: effectiveProposal, for: axis) else {
      guard case .unspecified = crossDimension(of: effectiveProposal, for: axis) else {
        results.append(
          makeMeasuredNode(
            for: node,
            originalProposal: originalProposal,
            effectiveProposal: effectiveProposal,
            childMeasurements: idealMeasurements,
            selectedChildIndex: nil,
            passContext: passContext
          )
        )
        return
      }

      scheduleStackCrossReconciliation(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        measurements: idealMeasurements,
        passContext: passContext,
        work: &work,
        results: &results
      )
      return
    }

    let spacingBudget = resolvedStackSpacings(
      for: children,
      axis: axis,
      spacingOverride: spacing
    ).reduce(0, +)
    let availableMain = max(0, proposedMain - spacingBudget)
    let idealMainSizes = idealMeasurements.map {
      mainDimension(of: $0.measuredSize, for: axis)
    }
    var allocatedMainSizes = idealMainSizes
    let idealMainTotal = idealMainSizes.reduce(0, +)

    if idealMainTotal < availableMain {
      distributeExtraSpaceToFlexibleChildren(
        children,
        into: &allocatedMainSizes,
        axis: axis,
        extraSpace: availableMain - idealMainTotal
      )
    } else if idealMainTotal > availableMain {
      compressStackChildren(
        children,
        idealMeasurements: idealMeasurements,
        axis: axis,
        allocatedMainSizes: &allocatedMainSizes,
        overflow: idealMainTotal - availableMain
      )
    }

    work.append(
      .finishStackAllocated(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        childCount: children.count,
        allocatedMainSizes: allocatedMainSizes
      )
    )
    for index in children.indices.reversed() {
      let allocatedProposal = stackProposal(
        axis: axis,
        main: .finite(allocatedMainSizes[index]),
        cross: crossDimension(of: effectiveProposal, for: axis)
      )
      work.append(.measure(children[index], allocatedProposal))
    }
  }

  private func scheduleStackCrossReconciliation(
    _ node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    measurements: [MeasuredNode],
    passContext: LayoutPassContext?,
    work: inout [MeasurementWorkItem],
    results: inout [MeasuredNode]
  ) {
    let maxCross = measurements.reduce(0) { partial, measurement in
      max(partial, crossDimension(of: measurement.measuredSize, for: axis))
    }
    guard maxCross > 0 else {
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
      return
    }

    var replacementIndices: [Int] = []
    var replacementProposals: [ProposedSize] = []
    for (index, measurement) in measurements.enumerated() {
      let currentCross = crossDimension(of: measurement.measuredSize, for: axis)
      guard currentCross < maxCross else {
        continue
      }
      guard !stackChildRemeasurementIsNoop(children[index], parentStackAxis: axis) else {
        continue
      }
      replacementIndices.append(index)
      replacementProposals.append(
        stackProposal(
          axis: axis,
          main: .finite(mainDimension(of: measurement.measuredSize, for: axis)),
          cross: .finite(maxCross)
        )
      )
    }

    guard !replacementIndices.isEmpty else {
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
      return
    }

    work.append(
      .finishStackReconciliation(
        node,
        originalProposal: originalProposal,
        effectiveProposal: effectiveProposal,
        children: children,
        axis: axis,
        measurements: measurements,
        replacementIndices: replacementIndices
      )
    )
    for offset in replacementIndices.indices.reversed() {
      work.append(.measure(children[replacementIndices[offset]], replacementProposals[offset]))
    }
  }

  private func makeMeasuredNode(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    childMeasurements: [MeasuredNode],
    selectedChildIndex: Int?,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    let storedChildMeasurements = storedChildMeasurements(
      for: node,
      measuredChildren: childMeasurements
    )
    let clampingProposal = clampingProposal(
      for: node,
      effectiveProposal: effectiveProposal
    )
    let rawSize: CellSize
    if case .viewThatFits = node.layoutBehavior {
      rawSize =
        if let selectedChildIndex,
          childMeasurements.indices.contains(selectedChildIndex)
        {
          childMeasurements[selectedChildIndex].measuredSize
        } else {
          .zero
        }
    } else {
      rawSize = measuredSize(
        for: node,
        childMeasurements: childMeasurements,
        proposal: effectiveProposal,
        passContext: passContext
      )
    }
    let measured = MeasuredNode(
      identity: node.identity,
      proposal: originalProposal,
      measuredSize: clampedSize(rawSize, proposal: clampingProposal),
      childMeasurements: storedChildMeasurements,
      containerAllocationSnapshot: containerAllocationSnapshot(
        for: node,
        childMeasurements: childMeasurements,
        proposal: effectiveProposal,
        selectedChildIndex: selectedChildIndex
      )
    )
    cache?.store(measured, for: node)
    return measured
  }

  private func containerAllocationSnapshot(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
    proposal _: ProposedSize,
    selectedChildIndex: Int?
  ) -> ContainerAllocationSnapshot? {
    guard !childMeasurements.isEmpty else {
      return nil
    }

    let chosenChildIndex: Int?
    switch resolved.layoutBehavior {
    case .viewThatFits:
      chosenChildIndex = selectedChildIndex
    default:
      chosenChildIndex = nil
    }

    let stackChildren = stackChildren(for: resolved)

    let lazyStackSnapshot: LazyStackAllocationSnapshot?
    switch resolved.layoutBehavior {
    case .lazyStack(let axis, let spacing, let horizontalAlignment, let verticalAlignment):
      lazyStackSnapshot = lazyStackAllocationSnapshot(
        for: stackChildren,
        childMeasurements: childMeasurements,
        axis: axis,
        spacingOverride: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment
      )
    default:
      lazyStackSnapshot = nil
    }

    return ContainerAllocationSnapshot(
      childSizes: childMeasurements.map {
        ChildAllocation(identity: $0.identity, size: $0.measuredSize)
      },
      selectedChildIndex: chosenChildIndex,
      lazyStack: lazyStackSnapshot
    )
  }

  private func scheduleChildren(
    _ children: [ResolvedNode],
    proposal: ProposedSize,
    finish: MeasurementWorkItem,
    work: inout [MeasurementWorkItem]
  ) {
    work.append(finish)
    for child in children.reversed() {
      work.append(.measure(child, proposal))
    }
  }

  private func popMeasurement(
    from results: inout [MeasuredNode]
  ) -> MeasuredNode {
    precondition(!results.isEmpty, "measurement work stack expected a child result")
    return results.removeLast()
  }

  private func popMeasurements(
    from results: inout [MeasuredNode],
    count: Int
  ) -> [MeasuredNode] {
    guard count > 0 else {
      return []
    }
    precondition(results.count >= count, "measurement work stack expected \(count) child results")
    let start = results.count - count
    let childMeasurements = Array(results[start..<results.count])
    results.removeLast(count)
    return childMeasurements
  }
}
