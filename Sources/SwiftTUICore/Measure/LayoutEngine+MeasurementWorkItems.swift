/// Heap-boxes the iterative work-stack payload as one unit.
///
/// Every case carries at least one ``ResolvedNode`` (currently a large value),
/// and a direct multi-payload enum makes debug builds reserve enough native
/// stack for the largest case at each `measureIterative` invocation. Custom
/// layouts may re-enter measurement through `LayoutSubview.sizeThatFits`; a
/// shallow WindowHostLayout -> author layout -> ScrollView chain could
/// therefore exhaust Dispatch's worker stack while comparing the retained
/// measurement cache. Indirection keeps each work-stack element pointer-sized
/// while preserving the existing heap-backed iterative traversal.
indirect enum MeasurementWorkItem {
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
  /// Windowed lazy stacks measure through the work stack (scroll-latency
  /// Stage 2): the element-0 probe's finish derives the window and schedules
  /// the band, and the band's finish assembles the windowed product. Native
  /// per-row measure re-entry overflowed the frame-tail worker's stack under
  /// nested custom-layout + scroll shapes.
  case finishWindowedLazyStackProbe(
    WindowedLazyStackMeasurementContext,
    probeElement: ResolvedNode
  )
  case finishWindowedLazyStack(
    WindowedLazyStackMeasurementContext,
    window: Range<Int>,
    windowChildren: [ResolvedNode],
    reusedProbeMeasurement: MeasuredNode?,
    scheduledChildCount: Int
  )
}
