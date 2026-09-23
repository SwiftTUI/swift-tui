extension LayoutEngine {
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
    of size: CellSize,
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
    of size: CellSize,
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
    of point: CellPoint,
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
    of size: CellSize,
    for axis: Axis,
    to value: Int
  ) -> CellSize {
    switch axis {
    case .horizontal:
      return CellSize(width: value, height: size.height)
    case .vertical:
      return CellSize(width: size.width, height: value)
    }
  }

  package func isSpacer(_ child: ResolvedNode) -> Bool {
    child.kind == .view("Spacer")
  }

  /// Along-axis Spacers report an intrinsic size even when offered surplus.
  /// Transparent wrappers preserve that response and need the same allocation
  /// override. Stop at constraints or containers that own their own sizing.
  func isStackSpacer(_ node: ResolvedNode, axis: Axis) -> Bool {
    var current = node
    while true {
      if isSpacer(current) {
        return current.drawMetadata.leafStackAxis == nil
          || current.drawMetadata.leafStackAxis == axis
      }
      if isFixedSize(current.layoutMetadata, on: axis) { return false }
      let childIndex: Int
      switch current.layoutBehavior {
      case .padding, .border, .offset:
        childIndex = 0
      case .frame(let width, let height, _):
        guard (axis == .horizontal ? width : height) == nil else { return false }
        childIndex = 0
      case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
        let (minimum, ideal, maximum) =
          axis == .horizontal ? (minW, idealW, maxW) : (minH, idealH, maxH)
        guard !hasFlexibleConstraint(min: minimum, ideal: ideal, max: maximum) else { return false }
        childIndex = 0
      case .decoration(let primaryIndex, _):
        childIndex = primaryIndex
      case .safeAreaIgnoring(let insets, let fillsProposal):
        guard !fillsProposal,
          (axis == .horizontal ? insets.horizontal : insets.vertical) == 0
        else { return false }
        childIndex = 0
      default:
        return false
      }
      guard current.children.indices.contains(childIndex) else { return false }
      current = current.children[childIndex]
    }
  }
}
