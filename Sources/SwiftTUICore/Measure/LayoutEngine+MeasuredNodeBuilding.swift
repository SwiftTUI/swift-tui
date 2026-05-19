extension LayoutEngine {
  func makeMeasuredNode(
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
        selectedChildIndex: selectedChildIndex
      )
    )
    cache?.store(measured, for: node)
    return measured
  }

  private func containerAllocationSnapshot(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
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
}
