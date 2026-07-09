/// A render-side projection of the placed tree carrying only the facts the
/// viewport-lifecycle planner reads: each node's identity, its lifecycle
/// metadata, and its child structure. It replaces the planner's former
/// `PlacedNode` parameter so the graph engine no longer names a render
/// phase-product (`PlacedNode`). Built render-side by
/// ``PlacedNode/viewportVisibilitySummary`` and consumed by
/// ``ViewGraphLifecyclePlanner``; this is the sanctioned render→graph
/// visibility edge (the graph receives an immutable value, never the placed
/// tree itself).
package struct ViewportVisibilitySummary: Sendable {
  package var identity: Identity
  package var lifecycleMetadata: LifecycleMetadata
  package var children: [ViewportVisibilitySummary]

  package init(
    identity: Identity,
    lifecycleMetadata: LifecycleMetadata,
    children: [ViewportVisibilitySummary]
  ) {
    self.identity = identity
    self.lifecycleMetadata = lifecycleMetadata
    self.children = children
  }
}
