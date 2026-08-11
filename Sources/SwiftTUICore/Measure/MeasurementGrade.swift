/// Whether a measurement request's product may commit — place, draw, and
/// persist as frame geometry — or is a probe whose discard is provable at the
/// site that scheduled it (plan 2026-08-11-004 Stage 1).
///
/// Grade is a property of the REQUEST, never of the product: exact-key cache
/// entries stay grade-blind because the same `(node, proposal)` key yields
/// the same product, so a probe-born entry legally serves a later
/// commit-grade exact lookup. What grade gates is serve LATITUDE — a cache
/// tier may answer a probe-grade request with a broadened (non-exact) serve
/// it must never hand to a commit-grade request. The fail-loud guard for
/// that boundary is `LayoutPassContext.recordProbeLatitudeServe`.
///
/// Probe sites are marked only where supersession is knowable at scheduling
/// time: a stack's ideal round under a finite effective main (the allocation
/// round supersedes it), `ViewThatFits` fit probes (selection only),
/// windowed lazy-stack element-0 stride probes, and author
/// `LayoutSubview.sizeThatFits` calls made inside a custom layout's
/// `sizeThatFits`. Everything else — allocation offers, reconciliation
/// re-measures, placement re-measures — stays commit-grade even when some
/// products are later superseded, because that supersession is
/// data-dependent.
package enum MeasurementGrade: Equatable, Sendable {
  case probe
  case commit

  /// Sticky-downward composition: any request issued while executing a
  /// probe-grade item is probe-grade; a commit-grade container issues at
  /// its site's own grade.
  package func effective(site: MeasurementGrade) -> MeasurementGrade {
    self == .probe ? .probe : site
  }
}
