extension LayoutEngine {
  package func clampedSize(
    _ size: CellSize,
    proposal: ProposedSize
  ) -> CellSize {
    CellSize(
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
    case .stack, .lazyStack, .overlay, .padding, .safeAreaIgnoring, .safeAreaInset, .border,
      .offset, .position, .decoration, .viewThatFits, .custom:
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
    _ size: CellSize,
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

}
