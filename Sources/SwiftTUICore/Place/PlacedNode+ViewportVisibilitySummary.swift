extension PlacedNode {
  /// Projects the placed subtree to the identity / lifecycle-metadata facts the
  /// viewport-lifecycle planner consumes, dropping all geometry. This is the
  /// render→graph seam: the graph engine receives this value instead of naming
  /// `PlacedNode`. See ``ViewportVisibilitySummary``.
  package var viewportVisibilitySummary: ViewportVisibilitySummary {
    ViewportVisibilitySummary(
      identity: identity,
      lifecycleMetadata: lifecycleMetadata,
      children: children.map(\.viewportVisibilitySummary)
    )
  }
}
