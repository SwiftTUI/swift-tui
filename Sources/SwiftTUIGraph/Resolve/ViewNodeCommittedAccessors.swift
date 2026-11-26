@_spi(Testing) import SwiftTUIPrimitives

// MARK: - Committed-field forwarding accessors
//
// These were previously ~14 stored mirror fields on ViewNode that were
// copied one-by-one out of each new ResolvedNode during
// `apply(resolved:children:)`.  The mirror had two
// problems:
//
// - drift risk: nothing enforced that the scattered fields stayed
//   consistent with the most-recently-applied ResolvedNode.
// - boilerplate: every new ResolvedNode field required touching
//   `apply()`, `snapshot()`, and both inits.
//
// Now they're derived from `committed: ResolvedNode`, which is a single
// stored field.  External readers see the same API they did before.
// There are no setters: all writes must go through
// `apply(resolved:children:)`.
extension ViewNode {
  package var resolvedIdentity: Identity { committed.identity }
  package var kind: NodeKind { committed.kind }
  package var lifecycleMetadata: LifecycleMetadata { committed.lifecycleMetadata }
}
