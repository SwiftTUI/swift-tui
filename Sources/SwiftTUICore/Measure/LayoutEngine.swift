package struct LayoutEngine: Sendable {
  package let cache: MeasurementCache?
  /// The grade a `measure` call issues at when the caller does not say
  /// (plan 2026-08-11-004 Stage 1). `.commit` everywhere except engine
  /// values handed into custom-layout author code: the `.custom` measure
  /// case re-brands the engine with its item's grade for the pre-measure
  /// (sticky-downward), and `measureContainer` re-brands with `.probe` so
  /// author `sizeThatFits` probes are probe-grade. A value field rather
  /// than ambient state, so nothing crosses the frame-tail worker offload.
  package var defaultMeasurementGrade: MeasurementGrade = .commit

  /// Creates a layout engine with an optional retained measurement cache.
  package init(cache: MeasurementCache? = nil) {
    self.cache = cache
  }

  /// A copy of this engine whose grade-less `measure` calls issue at
  /// `grade`.
  package func withDefaultMeasurementGrade(
    _ grade: MeasurementGrade
  ) -> LayoutEngine {
    var engine = self
    engine.defaultMeasurementGrade = grade
    return engine
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
    passContext: LayoutPassContext?,
    grade: MeasurementGrade? = nil
  ) -> MeasuredNode {
    measureIterative(
      resolved,
      proposal: proposal,
      passContext: passContext,
      grade: grade ?? defaultMeasurementGrade
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
    return viewDimensions(for: resolved, measured: measured, passContext: passContext)
  }
}
