enum MeasurementWorkItem {
  case measure(ResolvedNode, ProposedSize)
  case measureFresh(ResolvedNode, ProposedSize)
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
  case stackAllocateStep(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    state: StackSequentialAllocationState
  )
  case finishStackAllocationBatch(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    children: [ResolvedNode],
    axis: Axis,
    state: StackSequentialAllocationState,
    batchPositions: Range<Int>
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
