import SwiftTUICore

/// Computes a conservative private raster reuse hint for a frame tail.
///
/// The returned damage may be passed to the rasterizer so it can reuse clean
/// rows from the previous raster surface. This is not the host-facing damage
/// contract; committed artifacts derive that contract from the actual previous
/// and current raster surfaces after rasterization.
enum FrameTailPresentationDamageResolver {
  static func resolve(
    rootIdentity: Identity,
    placed: PlacedNode,
    draw: DrawNode,
    retainedLayout: RetainedLayoutSession?,
    previousDraw: DrawNode?,
    previousSurfaceTopology: SurfaceTopologySignature?,
    animationRedrawIdentities: Set<Identity> = [],
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot = .init()
  ) -> FrameTailRasterReusePlan {
    // The draw-tree diff below rests on two premises: the previous surface is
    // exactly the raster of `previousDraw` (the retained-products gate in
    // `FrameTailRetainedState` stores that tree only when the effective placed
    // tree byte-matches the baseline), and the current draw tree completely
    // reflects everything this frame paints. Animation stresses both, in both
    // cases *after* invalidation was computed:
    //
    //  - property interpolation rewrites values in the already-resolved tree
    //    (`AnimationInjectionStage`), so what this frame paints depends on
    //    stages the retained-reuse machinery never saw as changes;
    //  - the placed overlay snapshot decorates the placed tree ahead of draw
    //    extraction with removal snapshots and insertion/matched-geometry
    //    offsets that the retained *baseline* placed tree does not carry.
    //
    // The products gate already withholds `previousDraw` on the frame *after*
    // an animated one, so barriering the animated frame itself costs at most
    // one frame of reuse per animation and keeps this resolver's soundness
    // argument local — no dependence on the extraction signature's sensitivity
    // to interpolated values or on overlay application ordering. An incomplete
    // "damage is complete" answer is release-only corruption under
    // `.trustSoundDamage`, so putting animating frames back on the incremental
    // path (e.g. damaging `redrawIdentities` subtree extents) must first prove
    // those remote invariants, not merely that the redraw set is exhaustive.
    guard animationRedrawIdentities.isEmpty else {
      return .init(damage: nil, barriers: [.animationInterpolationApplied])
    }
    // Co-present adoption is not a barrier: it decorates the tree the same
    // way on every frame with the same layout, the previous committed draw
    // tree was extracted from an equally adopted tree, and the draw-tree diff
    // below sees an adopted node's rect move exactly as it sees any other
    // bounds change. Only animation *samples* barrier.
    guard !animationOverlaySnapshot.hasTransientDecoration else {
      return .init(damage: nil, barriers: [.animationOverlayDecorated])
    }

    let currentSurfaceTopology = SurfaceTopologySignature(placedRoot: placed)
    if currentSurfaceTopology.differs(from: previousSurfaceTopology) {
      // PROTOTYPE (opt-in via SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE): when the only
      // topology change is a presentation overlay stack appearing on top of an
      // otherwise-unchanged background, re-raster just the overlay's painted rows
      // (plus the directly-invalidated trigger) instead of forcing a full fresh
      // re-raster of the whole surface. Falls back to the conservative full-diff
      // for any other topology change.
      if overlayIncrementalDamageEnabled,
        let bounded = additiveOverlayBoundedDamage(
          rootIdentity: rootIdentity,
          placed: placed,
          retainedLayout: retainedLayout,
          previousSurfaceTopology: previousSurfaceTopology,
          currentSurfaceTopology: currentSurfaceTopology
        )
      {
        return .init(damage: bounded, barriers: [])
      }
      return .init(damage: nil, barriers: [.surfaceTopologyChanged])
    }

    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex
    else {
      return .init(damage: nil, barriers: [.missingRetainedFrame])
    }

    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.isEmpty else {
      return .init(damage: nil, barriers: [.emptyInvalidation])
    }
    guard !directlyInvalidated.contains(rootIdentity) else {
      return .init(damage: nil, barriers: [.rootInvalidated])
    }

    // Damage is derived by diffing the previous committed *draw* tree against
    // this frame's, NOT from `directlyInvalidated` and not from the placed
    // trees.
    //
    // `directlyInvalidated` is the invalidation *seed* set — the identities
    // whose state or observation changed. Re-resolution routinely changes what
    // a node paints without that node being a seed: a sibling reading a derived
    // value, an environment or preference propagation, a container relaying out
    // around changed content. Keying damage on seed subtree extents under-reports,
    // and an incomplete "damage is complete" answer is release-only corruption.
    //
    // The placed tree is not a sound basis either: draw extraction reuses
    // retained subtrees (``RetainedPhaseExtractionProof``), so two frames with
    // byte-identical placed subtrees can still emit different draw commands.
    // The raster is a pure function of the draw tree, so diffing draw trees is
    // sound by construction — it is the last product before the cells.
    guard let previousDraw else {
      return .init(damage: nil, barriers: [.missingRetainedFrame])
    }
    // Both trees' diffs are rooted together; a re-rooted tree has nothing to
    // pair against. Topology-signature equality above should already imply
    // this, but the resolver is a soundness gate and must not rely on another
    // check's side effects.
    guard previousDraw.identity == draw.identity else {
      return .init(damage: nil, barriers: [.placedRootChanged])
    }

    // G12: the identity-keyed retained tables collapse duplicate explicit ids
    // last-writer-wins, so any consumer pairing "the" node for an identity can
    // silently mix siblings. Duplicates already emit a deterministic
    // `identity.duplicateEntity` `RuntimeIssue`, so barriering them costs
    // nothing legitimate.
    guard !hasCollidingPlacedIdentities(placed),
      previousFrameIndex.duplicateRuntimeIdentities.isEmpty
    else {
      return .init(damage: nil, barriers: [.duplicateInvalidatedIdentity])
    }

    var textRowRanges: [Int: [Range<Int>]] = [:]
    collectDrawTreeDamage(
      previous: previousDraw,
      current: draw,
      into: &textRowRanges
    )
    return .init(
      damage: PresentationDamage(
        textRows: textRowRanges.keys.sorted().map { row in
          .init(
            row: row,
            columnRanges: textRowRanges[row] ?? []
          )
        }
      ),
      barriers: []
    )
  }

  /// Diffs the previous committed draw tree against this frame's and records
  /// the rows every difference can repaint.
  ///
  /// The walk is *structural*: children are paired positionally and their
  /// identities checked, never looked up in an identity index. Identity-keyed
  /// pairing is not safe here — duplicate explicit ids collapse
  /// last-writer-wins, and occurrence-qualified duplicates can swap which
  /// sibling owns which identity between frames, both of which let a changed
  /// node compare equal to a *different* node and vanish from the damage set.
  ///
  /// Whole-subtree equality prunes: an unchanged subtree costs one comparison
  /// and contributes nothing. A node whose own projection is unchanged but
  /// whose descendants differ is walked into rather than painted over, which is
  /// what keeps a deep change from damaging every ancestor's slot up to the
  /// full-surface root.
  ///
  /// Explicit stack, not recursion: draw trees are as deep as the authored view
  /// hierarchy and the frame tail runs on 512 KiB Dispatch worker stacks.
  private static func collectDrawTreeDamage(
    previous previousRoot: DrawNode,
    current currentRoot: DrawNode,
    into textRowRanges: inout [Int: [Range<Int>]]
  ) {
    var stack: [(previous: DrawNode, current: DrawNode)] = [(previousRoot, currentRoot)]

    while let entry = stack.popLast() {
      let previous = entry.previous
      let current = entry.current
      if previous == current {
        continue
      }
      if !previous.paintProjectionEquals(current) {
        damage(current.bounds, into: &textRowRanges)
        damage(previous.bounds, into: &textRowRanges)
      }

      let pairedCount = min(previous.children.count, current.children.count)
      for index in 0..<pairedCount {
        let previousChild = previous.children[index]
        let currentChild = current.children[index]
        guard previousChild.identity == currentChild.identity else {
          // A re-key at this slot: the two subtrees are unrelated, so both the
          // ink that leaves and the ink that arrives has to be repainted.
          damage(previousChild.subtreeBounds, into: &textRowRanges)
          damage(currentChild.subtreeBounds, into: &textRowRanges)
          continue
        }
        stack.append((previousChild, currentChild))
      }
      // Departed children paint nothing now, so their previous ink has to be
      // erased explicitly; arrived children are all new ink.
      for index in pairedCount..<previous.children.count {
        damage(previous.children[index].subtreeBounds, into: &textRowRanges)
      }
      for index in pairedCount..<current.children.count {
        damage(current.children[index].subtreeBounds, into: &textRowRanges)
      }
    }
  }

  /// Records a changed rect, dilated by one cell on every side.
  ///
  /// A terminal cell is not the smallest unit this renderer paints: half-block
  /// glyphs give it sub-cell resolution, and the cell that carries the half
  /// block sits *outside* the region whose colour it shows. A panel's border
  /// ring takes its background from the interior it encloses; a button's focus
  /// fill shows through the boundary cell of the row below it. So a change
  /// confined to a node's own bounds can repaint the cells immediately around
  /// them, which damage derived from bounds alone misses — under release's
  /// `.trustSoundDamage` policy that ships as a stale band beside every control
  /// whose appearance changes. One cell is the whole reach: a half-block
  /// painter reaches the adjacent cell, never further.
  ///
  /// Measured, not assumed: gating this margin on "is there border chrome
  /// above me" left four scenarios in the full-suite F13 census still
  /// diverging, every one of them exactly one row from a changed control fill
  /// with no border node anywhere on the path.
  ///
  /// The one-cell reach is an assumed painter invariant, not a statically
  /// checked one — nothing prevents a future painter from sampling state two
  /// cells away. The enforcement is the F13 verify oracle: DEBUG re-rasters
  /// every incremental frame and the soundness probe asserts on divergence, so
  /// a painter that outgrows the margin reds the suites rather than shipping
  /// quietly — provided some suite paints it on an incremental frame.
  private static func damage(
    _ bounds: CellRect,
    into textRowRanges: inout [Int: [Range<Int>]]
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }
    textRows(
      for: CellRect(
        origin: .init(x: bounds.origin.x - 1, y: bounds.origin.y - 1),
        size: .init(width: bounds.size.width + 2, height: bounds.size.height + 2)
      ),
      into: &textRowRanges
    )
  }

  /// Whether any identity appears on more than one placed node.
  ///
  /// A lightweight scan rather than ``indexPlacedNodes(_:)``: the
  /// stable-topology path needs only the collision fact, not the node and
  /// parent maps the opt-in overlay prototype builds.
  private static func hasCollidingPlacedIdentities(_ root: PlacedNode) -> Bool {
    var seen: Set<Identity> = []
    var stack: [PlacedNode] = [root]
    while let node = stack.popLast() {
      if !seen.insert(node.identity).inserted {
        return true
      }
      stack.append(contentsOf: node.children)
    }
    return false
  }

  /// The current frame's placed tree, keyed by identity, together with the
  /// tree's *real* parent edges.
  ///
  /// Ancestry is recorded here rather than derived from `Identity.parent`
  /// because that projection is purely lexical: it drops the last path
  /// component and terminates only at the empty identity. Deriving a placed
  /// path from it both walks off the top of the placed tree — a real app roots
  /// its placed tree at the window content, so `App` and `(root)` are
  /// identities that never own a `PlacedNode` — and fails whenever a placed
  /// child's identity extends its placed parent's by more than one component
  /// (explicit ids and indexed components both make that shape reachable).
  private struct CurrentPlacedIndex {
    var rootIdentity: Identity
    var nodesByIdentity: [Identity: PlacedNode] = [:]
    var parentByIdentity: [Identity: Identity] = [:]
    /// Identities indexed more than once. Storage is last-writer-wins, so a
    /// path crossing one of these can silently mix nodes from different
    /// siblings; the resolver barriers instead.
    var collidingIdentities: Set<Identity> = []
  }

  /// Climbs recorded placed-tree edges from `identity` up to the placed root.
  ///
  /// Returns `nil` when the identity is not placed or any hop is missing, which
  /// keeps the resolver conservative for genuinely unplaced subtrees.
  private static func indexPlacedNodes(
    _ root: PlacedNode
  ) -> CurrentPlacedIndex {
    var index = CurrentPlacedIndex(rootIdentity: root.identity)
    var stack: [(node: PlacedNode, parent: Identity?)] = [(root, nil)]

    while let entry = stack.popLast() {
      let identity = entry.node.identity
      if index.nodesByIdentity.updateValue(entry.node, forKey: identity) != nil {
        index.collidingIdentities.insert(identity)
      }
      if let parent = entry.parent {
        index.parentByIdentity[identity] = parent
      }
      for child in entry.node.children.reversed() {
        stack.append((child, identity))
      }
    }

    return index
  }

  private static func textRows(
    for bounds: CellRect,
    into textRowRanges: inout [Int: [Range<Int>]]
  ) {
    guard bounds.size.width > 0,
      bounds.size.height > 0
    else {
      return
    }

    let lowerBound = max(0, bounds.origin.y)
    let upperBound = max(lowerBound, bounds.origin.y + bounds.size.height)
    let leadingColumn = max(0, bounds.origin.x)
    let trailingColumn = max(leadingColumn, bounds.origin.x + bounds.size.width)
    guard leadingColumn < trailingColumn else {
      return
    }

    for row in lowerBound..<upperBound {
      textRowRanges[row, default: []].append(leadingColumn..<trailingColumn)
    }
  }

  // MARK: - Additive-overlay bounded damage (prototype, opt-in)

  /// Opt-in flag. Default `false` keeps the conservative full-surface re-raster
  /// on every topology change, so this prototype never affects the default
  /// build. Set `SWIFTTUI_OVERLAY_INCREMENTAL_DAMAGE=1` to enable. Validate with
  /// `SWIFTTUI_RASTER_VERIFY_INCREMENTAL=1`, which re-rasters fresh and asserts
  /// the incremental surface is byte-identical (catching any under-reported
  /// damage).
  private static let overlayIncrementalDamageEnabled: Bool =
    FeatureGate.overlayIncrementalDamage.initialIsEnabled()

  /// Roles emitted *only* by the presentation overlay machinery
  /// (`OverlayStack` / `PresentationPortalRoot`). No background view produces
  /// these, so filtering them out isolates the background's contribution to the
  /// surface-topology signature.
  private static func isOverlayPresentationRole(
    _ role: SurfaceCompositionRole
  ) -> Bool {
    switch role {
    case .stackingContext, .detachedOverlayHost, .detachedOverlayEntry, .detachedOverlayRoot:
      true
    default:
      false
    }
  }

  /// Returns bounded raster-reuse damage when the surface-topology change is
  /// purely the appearance of a presentation overlay over an unchanged
  /// background. Returns `nil` (the caller then forces a full re-raster) for any
  /// other change, so this only ever *relaxes* the full-diff in the safe case.
  ///
  /// Soundness rests on the same model the stable-topology incremental path
  /// already trusts — `directlyInvalidated` is the complete set of changed
  /// background identities — plus two overlay-specific facts: (1) the new
  /// overlay only adds ink within the leaf bounds of its `.detachedOverlayHost`
  /// subtree (a full-surface translucent backdrop is itself a full-surface leaf,
  /// so it correctly expands damage to every row), and (2) inserting the overlay
  /// does not reflow the background (the base keeps an identical pass-through
  /// placement at origin `.zero`). The background's special-node topology being
  /// byte-identical is checked explicitly below.
  private static func additiveOverlayBoundedDamage(
    rootIdentity: Identity,
    placed: PlacedNode,
    retainedLayout: RetainedLayoutSession?,
    previousSurfaceTopology: SurfaceTopologySignature?,
    currentSurfaceTopology: SurfaceTopologySignature
  ) -> PresentationDamage? {
    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex,
      let previousSurfaceTopology
    else {
      return nil
    }

    // 1) The background's topology contribution must be byte-identical: with the
    //    overlay-presentation roles stripped, both signatures must be equal.
    guard
      backgroundTopologyMatches(
        previous: previousSurfaceTopology,
        current: currentSurfaceTopology
      )
    else {
      return nil
    }

    // 2) Rows the new overlay content actually paints (leaf bounds under the
    //    `.detachedOverlayHost` subtree).
    var dirtyRows: Set<Int> = []
    var foundOverlayHost = false
    collectOverlayPaintedRows(placed, into: &dirtyRows, foundOverlayHost: &foundOverlayHost)
    guard foundOverlayHost else {
      return nil
    }

    // 3) Union the directly-invalidated trigger (the control whose state toggled
    //    the presentation), previous + current bounds, so its own repaint is not
    //    dropped.
    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.contains(rootIdentity) else {
      return nil
    }
    let currentPlacedIndex = indexPlacedNodes(placed)
    for identity in directlyInvalidated {
      // Subtree extent, not own slot — same offset/position translation
      // reasoning as the stable-topology path above (F07).
      if let current = currentPlacedIndex.nodesByIdentity[identity] {
        addRows(current.subtreeBounds, into: &dirtyRows)
      }
      if let previous = previousFrameIndex.placedNode(for: identity) {
        addRows(previous.subtreeBounds, into: &dirtyRows)
      }
    }

    guard !dirtyRows.isEmpty else {
      return nil
    }
    return PresentationDamage(dirtyRows: dirtyRows)
  }

  private static func backgroundTopologyMatches(
    previous: SurfaceTopologySignature,
    current: SurfaceTopologySignature
  ) -> Bool {
    let previousBackground = previous.entries.filter { !isOverlayPresentationRole($0.role) }
    let currentBackground = current.entries.filter { !isOverlayPresentationRole($0.role) }
    return previousBackground == currentBackground
  }

  private static func collectOverlayPaintedRows(
    _ node: PlacedNode,
    into rows: inout Set<Int>,
    foundOverlayHost: inout Bool
  ) {
    if node.surfaceComposition.role == .detachedOverlayHost {
      foundOverlayHost = true
      collectLeafRows(node, into: &rows)
      return
    }
    for child in node.children {
      collectOverlayPaintedRows(child, into: &rows, foundOverlayHost: &foundOverlayHost)
    }
  }

  private static func collectLeafRows(
    _ node: PlacedNode,
    into rows: inout Set<Int>
  ) {
    if node.children.isEmpty {
      addRows(node.bounds, into: &rows)
      return
    }
    for child in node.children {
      collectLeafRows(child, into: &rows)
    }
  }

  private static func addRows(
    _ bounds: CellRect,
    into rows: inout Set<Int>
  ) {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return
    }
    let lowerRow = max(0, bounds.origin.y)
    let upperRow = max(lowerRow, bounds.maxY)
    guard lowerRow < upperRow else {
      return
    }
    for row in lowerRow..<upperRow {
      rows.insert(row)
    }
  }

}

struct FrameTailRasterReusePlan: Sendable {
  var damage: PresentationDamage?
  var barriers: Set<FrameTailRasterReuseBarrier>
}

enum FrameTailRasterReuseBarrier: String, Hashable, Sendable, CaseIterable {
  case missingRetainedFrame = "missing_retained_frame"
  case rootInvalidated = "root_invalidated"
  case emptyInvalidation = "empty_invalidation"
  case surfaceTopologyChanged = "surface_topology_changed"
  /// The previous frame's placed tree was rooted at a different identity, so
  /// the two placed paths are not comparable.
  case placedRootChanged = "placed_root_changed"
  /// An identity on one of the placed paths resolved to more than one node, so
  /// the path may mix nodes from different duplicate siblings.
  case duplicateInvalidatedIdentity = "duplicate_invalidated_identity"
  /// The head's animation-injection stage rewrote resolved values after
  /// invalidation was computed, so `directlyInvalidated` is not the complete
  /// set of identities that repaint this frame.
  case animationInterpolationApplied = "animation_interpolation_applied"
  /// The current placed tree carries animation overlay decoration that the
  /// retained baseline placed tree does not.
  case animationOverlayDecorated = "animation_overlay_decorated"
}
