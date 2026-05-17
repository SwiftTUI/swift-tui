public struct LayoutEngine: Sendable {
  public let cache: MeasurementCache?

  /// Creates a layout engine with an optional retained measurement cache.
  public init(cache: MeasurementCache? = nil) {
    self.cache = cache
  }

  /// Measures a resolved tree under `proposal`.
  public func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> MeasuredNode {
    measure(
      resolved,
      proposal: proposal,
      passContext: nil
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
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      passContext: nil
    )
  }

  /// Places a measured tree inside `bounds`.
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
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

  public func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> ViewDimensions {
    dimensions(of: resolved, proposal: proposal, passContext: nil)
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
