extension LayoutEngine {
  func scheduleStackAfterIdealMeasurements(
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

    let plan = makeStackAllocationPlan(
      children: children,
      idealMeasurements: idealMeasurements,
      axis: axis
    )
    let state = StackSequentialAllocationState(
      plan: plan,
      position: 0,
      remainingMain: availableMain,
      allocatedMainSizes: idealMeasurements.map {
        mainDimension(of: $0.measuredSize, for: axis)
      },
      measurements: Array(repeating: nil, count: children.count)
    )
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
  }

  func scheduleStackCrossReconciliation(
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
}
