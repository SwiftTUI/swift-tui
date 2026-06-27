/// Aggregate frame product for inspection, retained reuse, and runtime handoff.
///
/// The individual phase products keep their own ownership contracts. This
/// bundle preserves the current-frame products together with diagnostics,
/// presentation hints, and the commit plan. Retained-layout indexes must use a
/// canonical baseline placed tree rather than an animation-decorated placed tree
/// when storing these artifacts for a later frame.
///
/// Field authority:
///
/// - Canonical phase products: ``resolvedTree``, ``measuredTree``,
///   ``semanticSnapshot``, ``drawTree``, and ``rasterSurface``.
/// - Decorated/baseline-sensitive projection: ``placedTree``. A current frame
///   may commit an animation-decorated placed tree, but retained-layout
///   baselines must store the canonical placement product.
/// - Renderer artifact raster damage: ``presentationDamage``.
/// - Advisory visibility signals: ``drawnIdentities``.
/// - Side-effect plan: ``commitPlan``.
/// - Diagnostics: ``diagnostics``.
package struct FrameArtifacts: Equatable, Sendable {
  package var resolvedTree: ResolvedNode
  package var measuredTree: MeasuredNode
  package var placedTree: PlacedNode
  package var semanticSnapshot: SemanticSnapshot
  package var drawTree: DrawNode
  package var rasterSurface: RasterSurface
  /// Optional artifact-level raster damage for this renderer commit.
  ///
  /// A non-`nil` value must describe the actual changed raster rows/ranges
  /// between the previous renderer-committed `RasterSurface` and this frame's
  /// `rasterSurface`. A `nil` value means the previous renderer surface is
  /// incompatible or unavailable. Runtime presentation code re-derives
  /// host-facing damage from the previous actually presented surface so skipped
  /// async artifacts cannot leak retained renderer history to frontends.
  /// Private retained-layout reuse hints must not be exposed through this field
  /// unless they have been proven to cover the actual renderer-surface diff.
  package var presentationDamage: PresentationDamage?
  /// Identities whose ``DrawNode`` had a non-empty visible rect after
  /// all ancestor clip bounds were applied during rasterization.
  ///
  /// The runtime retains this set as a geometric visibility signal for
  /// diagnostics and scheduling policy. Animation deadlines are no longer
  /// suppressed solely because an identity is absent from this set; the
  /// scheduler may still use it to understand whether an animating subtree
  /// painted any cells in the current frame.
  ///
  /// Note: this is a geometric predicate (would the identity paint any
  /// cells given the current clip), not an observation of incremental
  /// repaint behavior.  An identity that is visible but happens to
  /// fall outside ``presentationDamage`` for this particular frame is
  /// still recorded here.
  package var drawnIdentities: Set<Identity>
  package var commitPlan: CommitPlan
  package var diagnostics: FrameDiagnostics

  /// Creates a full frame artifact bundle.
  package init(
    resolvedTree: ResolvedNode,
    measuredTree: MeasuredNode,
    placedTree: PlacedNode,
    semanticSnapshot: SemanticSnapshot,
    drawTree: DrawNode,
    rasterSurface: RasterSurface,
    commitPlan: CommitPlan,
    diagnostics: FrameDiagnostics = .init()
  ) {
    self.resolvedTree = resolvedTree
    self.measuredTree = measuredTree
    self.placedTree = placedTree
    self.semanticSnapshot = semanticSnapshot
    self.drawTree = drawTree
    self.rasterSurface = rasterSurface
    presentationDamage = nil
    drawnIdentities = []
    self.commitPlan = commitPlan
    self.diagnostics = diagnostics
  }

  package init(
    resolvedTree: ResolvedNode,
    measuredTree: MeasuredNode,
    placedTree: PlacedNode,
    semanticSnapshot: SemanticSnapshot,
    drawTree: DrawNode,
    rasterSurface: RasterSurface,
    presentationDamage: PresentationDamage?,
    drawnIdentities: Set<Identity> = [],
    commitPlan: CommitPlan,
    diagnostics: FrameDiagnostics = .init()
  ) {
    self.resolvedTree = resolvedTree
    self.measuredTree = measuredTree
    self.placedTree = placedTree
    self.semanticSnapshot = semanticSnapshot
    self.drawTree = drawTree
    self.rasterSurface = rasterSurface
    self.presentationDamage = presentationDamage
    self.drawnIdentities = drawnIdentities
    self.commitPlan = commitPlan
    self.diagnostics = diagnostics
  }
}

extension FrameArtifacts {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.resolvedTree == rhs.resolvedTree
      && lhs.measuredTree == rhs.measuredTree
      && lhs.placedTree == rhs.placedTree
      && lhs.semanticSnapshot == rhs.semanticSnapshot
      && lhs.drawTree == rhs.drawTree
      && lhs.rasterSurface == rhs.rasterSurface
      && lhs.presentationDamage == rhs.presentationDamage
      && lhs.drawnIdentities == rhs.drawnIdentities
      && lhs.commitPlan == rhs.commitPlan
  }
}
