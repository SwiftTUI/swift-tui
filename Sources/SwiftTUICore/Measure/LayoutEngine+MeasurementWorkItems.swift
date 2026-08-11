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
  case measure(ResolvedNode, ProposedSize, MeasurementGrade)
  case measureFresh(ResolvedNode, ProposedSize, MeasurementGrade)
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
    safeArea: EdgeInsets,
    grade: MeasurementGrade
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
    primaryIndex: Int,
    grade: MeasurementGrade
  )
  case finishDecoration(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    primaryIndex: Int,
    primaryMeasurement: MeasuredNode,
    decorationIndices: [Int]
  )
  /// The ViewThatFits finish items carry no grade: fit probes are
  /// probe-grade unconditionally (probe composes stickily with anything),
  /// and the committed child measurements were already scheduled at the
  /// container's grade.
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
    childCount: Int,
    grade: MeasurementGrade
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
  /// Hintless ideal-round estimate for indexed lazy stacks (scroll-latency
  /// R4-C): the element-0 probe's finish assembles the stride x count
  /// estimate product instead of scheduling the exhaustive arm.
  case finishLazyStackIdealEstimate(
    ResolvedNode,
    originalProposal: ProposedSize,
    effectiveProposal: ProposedSize,
    axis: Axis,
    spacing: Int,
    count: Int
  )
}
