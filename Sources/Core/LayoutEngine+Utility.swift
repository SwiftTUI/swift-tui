extension LayoutEngine {
  package func clampedSize(
    _ size: Size,
    proposal: ProposedSize
  ) -> Size {
    Size(
      width: clamp(size.width, to: proposal.width),
      height: clamp(size.height, to: proposal.height)
    )
  }

  package func clamp(_ value: Int, to dimension: ProposedDimension) -> Int {
    switch dimension {
    case .unspecified, .infinity:
      return value
    case .finite(let proposed):
      return min(value, max(0, proposed))
    }
  }

  package func finiteDimension(
    of dimension: ProposedDimension
  ) -> Int? {
    switch dimension {
    case .finite(let value):
      value
    case .unspecified, .infinity:
      nil
    }
  }

  package func proposalApplyingFixedSizeMetadata(
    _ metadata: LayoutMetadata,
    to proposal: ProposedSize
  ) -> ProposedSize {
    ProposedSize(
      width: metadata.fixedSizeHorizontal ? .unspecified : proposal.width,
      height: metadata.fixedSizeVertical ? .unspecified : proposal.height
    )
  }

  package func clampingProposal(
    for resolved: ResolvedNode,
    effectiveProposal: ProposedSize
  ) -> ProposedSize {
    switch resolved.layoutBehavior {
    case .intrinsic:
      if case .image = resolved.drawPayload {
        return .unspecified
      }
      return effectiveProposal
    case .stack, .overlay, .padding, .decoration, .viewThatFits, .custom:
      return .unspecified
    case .frame(let width, let height, _):
      return ProposedSize(
        width: width == nil ? effectiveProposal.width : .unspecified,
        height: height == nil ? effectiveProposal.height : .unspecified
      )
    case .flexibleFrame(let minW, _, let maxW, let minH, _, let maxH, _):
      let allWidthConstrained = minW != nil && maxW != nil
      let allHeightConstrained = minH != nil && maxH != nil
      return ProposedSize(
        width: allWidthConstrained ? .unspecified : effectiveProposal.width,
        height: allHeightConstrained ? .unspecified : effectiveProposal.height
      )
    }
  }

  package func proposalByRelaxingAxes(
    _ proposal: ProposedSize,
    axes: AxisSet
  ) -> ProposedSize {
    ProposedSize(
      width: axes.contains(.horizontal) ? .unspecified : proposal.width,
      height: axes.contains(.vertical) ? .unspecified : proposal.height
    )
  }

  package func fits(
    _ size: Size,
    within proposal: ProposedSize,
    axes: AxisSet
  ) -> Bool {
    if axes.contains(.horizontal), !fits(size.width, within: proposal.width) {
      return false
    }
    if axes.contains(.vertical), !fits(size.height, within: proposal.height) {
      return false
    }
    return true
  }

  package func fits(
    _ value: Int,
    within dimension: ProposedDimension
  ) -> Bool {
    switch dimension {
    case .unspecified, .infinity:
      return true
    case .finite(let limit):
      return value <= limit
    }
  }

  package func selectedChildIndex(
    for resolved: ResolvedNode,
    proposal: ProposedSize,
    axes: AxisSet,
    passContext: LayoutPassContext?
  ) -> Int? {
    guard !resolved.children.isEmpty else {
      return nil
    }

    let fitProbe = proposalByRelaxingAxes(proposal, axes: axes)
    for (index, child) in resolved.children.enumerated() {
      let idealMeasurement = measure(
        child,
        proposal: fitProbe,
        passContext: passContext
      )
      if fits(idealMeasurement.measuredSize, within: proposal, axes: axes) {
        return index
      }
    }

    return resolved.children.indices.last
  }

  package func containerAllocationSnapshot(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> ContainerAllocationSnapshot? {
    guard !childMeasurements.isEmpty else {
      return nil
    }

    let chosenChildIndex: Int?
    switch resolved.layoutBehavior {
    case .viewThatFits(let axes):
      chosenChildIndex = selectedChildIndex(
        for: resolved,
        proposal: proposal,
        axes: axes,
        passContext: passContext
      )
    default:
      chosenChildIndex = nil
    }

    return ContainerAllocationSnapshot(
      childSizes: childMeasurements.map {
        ChildAllocation(identity: $0.identity, size: $0.measuredSize)
      },
      selectedChildIndex: chosenChildIndex
    )
  }
}
