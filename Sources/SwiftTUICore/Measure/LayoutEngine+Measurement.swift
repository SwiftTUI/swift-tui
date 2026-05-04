extension LayoutEngine {
  // MARK: - Measurement dispatch

  internal func measureChildren(
    for resolved: ResolvedNode,
    parentProposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> [MeasuredNode] {
    if resolved.layoutDependentContent != nil {
      return []
    }

    switch resolved.layoutBehavior {
    case .intrinsic, .overlay, .offset, .position:
      return resolved.children.map { child in
        measure(child, proposal: parentProposal, passContext: passContext)
      }
    case .stack(
      let axis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      return measureStackChildren(
        for: stackChildren(for: resolved),
        parentProposal: parentProposal,
        axis: axis,
        spacing: spacing,
        passContext: passContext
      )
    case .lazyStack(
      let axis, let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      return measureStackChildren(
        for: stackChildren(for: resolved),
        parentProposal: parentProposal,
        axis: axis,
        spacing: spacing,
        passContext: passContext
      )
    case .padding(let insets):
      let childProposal = inset(parentProposal, by: insets)
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .safeAreaIgnoring(let insets):
      let childProposal = outset(parentProposal, by: insets)
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      guard resolved.children.count >= 2 else {
        return resolved.children.map { child in
          measure(child, proposal: parentProposal, passContext: passContext)
        }
      }

      let insetProposal = safeAreaInsetAdornmentProposal(
        parentProposal,
        edge: edge
      )
      let insetMeasurement = measure(
        resolved.children[1],
        proposal: insetProposal,
        passContext: passContext
      )
      let consumedInsets = safeAreaInsetConsumedInsets(
        edge: edge,
        contentSize: insetMeasurement.measuredSize,
        spacing: spacing,
        safeArea: safeArea
      )
      let baseProposal = inset(parentProposal, by: consumedInsets)
      let baseMeasurement = measure(
        resolved.children[0],
        proposal: baseProposal,
        passContext: passContext
      )
      return [baseMeasurement, insetMeasurement]
    case .border(let set, let placement, _, _, _, _, let sides):
      let insets = borderLayoutInsets(
        set: set, placement: placement, sides: sides)
      let childProposal = inset(parentProposal, by: insets)
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .frame(let width, let height, _):
      let childProposal = ProposedSize(
        width: width.map(ProposedDimension.finite) ?? parentProposal.width,
        height: height.map(ProposedDimension.finite) ?? parentProposal.height
      )
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let childProposal = ProposedSize(
        width: flexibleFrameChildProposalDimension(
          proposal: parentProposal.width,
          min: minW,
          ideal: idealW,
          max: maxW
        ),
        height: flexibleFrameChildProposalDimension(
          proposal: parentProposal.height,
          min: minH,
          ideal: idealH,
          max: maxH
        )
      )
      return resolved.children.map { child in
        measure(child, proposal: childProposal, passContext: passContext)
      }
    case .decoration(let primaryIndex, _):
      guard resolved.children.indices.contains(primaryIndex) else {
        return resolved.children.map { child in
          measure(child, proposal: parentProposal, passContext: passContext)
        }
      }

      var measuredChildren = [MeasuredNode?](repeating: nil, count: resolved.children.count)
      let primaryMeasurement = measure(
        resolved.children[primaryIndex],
        proposal: parentProposal,
        passContext: passContext
      )
      measuredChildren[primaryIndex] = primaryMeasurement

      let decorationProposal = ProposedSize(
        width: primaryMeasurement.measuredSize.width,
        height: primaryMeasurement.measuredSize.height
      )

      for index in resolved.children.indices where index != primaryIndex {
        measuredChildren[index] = measure(
          resolved.children[index],
          proposal: decorationProposal,
          passContext: passContext
        )
      }

      return measuredChildren.compactMap { $0 }
    case .viewThatFits:
      return resolved.children.map { child in
        measure(child, proposal: parentProposal, passContext: passContext)
      }
    case .custom(let handle):
      return handle.measureChildren(
        engine: self,
        node: resolved,
        proposal: parentProposal,
        passContext: passContext
      )
    }
  }

}
