extension LayoutEngine {
  // MARK: - Inset helpers

  internal func inset(
    _ proposal: ProposedSize,
    by insets: EdgeInsets
  ) -> ProposedSize {
    ProposedSize(
      width: inset(proposal.width, by: insets.horizontal),
      height: inset(proposal.height, by: insets.vertical)
    )
  }

  internal func inset(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      return .unspecified
    case .infinity:
      return .infinity
    case .finite(let value):
      return .finite(max(0, value - amount))
    }
  }

  internal func outset(
    _ proposal: ProposedSize,
    by insets: EdgeInsets
  ) -> ProposedSize {
    ProposedSize(
      width: outset(proposal.width, by: insets.horizontal),
      height: outset(proposal.height, by: insets.vertical)
    )
  }

  internal func outset(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      return .unspecified
    case .infinity:
      return .infinity
    case .finite(let value):
      return .finite(max(0, value + amount))
    }
  }

  internal func measuredDimension(
    _ proposal: ProposedDimension,
    fallback: Int
  ) -> Int {
    switch proposal {
    case .finite(let value):
      max(0, value)
    case .unspecified, .infinity:
      fallback
    }
  }

  internal func safeAreaInsetAdornmentProposal(
    _ parentProposal: ProposedSize,
    edge: Edge
  ) -> ProposedSize {
    switch edge {
    case .top, .bottom:
      return ProposedSize(
        width: parentProposal.width,
        height: .unspecified
      )
    case .leading, .trailing:
      return ProposedSize(
        width: .unspecified,
        height: parentProposal.height
      )
    }
  }

  internal func safeAreaInsetConsumedAmount(
    edge: Edge,
    contentSize: CellSize,
    spacing: Int,
    safeArea: EdgeInsets
  ) -> Int {
    let contentLength =
      switch edge {
      case .top, .bottom:
        contentSize.height
      case .leading, .trailing:
        contentSize.width
      }
    return max(0, contentLength + max(0, spacing) - safeArea.value(for: edge))
  }

  internal func safeAreaInsetConsumedInsets(
    edge: Edge,
    contentSize: CellSize,
    spacing: Int,
    safeArea: EdgeInsets
  ) -> EdgeInsets {
    let consumed = safeAreaInsetConsumedAmount(
      edge: edge,
      contentSize: contentSize,
      spacing: spacing,
      safeArea: safeArea
    )
    switch edge {
    case .top:
      return EdgeInsets(top: consumed)
    case .leading:
      return EdgeInsets(leading: consumed)
    case .bottom:
      return EdgeInsets(bottom: consumed)
    case .trailing:
      return EdgeInsets(trailing: consumed)
    }
  }

  /// The per-side layout insets a border contributes to its owner's frame.
  ///
  /// For `.inset` placements the border occupies the content's own
  /// outermost rows and columns and therefore adds zero layout insets;
  /// the rasterizer will draw border glyphs into those existing cells.
  /// For `.outset` placements the insets reserve
  /// frame cells around the content so no glyph ever lands on the
  /// child's drawable area.  `sides` masks the result so callers can
  /// request borders on a subset of edges (e.g. top only).
  package func borderLayoutInsets(
    set: BorderSet,
    placement: StrokeStyle.Placement,
    sides: Edge.Set
  ) -> EdgeInsets {
    guard placement != .inset else { return EdgeInsets() }
    return EdgeInsets(
      top: sides.contains(.top) ? set.topDisplayWidth : 0,
      leading: sides.contains(.leading) ? set.leftDisplayWidth : 0,
      bottom: sides.contains(.bottom) ? set.bottomDisplayWidth : 0,
      trailing: sides.contains(.trailing) ? set.rightDisplayWidth : 0
    )
  }
}
