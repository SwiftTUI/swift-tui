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
}
