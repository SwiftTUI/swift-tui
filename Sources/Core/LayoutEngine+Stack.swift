extension LayoutEngine {
  package func measureStackChildren(
    for resolved: ResolvedNode,
    parentProposal: ProposedSize,
    axis: Axis,
    spacing: Int?,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    measureStackChildren(
      for: stackChildren(for: resolved),
      parentProposal: parentProposal,
      axis: axis,
      spacing: spacing,
      passContext: passContext
    )
  }

  package func measureStackChildren(
    for children: [ResolvedNode],
    parentProposal: ProposedSize,
    axis: Axis,
    spacing: Int?,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    let idealProposal = stackProposal(
      axis: axis,
      main: .unspecified,
      cross: crossDimension(of: parentProposal, for: axis)
    )
    let idealMeasurements = children.map { child in
      measure(child, proposal: idealProposal, passContext: passContext)
    }

    guard case .finite(let proposedMain) = mainDimension(of: parentProposal, for: axis) else {
      // Parent did not propose a finite main dimension (the classic
      // `.fixedSize()` case, or an unconstrained root).  SwiftUI's stack
      // still reconciles the cross axis to the widest child's ideal and
      // then re-measures every child with that cross width.  Without
      // that re-measure, internal `Spacer`s and `frame(maxWidth: .infinity)`
      // inside row children stay collapsed because the children only ever
      // see `.unspecified` on their main axis.
      //
      // We only do this when the parent's cross axis is also unspecified,
      // which is what distinguishes "fixedSize / unconstrained parent"
      // from a parent that has already decided on a cross width.  For the
      // already-finite-cross path we keep the existing (faster) behaviour.
      guard case .unspecified = crossDimension(of: parentProposal, for: axis) else {
        return idealMeasurements
      }
      let maxIdealCross = idealMeasurements.reduce(0) { partial, measurement in
        max(partial, crossDimension(of: measurement.measuredSize, for: axis))
      }
      guard maxIdealCross > 0 else {
        return idealMeasurements
      }
      // Fast path: if every child's ideal cross already matches the
      // max, there is no slack for a flexible child (Spacer,
      // frame(maxWidth:.infinity)) to claim, so re-measuring with a
      // finite cross produces the same result.  Skipping the second
      // pass keeps homogeneous stacks out of the measurement cache's
      // resize-cost path.
      let needsReconciliation = idealMeasurements.contains { measurement in
        crossDimension(of: measurement.measuredSize, for: axis) < maxIdealCross
      }
      guard needsReconciliation else {
        return idealMeasurements
      }
      // Only re-measure children that could actually adapt to the
      // wider cross axis.  Children already at the max have no slack
      // to claim, and rigid text-like leaves (Text, TextFigure,
      // RichText, Rule) return the same measurement at any cross that
      // is wider than their ideal.  Skipping them keeps the clean
      // siblings of an asymmetric stack out of the re-measurement
      // path so their placed tree can still be reused across frames.
      return idealMeasurements.enumerated().map { index, ideal in
        let idealCross = crossDimension(of: ideal.measuredSize, for: axis)
        guard idealCross < maxIdealCross else {
          return ideal
        }
        if stackChildRemeasurementIsNoop(children[index], parentStackAxis: axis) {
          return ideal
        }
        let reProposal = stackProposal(
          axis: axis,
          main: .finite(mainDimension(of: ideal.measuredSize, for: axis)),
          cross: .finite(maxIdealCross)
        )
        return measure(children[index], proposal: reProposal, passContext: passContext)
      }
    }

    let spacingBudget = resolvedStackSpacings(
      for: children,
      axis: axis,
      spacingOverride: spacing
    ).reduce(0, +)
    let availableMain = max(0, proposedMain - spacingBudget)
    let idealMainSizes = idealMeasurements.map { mainDimension(of: $0.measuredSize, for: axis) }
    var allocatedMainSizes = idealMainSizes
    let idealMainTotal = idealMainSizes.reduce(0, +)

    if idealMainTotal < availableMain {
      distributeExtraSpaceToSpacers(
        children,
        into: &allocatedMainSizes,
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

    return children.enumerated().map { index, child in
      var measurement = measure(
        child,
        proposal: stackProposal(
          axis: axis,
          main: .finite(allocatedMainSizes[index]),
          cross: crossDimension(of: parentProposal, for: axis)
        ),
        passContext: passContext
      )
      if isSpacer(child) {
        measurement.measuredSize = settingMainDimension(
          of: measurement.measuredSize,
          for: axis,
          to: allocatedMainSizes[index]
        )
      }
      return measurement
    }
  }

  package func stackChildren(
    for resolved: ResolvedNode
  ) -> [ResolvedNode] {
    guard let source = resolved.indexedChildSource else {
      return resolved.children
    }

    if resolved.children.count == source.count {
      return resolved.children
    }

    return (0..<source.count).map { source.child(at: $0) }
  }

  package func lazyStackAllocationSnapshot(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    axis: Axis,
    spacingOverride: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  ) -> LazyStackAllocationSnapshot {
    let stackSpacings = resolvedStackSpacings(
      for: children,
      axis: axis,
      spacingOverride: spacingOverride
    )
    let crossMetrics = stackCrossMetrics(
      for: children,
      childMeasurements: childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    var childMainOffsets: [Int] = []
    var childMainLengths: [Int] = []
    childMainOffsets.reserveCapacity(childMeasurements.count)
    childMainLengths.reserveCapacity(childMeasurements.count)

    var nextOffset = 0
    for (index, measurement) in childMeasurements.enumerated() {
      let length = mainDimension(of: measurement.measuredSize, for: axis)
      childMainOffsets.append(nextOffset)
      childMainLengths.append(length)
      nextOffset += length
      if index < stackSpacings.count {
        nextOffset += stackSpacings[index]
      }
    }

    return LazyStackAllocationSnapshot(
      axis: axis,
      childMainOffsets: childMainOffsets,
      childMainLengths: childMainLengths,
      contentMainLength: nextOffset,
      crossLeading: crossMetrics.leading,
      crossTrailing: crossMetrics.trailing
    )
  }

  package func lazyStackVisibleChildRange(
    for snapshot: LazyStackAllocationSnapshot,
    viewportContext: LazyStackViewportContext,
    overscan: Int = 1
  ) -> Range<Int>? {
    let axisMatches =
      switch snapshot.axis {
      case .horizontal:
        viewportContext.axes.contains(.horizontal)
      case .vertical:
        viewportContext.axes.contains(.vertical)
      }
    guard axisMatches else {
      return nil
    }

    let viewportLength =
      mainDimension(of: viewportContext.viewportRect.size, for: snapshot.axis)
    guard viewportLength > 0, snapshot.contentMainLength > 0 else {
      return nil
    }

    let contentOffset = max(
      0,
      mainDimension(of: viewportContext.contentOffset, for: snapshot.axis)
    )
    let visibleStart = min(contentOffset, snapshot.contentMainLength)
    let visibleEnd = min(snapshot.contentMainLength, visibleStart + viewportLength)
    guard visibleStart < visibleEnd else {
      return nil
    }

    let childCount = min(snapshot.childMainOffsets.count, snapshot.childMainLengths.count)
    guard childCount > 0 else {
      return nil
    }

    let firstVisible = firstLazyStackChildIndex(
      in: snapshot,
      lowerBoundOfChildEndAfter: visibleStart,
      childCount: childCount
    )
    let lastVisibleExclusive = firstLazyStackChildIndex(
      in: snapshot,
      lowerBoundOfChildStartAtOrAfter: visibleEnd,
      childCount: childCount
    )

    guard firstVisible < lastVisibleExclusive else {
      return nil
    }

    let overscannedLower = max(0, firstVisible - max(0, overscan))
    let overscannedUpper = min(childCount, lastVisibleExclusive + max(0, overscan))
    guard overscannedLower < overscannedUpper else {
      return nil
    }

    return overscannedLower..<overscannedUpper
  }

  private func firstLazyStackChildIndex(
    in snapshot: LazyStackAllocationSnapshot,
    lowerBoundOfChildEndAfter target: Int,
    childCount: Int
  ) -> Int {
    var lower = 0
    var upper = childCount

    while lower < upper {
      let mid = (lower + upper) / 2
      let childEnd = snapshot.childMainOffsets[mid] + snapshot.childMainLengths[mid]
      if childEnd <= target {
        lower = mid + 1
      } else {
        upper = mid
      }
    }

    return lower
  }

  private func firstLazyStackChildIndex(
    in snapshot: LazyStackAllocationSnapshot,
    lowerBoundOfChildStartAtOrAfter target: Int,
    childCount: Int
  ) -> Int {
    var lower = 0
    var upper = childCount

    while lower < upper {
      let mid = (lower + upper) / 2
      if snapshot.childMainOffsets[mid] < target {
        lower = mid + 1
      } else {
        upper = mid
      }
    }

    return lower
  }

  package func resolvedStackSpacings(
    for children: [ResolvedNode],
    axis: Axis,
    spacingOverride: Int?
  ) -> [Int] {
    guard children.count > 1 else {
      return []
    }

    if let spacingOverride {
      return Array(repeating: spacingOverride, count: children.count - 1)
    }

    return children.indices.dropLast().map { index in
      preferredSpacingDistance(
        from: children[index].layoutMetadata.spacing,
        to: children[index + 1].layoutMetadata.spacing,
        axis: axis
      )
    }
  }

  package func preferredSpacingDistance(
    from current: Spacing,
    to next: Spacing,
    axis: Axis
  ) -> Int {
    switch axis {
    case .horizontal:
      return max(current.horizontal ?? 1, next.horizontal ?? 1)
    case .vertical:
      return max(current.vertical ?? 0, next.vertical ?? 0)
    }
  }

  package func stackCrossMetrics(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  ) -> (leading: Int, trailing: Int) {
    let dimensions = zip(children, childMeasurements).map { child, measurement in
      viewDimensions(for: child, measured: measurement)
    }

    switch axis {
    case .horizontal:
      let leading = dimensions.map { max(0, $0[verticalAlignment]) }.max() ?? 0
      let trailing = dimensions.map { max(0, $0.height - $0[verticalAlignment]) }.max() ?? 0
      return (leading, trailing)
    case .vertical:
      let leading = dimensions.map { max(0, $0[horizontalAlignment]) }.max() ?? 0
      let trailing = dimensions.map { max(0, $0.width - $0[horizontalAlignment]) }.max() ?? 0
      return (leading, trailing)
    }
  }

  package func distributeExtraSpaceToSpacers(
    _ children: [ResolvedNode],
    into allocatedMainSizes: inout [Int],
    extraSpace: Int
  ) {
    guard extraSpace > 0 else {
      return
    }

    let spacerIndices = children.indices.filter { isSpacer(children[$0]) }
    guard !spacerIndices.isEmpty else {
      return
    }

    let baseShare = extraSpace / spacerIndices.count
    let remainder = extraSpace % spacerIndices.count

    for index in spacerIndices {
      allocatedMainSizes[index] += baseShare
    }

    guard remainder > 0 else {
      return
    }

    for offset in evenlyDistributedOffsets(
      count: spacerIndices.count,
      picks: remainder
    ) {
      allocatedMainSizes[spacerIndices[offset]] += 1
    }
  }

  package func compressStackChildren(
    _ children: [ResolvedNode],
    idealMeasurements: [MeasuredNode],
    axis: Axis,
    allocatedMainSizes: inout [Int],
    overflow: Int
  ) {
    var remainingOverflow = overflow
    let priorities = Set(children.map { $0.layoutMetadata.layoutPriority }).sorted()

    for priority in priorities where remainingOverflow > 0 {
      let indices = children.indices.filter {
        children[$0].layoutMetadata.layoutPriority == priority
      }
      let minimumSizes = indices.map {
        minimumMainSize(for: children[$0], idealMeasurement: idealMeasurements[$0], axis: axis)
      }
      let compressibles = indices.enumerated().map { offset, index in
        max(0, allocatedMainSizes[index] - minimumSizes[offset])
      }
      let totalCompressible = compressibles.reduce(0, +)

      guard totalCompressible > 0 else {
        continue
      }

      if remainingOverflow >= totalCompressible {
        for (offset, index) in indices.enumerated() {
          allocatedMainSizes[index] = minimumSizes[offset]
        }
        remainingOverflow -= totalCompressible
        continue
      }

      var reductions = Array(repeating: 0, count: indices.count)
      var distributed = 0

      for offset in indices.indices {
        let reduction = (remainingOverflow * compressibles[offset]) / totalCompressible
        reductions[offset] = reduction
        distributed += reduction
      }

      let remainder = remainingOverflow - distributed
      if remainder > 0 {
        let eligibleOffsets = indices.indices.filter {
          reductions[$0] < compressibles[$0]
        }
        for offset in evenlyDistributedOffsets(
          count: eligibleOffsets.count,
          picks: min(remainder, eligibleOffsets.count)
        ) {
          reductions[eligibleOffsets[offset]] += 1
        }
      }

      for (offset, index) in indices.enumerated() {
        allocatedMainSizes[index] = max(
          minimumSizes[offset],
          allocatedMainSizes[index] - reductions[offset]
        )
      }

      remainingOverflow = 0
    }

  }

  package func evenlyDistributedOffsets(
    count: Int,
    picks: Int
  ) -> [Int] {
    guard count > 0, picks > 0 else {
      return []
    }

    return (0..<picks).map { pick in
      ((pick * 2 + 1) * count) / (picks * 2)
    }
  }

  package func minimumMainSize(
    for child: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> Int {
    max(
      minimumMainDimension(
        for: child.layoutMetadata,
        axis: axis
      ) ?? 0,
      derivedMinimumMainSize(
        for: child,
        idealMeasurement: idealMeasurement,
        axis: axis
      )
    )
  }

  package func stackProposal(
    axis: Axis,
    main: ProposedDimension,
    cross: ProposedDimension
  ) -> ProposedSize {
    switch axis {
    case .horizontal:
      return ProposedSize(width: main, height: cross)
    case .vertical:
      return ProposedSize(width: cross, height: main)
    }
  }

  package func mainDimension(
    of proposal: ProposedSize,
    for axis: Axis
  ) -> ProposedDimension {
    switch axis {
    case .horizontal:
      return proposal.width
    case .vertical:
      return proposal.height
    }
  }

  package func crossDimension(
    of proposal: ProposedSize,
    for axis: Axis
  ) -> ProposedDimension {
    switch axis {
    case .horizontal:
      return proposal.height
    case .vertical:
      return proposal.width
    }
  }

  package func mainDimension(
    of size: Size,
    for axis: Axis
  ) -> Int {
    switch axis {
    case .horizontal:
      return size.width
    case .vertical:
      return size.height
    }
  }

  package func crossDimension(
    of size: Size,
    for axis: Axis
  ) -> Int {
    switch axis {
    case .horizontal:
      return size.height
    case .vertical:
      return size.width
    }
  }

  package func mainDimension(
    of point: Point,
    for axis: Axis
  ) -> Int {
    switch axis {
    case .horizontal:
      return point.x
    case .vertical:
      return point.y
    }
  }

  package func settingMainDimension(
    of size: Size,
    for axis: Axis,
    to value: Int
  ) -> Size {
    switch axis {
    case .horizontal:
      return Size(width: value, height: size.height)
    case .vertical:
      return Size(width: size.width, height: value)
    }
  }

  package func isSpacer(_ child: ResolvedNode) -> Bool {
    child.kind == .view("Spacer")
  }

  /// Whether re-measuring `child` with a wider cross dimension (for
  /// the fixedSize stack reconciliation pass in `measureStackChildren`)
  /// is guaranteed to produce the same measurement as its ideal pass.
  ///
  /// The reconciliation pass only helps when the subtree contains
  /// something that can actually claim the extra space along the
  /// parent's cross axis — a `Spacer` inside a stack aligned to that
  /// axis, or a `flexibleFrame` with a `.infinity` max along the
  /// axis.  Subtrees of purely rigid views (Text, nested VStacks of
  /// Texts, etc.) measure identically at any wider cross, so
  /// re-measuring them is pure waste and also evicts their retained
  /// placement cache across frames.
  package func stackChildRemeasurementIsNoop(
    _ child: ResolvedNode,
    parentStackAxis: Axis
  ) -> Bool {
    let crossAxis: Axis =
      switch parentStackAxis {
      case .horizontal: .vertical
      case .vertical: .horizontal
      }
    return !subtreeHasFlexibleContent(child, axis: crossAxis)
  }

  private func subtreeHasFlexibleContent(
    _ node: ResolvedNode,
    axis: Axis
  ) -> Bool {
    switch node.layoutBehavior {
    case .flexibleFrame(let minW, _, let maxW, let minH, _, let maxH, _):
      let (axisMin, axisMax): (ProposedDimension?, ProposedDimension?) =
        switch axis {
        case .horizontal: (minW, maxW)
        case .vertical: (minH, maxH)
        }
      if case .infinity = axisMax {
        return true
      }
      if case .finite(let lo) = axisMin ?? .finite(0),
        case .finite(let hi) = axisMax ?? .finite(0),
        hi > lo
      {
        return true
      }
    case .stack(let stackAxis, _, _, _), .lazyStack(let stackAxis, _, _, _):
      if stackAxis == axis, node.children.contains(where: isSpacer) {
        return true
      }
    default:
      break
    }
    return node.children.contains { subtreeHasFlexibleContent($0, axis: axis) }
  }

  package func isFixedSize(
    _ metadata: LayoutMetadata,
    on axis: Axis
  ) -> Bool {
    switch axis {
    case .horizontal:
      return metadata.fixedSizeHorizontal
    case .vertical:
      return metadata.fixedSizeVertical
    }
  }

  package func minimumMainDimension(
    for metadata: LayoutMetadata,
    axis: Axis
  ) -> Int? {
    switch axis {
    case .horizontal:
      return metadata.minimumWidth
    case .vertical:
      return metadata.minimumHeight
    }
  }

  package func derivedMinimumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> Int {
    if isFixedSize(node.layoutMetadata, on: axis) || isSpacer(node) {
      return mainDimension(of: idealMeasurement.measuredSize, for: axis)
    }

    let stackChildren = stackChildren(for: node)
    let childMinimums = zip(stackChildren, idealMeasurement.childMeasurements).map {
      child, measurement in
      minimumMainSize(
        for: child,
        idealMeasurement: measurement,
        axis: axis
      )
    }

    switch node.layoutBehavior {
    case .intrinsic:
      if case .textFigure(let payload) = node.drawPayload {
        if axis == .horizontal {
          return TextFigureSupport.layoutMetrics(for: payload).minimumWidth
        }
        if !payload.content.isEmpty {
          return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
        }
      }
      if case .text(let content) = node.drawPayload,
        axis == .vertical,
        !content.isEmpty
      {
        return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
      }
      if case .richText(let payload) = node.drawPayload,
        axis == .vertical,
        !payload.visibleText.isEmpty
      {
        return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
      }
      return childMinimums.max() ?? 0
    case .overlay, .offset, .position, .decoration:
      return childMinimums.max() ?? 0
    case .stack(
      axis: let stackAxis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      if stackAxis == axis {
        let spacingBudget = resolvedStackSpacings(
          for: stackChildren,
          axis: axis,
          spacingOverride: spacing
        ).reduce(0, +)
        return childMinimums.reduce(0, +) + spacingBudget
      }
      return childMinimums.max() ?? 0
    case .lazyStack(
      axis: let stackAxis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      if stackAxis == axis {
        let spacingBudget = resolvedStackSpacings(
          for: stackChildren,
          axis: axis,
          spacingOverride: spacing
        ).reduce(0, +)
        return childMinimums.reduce(0, +) + spacingBudget
      }
      return childMinimums.max() ?? 0
    case .padding(let insets):
      let contentMinimum = childMinimums.first ?? 0
      return contentMinimum + (axis == .horizontal ? insets.horizontal : insets.vertical)
    case .frame(let width, let height, _):
      let explicit =
        switch axis {
        case .horizontal:
          width
        case .vertical:
          height
        }
      return max(explicit ?? 0, childMinimums.first ?? 0)
    case .flexibleFrame(let minW, _, _, let minH, _, _, _):
      let minDim: ProposedDimension? =
        switch axis {
        case .horizontal:
          minW
        case .vertical:
          minH
        }
      if case .finite(let v) = minDim {
        return max(v, childMinimums.first ?? 0)
      }
      return childMinimums.first ?? 0
    case .viewThatFits:
      return childMinimums.max() ?? 0
    case .custom:
      return 0
    }
  }
}
