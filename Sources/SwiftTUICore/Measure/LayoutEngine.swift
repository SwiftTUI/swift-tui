package struct LayoutEngine: Sendable {
  package let cache: MeasurementCache?

  /// Creates a layout engine with an optional retained measurement cache.
  package init(cache: MeasurementCache? = nil) {
    self.cache = cache
  }

  /// Measures a resolved tree under `proposal`.
  package func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> MeasuredNode {
    let passContext = LayoutPassContext()
    return measure(
      resolved,
      proposal: proposal,
      passContext: passContext
    )
  }

  package func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    measureIterative(
      resolved,
      proposal: proposal,
      passContext: passContext
    )
  }

  /// Places a measured tree at `origin`.
  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero
  ) -> PlacedNode {
    let passContext = LayoutPassContext()
    return place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      passContext: passContext
    )
  }

  /// Places a measured tree inside `bounds`.
  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> PlacedNode {
    let passContext = LayoutPassContext()
    return place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    let effectivePassContext = passContext
    return place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      viewportContext: effectivePassContext?.scrollViewportContext,
      passContext: effectivePassContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    let effectivePassContext = passContext
    return place(
      resolved,
      measured: measured,
      in: bounds,
      viewportContext: effectivePassContext?.scrollViewportContext,
      passContext: effectivePassContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext? = nil
  ) -> PlacedNode {
    placeIterative(
      resolved,
      measured: measured,
      in: bounds,
      viewportContext: viewportContext,
      passContext: passContext
    )
  }

  package func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> ViewDimensions {
    let passContext = LayoutPassContext()
    return dimensions(of: resolved, proposal: proposal, passContext: passContext)
  }

  package func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> ViewDimensions {
    let measured = measure(resolved, proposal: proposal, passContext: passContext)
    return viewDimensions(for: resolved, measured: measured)
  }
}
