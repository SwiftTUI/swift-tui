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
  package var environmentSnapshot: EnvironmentSnapshot { committed.environmentSnapshot }
  package var transactionSnapshot: TransactionSnapshot { committed.transactionSnapshot }
  package var layoutBehavior: LayoutBehavior { committed.layoutBehavior }
  package var layoutRealizedContent: LayoutRealizedContentBoundary? {
    committed.layoutRealizedContent
  }
  package var layoutMetadata: LayoutMetadata { committed.layoutMetadata }
  package var drawMetadata: DrawMetadata { committed.drawMetadata }
  package var semanticMetadata: SemanticMetadata { committed.semanticMetadata }
  package var lifecycleMetadata: LifecycleMetadata { committed.lifecycleMetadata }
  package var drawPayload: DrawPayload { committed.drawPayload }
  package var intrinsicSize: CellSize? { committed.intrinsicSize }
  package var indexedChildSource: (any IndexedChildSource)? { committed.indexedChildSource }
  package var preferenceValues: PreferenceValues { committed.preferenceValues }
  package var supportsRetainedReuse: Bool { committed.supportsRetainedReuse }

  /// Derived on demand from `committed.children`.  Previously a stored
  /// field that was set in `apply()`; now computed so it can never drift
  /// from its source.
  package var childDescriptors: [ChildDescriptor] {
    committed.children.map(ChildDescriptor.init)
  }
}
