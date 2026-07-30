@_spi(Testing) import SwiftTUIPrimitives

extension ResolvedNode {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    // Node-hosted collections preserve authored row subtrees instead of
    // collapsing them into draw payloads. Those trees can exceed the frame-tail
    // worker's deliberately-small stack, and recursive equivalence previously
    // overflowed it before the cache could reject or accept the entry. Keep the
    // exact same field contract while moving the traversal storage to the heap.
    var pending: [(Self, Self)] = [(self, other)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.structuralPath == rhs.structuralPath,
        lhs.kind == rhs.kind,
        Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator),
        lhs.environmentSnapshot == rhs.environmentSnapshot,
        lhs.layoutBehavior.isEquivalentForMeasurement(to: rhs.layoutBehavior),
        lhs.layoutMetadata == rhs.layoutMetadata,
        // Alignment-guide closures are invisible to `layoutMetadata ==`; a
        // cached measured node would carry the previous capture's guides into
        // placement, so guide-carrying nodes never reuse cached measurements.
        !lhs.layoutMetadata.hasExplicitAlignmentGuides,
        lhs.layoutRealizedContent?.equivalenceSignature
          == rhs.layoutRealizedContent?.equivalenceSignature,
        lhs.drawPayload.isEquivalentForMeasurement(to: rhs.drawPayload),
        lhs.intrinsicSize == rhs.intrinsicSize,
        lhs.indexedChildSource?.measurementSignature
          == rhs.indexedChildSource?.measurementSignature,
        lhs.children.count == rhs.children.count
      else {
        return false
      }
      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }

  /// Stricter equivalence check used by the retained layout placement cache.
  /// Like `isEquivalentForMeasurement` but uses full draw payload equality
  /// instead of the relaxed measurement comparison, ensuring that visual-only
  /// changes (such as a shape's stroke style changing from thick to thin) are
  /// detected even when they don't affect measurement.
  package func isEquivalentForPlacement(
    to other: Self
  ) -> Bool {
    // Iterative for the same reason `isEquivalentForMeasurement` is (45ffdc44):
    // node-hosted collection rows and deep custom-layout chains reach this
    // walker on the frame-tail worker's small Dispatch stack. Same field
    // contract, heap-backed traversal.
    var pending: [(Self, Self)] = [(self, other)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.structuralPath == rhs.structuralPath,
        lhs.kind == rhs.kind,
        Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator),
        lhs.environmentSnapshot == rhs.environmentSnapshot,
        lhs.layoutBehavior.isEquivalentForPlacement(to: rhs.layoutBehavior),
        lhs.layoutMetadata == rhs.layoutMetadata,
        // Alignment-guide closures are invisible to `layoutMetadata ==`; a
        // guide-carrying node can never prove its placement inputs unchanged.
        !lhs.layoutMetadata.hasExplicitAlignmentGuides,
        lhs.layoutRealizedContent?.equivalenceSignature
          == rhs.layoutRealizedContent?.equivalenceSignature,
        lhs.drawPayload == rhs.drawPayload,
        lhs.intrinsicSize == rhs.intrinsicSize,
        lhs.indexedChildSource?.measurementSignature
          == rhs.indexedChildSource?.measurementSignature,
        lhs.children.count == rhs.children.count
      else {
        return false
      }
      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }

  /// Result of `placementEquivalence(to:)` — how a current resolved subtree
  /// relates to a cached one for retained-placement reuse.
  package enum PlacementEquivalence {
    /// Geometry diverges — the cached placement cannot be reused.
    case divergent
    /// Placement-equivalent (cached bounds reusable) but some geometry-stable
    /// metadata mirror (color, semantics, lifecycle, animation tick…) changed,
    /// so the reused subtree must be re-synced from the current resolved tree.
    case geometryReusable
    /// Fully identical across the subtree, including every metadata field that
    /// `PlacedNode` mirrors — the cached placed subtree is already correct and
    /// can be reused untouched (no metadata sync needed).
    case identical
  }

  /// Single-walk equivalence used by the retained-placement cache. It subsumes
  /// `isEquivalentForPlacement` (the geometry gate) and additionally reports
  /// whether the geometry-stable metadata mirrors are *also* unchanged, so the
  /// caller can skip the O(subtree) `synchronizeRetainedPhaseMetadata` rebuild
  /// on the common case where resolve carried the subtree forward
  /// byte-identically. Crucially it compares fields in place — it never projects
  /// a `PlacedNodeResolvedMetadata` per node — so the metadata check adds only a
  /// handful of comparisons to a walk that already runs.
  package func placementEquivalence(
    to other: Self
  ) -> PlacementEquivalence {
    // The recursion folded a tri-state on the way back up; this walks the same
    // pairs on the heap and folds globally instead. That is the same function
    // because the lattice is order-independent: a failed geometry gate anywhere
    // makes every ancestor `.divergent`, and a `.geometryReusable` anywhere
    // poisons every ancestor to exactly `.geometryReusable`. So `.identical`
    // holds iff no node in the subtree ever diverged on metadata.
    var sawMetadataDivergence = false
    var pending: [(Self, Self)] = [(self, other)]

    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.structuralPath == rhs.structuralPath,
        lhs.kind == rhs.kind,
        Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator),
        lhs.environmentSnapshot == rhs.environmentSnapshot,
        lhs.layoutBehavior.isEquivalentForPlacement(to: rhs.layoutBehavior),
        lhs.layoutMetadata == rhs.layoutMetadata,
        // Alignment-guide closures are invisible to `layoutMetadata ==`; a
        // guide-carrying node can never prove its placement inputs unchanged.
        !lhs.layoutMetadata.hasExplicitAlignmentGuides,
        lhs.layoutRealizedContent?.equivalenceSignature
          == rhs.layoutRealizedContent?.equivalenceSignature,
        lhs.drawPayload == rhs.drawPayload,
        lhs.intrinsicSize == rhs.intrinsicSize,
        lhs.indexedChildSource?.measurementSignature
          == rhs.indexedChildSource?.measurementSignature,
        lhs.children.count == rhs.children.count
      else {
        return .divergent
      }

      // Metadata mirrored by `PlacedNode` beyond the geometry gate above.
      // `kind`, `environmentSnapshot`, `layoutMetadata`, and `drawPayload` are
      // already proven equal by the gate; `semanticRole` derives purely from
      // `semanticMetadata` / focus / `layoutBehavior`, all compared here.
      if !sawMetadataDivergence {
        sawMetadataDivergence =
          lhs.identity != rhs.identity
          || lhs.structuralEdgeRole != rhs.structuralEdgeRole
          || lhs.entityIdentity != rhs.entityIdentity
          || lhs.entityStructuralPath != rhs.entityStructuralPath
          || lhs.declarationOwnerEdge != rhs.declarationOwnerEdge
          || lhs.layoutBehavior != rhs.layoutBehavior
          || lhs.drawMetadata != rhs.drawMetadata
          || lhs.drawEffects != rhs.drawEffects
          || lhs.surfaceComposition != rhs.surfaceComposition
          || lhs.semanticMetadata != rhs.semanticMetadata
          || lhs.lifecycleMetadata != rhs.lifecycleMetadata
          || lhs.isTransient != rhs.isTransient
          || lhs.matchedGeometry != rhs.matchedGeometry
      }

      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }

    return sawMetadataDivergence ? .geometryReusable : .identical
  }

  /// Two discriminators are "compatible" for equivalence purposes when
  /// either both match or at least one is `nil`.  This is the bridging
  /// rule that lets migrated and un-migrated call sites coexist — a
  /// typed descriptor still matches a legacy descriptor with the same
  /// name, so partial migrations don't cause structural churn.
  package static func typeDiscriminatorsCompatible(
    _ lhs: ObjectIdentifier?,
    _ rhs: ObjectIdentifier?
  ) -> Bool {
    switch (lhs, rhs) {
    case (let l?, let r?):
      return l == r
    default:
      return true
    }
  }
}

extension ResolvedNode {
  /// Stage-1 memo oracle: whether reusing `self` in place of `other` would be
  /// observably identical *under the semantics the real retained-reuse path
  /// guarantees* — i.e. ignoring `structuralPath` (re-stamped on reuse, see
  /// ViewFoundation reuse return) and comparing `transactionSnapshot` by
  /// `isReuseEquivalent` (the gate's check) rather than strict `==`. Every
  /// other field must match exactly, recursing into children. This is the
  /// sound oracle for memoization, vs the stricter `==` used elsewhere.
  package func memoReuseEquivalent(to other: ResolvedNode) -> Bool {
    // Heap-backed traversal: this runs on the resolve leg of the fused frame
    // tail (`ViewFoundation`'s memo gate), on the same small worker stack that
    // overflowed `isEquivalentForMeasurement` in production.
    var pending: [(ResolvedNode, ResolvedNode)] = [(self, other)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.identity == rhs.identity,
        lhs.structuralEdgeRole == rhs.structuralEdgeRole,
        lhs.entityIdentity == rhs.entityIdentity,
        lhs.entityStructuralPath == rhs.entityStructuralPath,
        lhs.declarationOwnerEdge == rhs.declarationOwnerEdge,
        lhs.kind == rhs.kind,
        Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator),
        lhs.environmentSnapshot == rhs.environmentSnapshot,
        lhs.transactionSnapshot.isReuseEquivalent(to: rhs.transactionSnapshot),
        lhs.layoutBehavior == rhs.layoutBehavior,
        lhs.layoutMetadata == rhs.layoutMetadata,
        lhs.layoutRealizedContent?.equivalenceSignature
          == rhs.layoutRealizedContent?.equivalenceSignature,
        lhs.drawMetadata == rhs.drawMetadata,
        lhs.drawEffects == rhs.drawEffects,
        lhs.surfaceComposition == rhs.surfaceComposition,
        lhs.semanticMetadata == rhs.semanticMetadata,
        lhs.lifecycleMetadata == rhs.lifecycleMetadata,
        lhs.handlerInventory == rhs.handlerInventory,
        lhs.drawPayload == rhs.drawPayload,
        lhs.intrinsicSize == rhs.intrinsicSize,
        lhs.indexedChildSource?.measurementSignature
          == rhs.indexedChildSource?.measurementSignature,
        lhs.preferenceValues == rhs.preferenceValues,
        lhs.supportsRetainedReuse == rhs.supportsRetainedReuse,
        // matchedGeometry is set at resolve time by .matchedGeometryEffect
        // (F96): a config change served from memo would pair stale geometry.
        // isTransient is a runtime-overlay product, always false at resolve —
        // compared for totality, vacuous on the resolve path.
        lhs.matchedGeometry == rhs.matchedGeometry,
        lhs.isTransient == rhs.isTransient,
        lhs.children.count == rhs.children.count
      else { return false }
      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }

  /// Stage-1 memo alarm classifier: returns the first **content** field on
  /// which the two nodes diverge, or nil when every divergence is per-resolve
  /// identity bookkeeping (`entityIdentity`/`entityStructuralPath`) or
  /// committed registration bookkeeping (`handlerInventory`; plus
  /// `structuralPath`, which ``memoReuseEquivalent(to:)`` already ignores, and
  /// `transactionSnapshot` compared by reuse-equivalence).
  ///
  /// The split matters because the bookkeeping fields are re-derived on every
  /// resolve pass (occurrence ordinals, entity re-routes), so a strict oracle
  /// counts them as "unsound" even though serving the committed node would be
  /// observably fine — measured at ~96% of the `no_reads` unsound class. A
  /// content divergence with no recorded reads, by contrast, is a comparator
  /// false-equal: the memo-soundness alarm
  /// (``SoundnessProbeConfiguration/recordMemoUnsoundSkip(_:)``) fires only on
  /// this class. Bookkeeping-only divergence burn-down is tracked with the
  /// comparator field-manifest work (F96 in the org findings registry).
  package func memoUnsoundContentDivergence(from other: ResolvedNode) -> String? {
    // Preorder in child order, carrying a depth so the reported
    // `"child.child.…field"` string stays byte-identical to the recursion's:
    // the probe histogram keys on it. The field ladder stays INLINE rather than
    // factored into a per-node helper — the F96 comparator field-totality lock
    // (`ResolvedNodeComparatorTotalityTests`) reads this function's own body
    // text to prove every stored field is compared or exempted, and a helper
    // would hide the fields from it.
    var pending: [(ResolvedNode, ResolvedNode, Int)] = [(self, other, 0)]
    while let (lhs, rhs, depth) = pending.popLast() {
      // Builds the prefix only on divergence, so a clean walk stays allocation
      // free rather than minting a string per node.
      func diverged(_ field: String) -> String {
        String(repeating: "child.", count: depth) + field
      }

      if lhs.identity != rhs.identity { return diverged("identity") }
      if lhs.structuralEdgeRole != rhs.structuralEdgeRole {
        return diverged("structuralEdgeRole")
      }
      if lhs.declarationOwnerEdge != rhs.declarationOwnerEdge {
        return diverged("declarationOwnerEdge")
      }
      if lhs.kind != rhs.kind { return diverged("kind") }
      if !Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator) {
        return diverged("typeDiscriminator")
      }
      if lhs.environmentSnapshot != rhs.environmentSnapshot {
        return diverged("environmentSnapshot")
      }
      if !lhs.transactionSnapshot.isReuseEquivalent(to: rhs.transactionSnapshot) {
        return diverged("transactionSnapshot")
      }
      if lhs.layoutBehavior != rhs.layoutBehavior { return diverged("layoutBehavior") }
      if lhs.layoutMetadata != rhs.layoutMetadata { return diverged("layoutMetadata") }
      if lhs.layoutRealizedContent?.equivalenceSignature
        != rhs.layoutRealizedContent?.equivalenceSignature
      {
        return diverged("layoutRealizedContent")
      }
      if lhs.drawMetadata != rhs.drawMetadata { return diverged("drawMetadata") }
      if lhs.drawEffects != rhs.drawEffects { return diverged("drawEffects") }
      if lhs.surfaceComposition != rhs.surfaceComposition {
        return diverged("surfaceComposition")
      }
      if lhs.semanticMetadata != rhs.semanticMetadata { return diverged("semanticMetadata") }
      if lhs.lifecycleMetadata != rhs.lifecycleMetadata { return diverged("lifecycleMetadata") }
      if lhs.drawPayload != rhs.drawPayload { return diverged("drawPayload") }
      if lhs.intrinsicSize != rhs.intrinsicSize { return diverged("intrinsicSize") }
      if lhs.indexedChildSource?.measurementSignature
        != rhs.indexedChildSource?.measurementSignature
      {
        return diverged("indexedChildSource")
      }
      if lhs.preferenceValues != rhs.preferenceValues { return diverged("preferenceValues") }
      if lhs.supportsRetainedReuse != rhs.supportsRetainedReuse {
        return diverged("supportsRetainedReuse")
      }
      if lhs.matchedGeometry != rhs.matchedGeometry { return diverged("matchedGeometry") }
      if lhs.isTransient != rhs.isTransient { return diverged("isTransient") }
      if lhs.children.count != rhs.children.count { return diverged("children.count") }

      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index], depth + 1))
      }
    }
    return nil
  }

  /// Stage-1 memo diagnostics: returns the first field that differs under the
  /// oracle's own semantics (or nil if oracle-equivalent), to characterize the
  /// `no_reads` unsound class — whether the mismatch is real content
  /// (`drawPayload`/`kind`/`children`/…, a comparator false-equal) or
  /// per-resolve identity bookkeeping (`entityIdentity`/…, an over-strict
  /// oracle field). Mirrors ``memoReuseEquivalent(to:)`` exactly: it never
  /// reports `structuralPath` (re-stamped on reuse, oracle-ignored) and
  /// compares `transactionSnapshot` by reuse-equivalence — reporting fields
  /// the oracle cannot fail on would misattribute the histogram. Content
  /// fields are checked before bookkeeping fields so a content divergence is
  /// never masked by a coincident bookkeeping diff.
  package func memoFirstDifferingField(from other: ResolvedNode) -> String? {
    // The content sweep is already a whole-subtree walk, so running it once at
    // the root is equivalent to the recursion re-running it per level (where it
    // returned nil every time after the first). What remains is a preorder
    // sweep for the bookkeeping fields, which reproduces the recursion's order:
    // a node's own bookkeeping before its children's, children in order.
    if let contentField = memoUnsoundContentDivergence(from: other) {
      return contentField
    }

    var pending: [(ResolvedNode, ResolvedNode, Int)] = [(self, other, 0)]
    while let (lhs, rhs, depth) = pending.popLast() {
      let prefix = String(repeating: "child.", count: depth)
      if lhs.entityIdentity != rhs.entityIdentity { return prefix + "entityIdentity" }
      if lhs.entityStructuralPath != rhs.entityStructuralPath {
        return prefix + "entityStructuralPath"
      }
      if lhs.handlerInventory != rhs.handlerInventory { return prefix + "handlerInventory" }
      // Counts already proven equal by the content sweep above.
      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index], depth + 1))
      }
    }

    // Unreachable in practice — the content and bookkeeping field sets union to
    // exactly `memoReuseEquivalent`'s — but kept as the recursion's own
    // defensive tail rather than silently dropped.
    return memoReuseEquivalent(to: other) ? nil : "other"
  }

  /// Explicit, iterative `==`.
  ///
  /// The synthesized/`children ==` form recursed through array equality, which
  /// is invisible at the call site and therefore the easiest way for this crash
  /// class to reopen. Converted regardless of the current caller inventory:
  /// enumerating "who compares a deep tree" is exactly the fragile analysis
  /// this work exists to delete, and the lint gate can then cover the file
  /// unconditionally.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    var pending: [(Self, Self)] = [(lhs, rhs)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.identity == rhs.identity,
        lhs.structuralPath == rhs.structuralPath,
        lhs.structuralEdgeRole == rhs.structuralEdgeRole,
        lhs.entityIdentity == rhs.entityIdentity,
        lhs.entityStructuralPath == rhs.entityStructuralPath,
        lhs.declarationOwnerEdge == rhs.declarationOwnerEdge,
        lhs.kind == rhs.kind,
        Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator),
        lhs.children.count == rhs.children.count,
        lhs.environmentSnapshot == rhs.environmentSnapshot,
        lhs.transactionSnapshot == rhs.transactionSnapshot,
        lhs.layoutBehavior == rhs.layoutBehavior,
        lhs.layoutMetadata == rhs.layoutMetadata,
        lhs.layoutRealizedContent?.equivalenceSignature
          == rhs.layoutRealizedContent?.equivalenceSignature,
        lhs.drawMetadata == rhs.drawMetadata,
        lhs.drawEffects == rhs.drawEffects,
        lhs.surfaceComposition == rhs.surfaceComposition,
        lhs.semanticMetadata == rhs.semanticMetadata,
        lhs.lifecycleMetadata == rhs.lifecycleMetadata,
        lhs.handlerInventory == rhs.handlerInventory,
        lhs.drawPayload == rhs.drawPayload,
        lhs.intrinsicSize == rhs.intrinsicSize,
        lhs.indexedChildSource?.measurementSignature
          == rhs.indexedChildSource?.measurementSignature,
        lhs.preferenceValues == rhs.preferenceValues,
        lhs.supportsRetainedReuse == rhs.supportsRetainedReuse,
        lhs.matchedGeometry == rhs.matchedGeometry,
        lhs.isTransient == rhs.isTransient
      else {
        return false
      }
      for index in lhs.children.indices.reversed() {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }
}
