extension LayoutEngine {
  func makeMeasuredNode(
    for node: ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    childMeasurements: [MeasuredNode],
    selectedChildIndex: Int?,
    issuedProposals: [ChildIssuedProposalRecord]? = nil,
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
    let sizingContext = passContext ?? LayoutPassContext()
    // Built-ins expose their sizing inputs in childMeasurements. Only author
    // hooks can consume extra probes whose products are absent from that array.
    let estimatesBeforeSizing: Int?
    if case .custom = node.layoutBehavior {
      estimatesBeforeSizing = sizingContext.estimatedMeasurementCount
    } else {
      estimatesBeforeSizing = nil
    }
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
        passContext: sizingContext
      )
    }
    let measuredSize = clampedSize(rawSize, proposal: clampingProposal)
    let measured = MeasuredNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      proposal: originalProposal,
      measuredSize: measuredSize,
      childMeasurements: storedChildMeasurements,
      containerAllocationSnapshot: containerAllocationSnapshot(
        for: node,
        measuredSize: measuredSize,
        childMeasurements: childMeasurements,
        selectedChildIndex: selectedChildIndex,
        issuedProposals: issuedProposals,
        passContext: passContext
      ),
      isEstimateDerived: childMeasurements.contains { $0.isEstimateDerived }
        || estimatesBeforeSizing.map { sizingContext.estimatedMeasurementCount != $0 } == true
    )
    cache?.store(measured, for: node)
    return measured
  }

  private func containerAllocationSnapshot(
    for resolved: ResolvedNode,
    measuredSize: CellSize,
    childMeasurements: [MeasuredNode],
    selectedChildIndex: Int?,
    issuedProposals: [ChildIssuedProposalRecord]?,
    passContext: LayoutPassContext?
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

    let childSizes = childMeasurements.map {
      ChildAllocation(identity: $0.identity, size: $0.measuredSize)
    }
    return ContainerAllocationSnapshot(
      childSizes: childSizes,
      selectedChildIndex: chosenChildIndex,
      lazyStack: lazyStackSnapshot,
      hostedCollection: measuredHostedListAllocation(
        for: resolved,
        childSizes: childSizes,
        measuredSize: measuredSize
      )
        ?? measuredHostedTableAllocation(
          for: resolved,
          childSizes: childSizes,
          measuredSize: measuredSize
        ),
      childIssuedProposals: resolvedIssuedProposalRecords(
        for: resolved,
        childMeasurements: childMeasurements,
        explicit: issuedProposals,
        passContext: passContext
      )
    )
  }
}
