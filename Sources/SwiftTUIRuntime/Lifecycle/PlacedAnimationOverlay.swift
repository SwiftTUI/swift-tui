@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

package struct PlacedAnimationOverlaySnapshot: Sendable {
  package var removalOverlays: [PlacedRemovalOverlaySnapshot]
  package var insertionOffsets: [PlacedAnimationOverlayOffset]
  package var insertionScales: [PlacedAnimationOverlayScale]
  package var matchedGeometryOffsets: [PlacedAnimationOverlayOffset]
  /// Co-present matched-geometry adoption: the deltas that render each
  /// `isSource: false` instance at its source's rect (plan 2026-08-25-003
  /// Stage A). Unlike the four channels above this one is steady-state —
  /// a deterministic function of the layout, not an animation sample — so
  /// it is applied first and does not count as transient decoration.
  package var adoptionOffsets: [PlacedAnimationOverlayOffset]

  package init(
    removalOverlays: [PlacedRemovalOverlaySnapshot] = [],
    insertionOffsets: [PlacedAnimationOverlayOffset] = [],
    insertionScales: [PlacedAnimationOverlayScale] = [],
    matchedGeometryOffsets: [PlacedAnimationOverlayOffset] = [],
    adoptionOffsets: [PlacedAnimationOverlayOffset] = []
  ) {
    self.removalOverlays = removalOverlays
    self.insertionOffsets = insertionOffsets
    self.insertionScales = insertionScales
    self.matchedGeometryOffsets = matchedGeometryOffsets
    self.adoptionOffsets = adoptionOffsets
  }

  /// No channel at all: the effective tree is the baseline.
  package var isEmpty: Bool {
    !hasTransientDecoration && adoptionOffsets.isEmpty
  }

  /// Whether an animation *sample* decorates the tree this frame: an exit
  /// overlay, an insertion offset or scale, or a matched-geometry offset.
  /// These are the channels the retained-products and incremental-raster
  /// gates must barrier on; an adoption-only snapshot decorates the tree the
  /// same way on every frame with the same layout and takes the incremental
  /// path.
  package var hasTransientDecoration: Bool {
    !removalOverlays.isEmpty
      || !insertionOffsets.isEmpty
      || !insertionScales.isEmpty
      || !matchedGeometryOffsets.isEmpty
  }
}

package struct PlacedRemovalOverlaySnapshot: Sendable {
  package var parentIdentity: Identity
  package var childIndex: Int
  package var snapshot: PlacedNode
  package var modifiers: TransitionModifiers
  /// The matched-geometry travel applied inside the overlay: the departing
  /// matched node's delta (and interpolated size) from its frozen rect
  /// toward its live counterpart's, or `nil` to fade in place.
  package var matchedGeometryOffset: PlacedAnimationOverlayOffset?

  package init(
    parentIdentity: Identity,
    childIndex: Int,
    snapshot: PlacedNode,
    modifiers: TransitionModifiers,
    matchedGeometryOffset: PlacedAnimationOverlayOffset? = nil
  ) {
    self.parentIdentity = parentIdentity
    self.childIndex = childIndex
    self.snapshot = snapshot
    self.modifiers = modifiers
    self.matchedGeometryOffset = matchedGeometryOffset
  }
}

package struct PlacedAnimationOverlayOffset: Sendable {
  package var identity: Identity
  package var dx: Int
  package var dy: Int
  /// The interpolated size a matched-geometry node renders at, or `nil`
  /// to keep its natural size (a translation only).
  package var size: CellSize?

  package init(
    identity: Identity,
    dx: Int,
    dy: Int,
    size: CellSize? = nil
  ) {
    self.identity = identity
    self.dx = dx
    self.dy = dy
    self.size = size
  }
}

package struct PlacedAnimationOverlayScale: Sendable {
  package var identity: Identity
  package var scale: Double
  package var anchor: UnitPoint

  package init(
    identity: Identity,
    scale: Double,
    anchor: UnitPoint
  ) {
    self.identity = identity
    self.scale = scale
    self.anchor = anchor
  }
}

package func applyPlacedAnimationOverlaySnapshot(
  _ snapshot: PlacedAnimationOverlaySnapshot,
  to tree: inout PlacedNode
) {
  // Adoption first: every later channel's offset is a delta relative to a
  // node's own rect, so a traveling exit overlay or a live insertion offset
  // on an adopted node composes on top of the adopted rect additively.
  let adoptionOffsets = overlayOffsetMap(snapshot.adoptionOffsets)
  if !adoptionOffsets.isEmpty {
    tree = translatePlacedNodesByIdentity(
      tree: tree,
      offsets: adoptionOffsets
    )
  }

  if !snapshot.removalOverlays.isEmpty {
    var injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]] = [:]
    for removal in snapshot.removalOverlays {
      var clone = removal.snapshot
      let modifiers = removal.modifiers.resolvingEdgeOffset(
        edgeBasis: removal.snapshot.bounds.size
      )
      applyPlacedOverlayModifiers(
        // Sampling already resolved the edge against the overlay's own size;
        // this only catches a snapshot that still carries a raw `moveEdge`,
        // and it resolves it on the same basis rather than the surface.
        modifiers,
        to: &clone
      )
      if let travel = removal.matchedGeometryOffset {
        // The departing matched node follows the same placed-level path as
        // the live counterpart (translate, then bounds-and-clip resize), so
        // the two rects coincide at every progress while they cross-fade.
        clone = translatePlacedNodesByIdentity(
          tree: clone,
          offsets: [travel.identity: travel]
        )
      }
      if let scale = modifiers.scale {
        applyScale(scale, to: &clone)
      }
      injections[removal.parentIdentity, default: []].append(
        (childIndex: removal.childIndex, snapshot: clone)
      )
    }
    tree = injectPlacedOverlays(tree: tree, injections: injections)
  }

  let insertionOffsets = overlayOffsetMap(snapshot.insertionOffsets)
  if !insertionOffsets.isEmpty {
    tree = translatePlacedNodesByIdentity(
      tree: tree,
      offsets: insertionOffsets
    )
  }

  let matchedGeometryOffsets = overlayOffsetMap(snapshot.matchedGeometryOffsets)
  if !matchedGeometryOffsets.isEmpty {
    tree = translatePlacedNodesByIdentity(
      tree: tree,
      offsets: matchedGeometryOffsets
    )
  }

  if !snapshot.insertionScales.isEmpty {
    tree = scalePlacedNodesByIdentity(
      tree: tree,
      scales: snapshot.insertionScales
    )
  }
}

private func overlayOffsetMap(
  _ offsets: [PlacedAnimationOverlayOffset]
) -> [Identity: PlacedAnimationOverlayOffset] {
  var result: [Identity: PlacedAnimationOverlayOffset] = [:]
  for offset in offsets {
    result[offset.identity] = offset
  }
  return result
}

/// Translates (and, when the offset carries a `size`, resizes by bounds and
/// clip) the first node matching each offset's identity. The walk stops at a
/// hit: an offset on a node *inside* a translated subtree is dropped, so a
/// nested matched node rides its ancestor's move (the register's nested-node
/// *Gap (narrowed)*).
package func translatePlacedNodesByIdentity(
  tree: PlacedNode,
  offsets: [Identity: PlacedAnimationOverlayOffset]
) -> PlacedNode {
  var node = tree
  if let delta = offsets[node.identity] {
    var translated = node
    translateBounds(&translated, dx: delta.dx, dy: delta.dy)
    if let size = delta.size {
      resizeBounds(&translated, to: size)
    }
    return translated
  }
  let walked = node.children.map { child in
    translatePlacedNodesByIdentity(tree: child, offsets: offsets)
  }
  node.children = walked
  return node
}

/// Resizes a matched-geometry node to its interpolated size at the placed
/// level (plan 2026-08-25-002 §3.2, bounds-and-clip rather than re-layout):
///
/// - the node's `bounds` and `contentBounds` take the new size;
/// - `drawMetadata.clipsToBounds` is set, which is what actually clips at
///   draw time (`DrawExtractor` derives the draw clip from it; the placed
///   `clipBounds` is never read by draw), and the placed `clipBounds` is
///   narrowed to the new rect so semantics hit-test what is painted;
/// - every descendant whose bounds coincided with the node's original
///   bounds (a `.background` fill, an overlay, full-frame chrome) resizes to
///   the same rect, so decoration follows the box while smaller content
///   descendants keep their layout and are clipped or unmasked.
private func resizeBounds(
  _ node: inout PlacedNode,
  to size: CellSize
) {
  let original = node.bounds
  let target = CellRect(origin: original.origin, size: size)
  resizeCoextensive(&node, from: original, to: target)
}

private func scalePlacedNodesByIdentity(
  tree: PlacedNode,
  scales: [PlacedAnimationOverlayScale]
) -> PlacedNode {
  var result = tree
  for scale in scales {
    result = scalePlacedNodeByIdentity(tree: result, scale: scale)
  }
  return result
}

private func scalePlacedNodeByIdentity(
  tree: PlacedNode,
  scale: PlacedAnimationOverlayScale
) -> PlacedNode {
  var node = tree
  if node.identity == scale.identity {
    applyScale(
      TransitionScaleEffect(scale: scale.scale, anchor: scale.anchor),
      to: &node
    )
    return node
  }
  node.children = node.children.map { child in
    scalePlacedNodeByIdentity(tree: child, scale: scale)
  }
  return node
}

private func applyScale(
  _ scale: TransitionScaleEffect,
  to node: inout PlacedNode
) {
  let target = scaledTransitionRect(node.bounds, scale: scale.scale, anchor: scale.anchor)
  translateBounds(
    &node,
    dx: target.origin.x - node.bounds.origin.x,
    dy: target.origin.y - node.bounds.origin.y
  )
  resizeBounds(&node, to: target.size)
}

package func scaledTransitionRect(
  _ rect: CellRect,
  scale: Double,
  anchor: UnitPoint
) -> CellRect {
  guard scale.isFinite else { return rect }
  let magnitude = abs(scale)
  let width = max(Int((Double(rect.size.width) * magnitude).rounded()), 0)
  let height = max(Int((Double(rect.size.height) * magnitude).rounded()), 0)
  let anchorX = Double(rect.origin.x) + anchor.x * Double(rect.size.width)
  let anchorY = Double(rect.origin.y) + anchor.y * Double(rect.size.height)
  return CellRect(
    origin: CellPoint(
      x: Int((anchorX - anchor.x * Double(width)).rounded()),
      y: Int((anchorY - anchor.y * Double(height)).rounded())
    ),
    size: CellSize(width: width, height: height)
  )
}

private func resizeCoextensive(
  _ node: inout PlacedNode,
  from original: CellRect,
  to target: CellRect
) {
  node.bounds = target
  let widthDelta = target.size.width - original.size.width
  let heightDelta = target.size.height - original.size.height
  node.contentBounds = CellRect(
    origin: node.contentBounds.origin,
    size: CellSize(
      width: max(node.contentBounds.size.width + widthDelta, 0),
      height: max(node.contentBounds.size.height + heightDelta, 0)
    )
  )
  node.drawMetadata.clipsToBounds = true
  if let clip = node.clipBounds {
    node.clipBounds = clip.intersection(target) ?? CellRect(origin: target.origin, size: .zero)
  } else {
    node.clipBounds = target
  }
  var children = node.children
  for index in children.indices where children[index].bounds == original {
    resizeCoextensive(&children[index], from: original, to: target)
  }
  node.children = children
}

private func applyPlacedOverlayModifiers(
  _ modifiers: TransitionModifiers,
  to node: inout PlacedNode
) {
  markTransient(&node)

  if let opacity = modifiers.opacity {
    applyOpacityAtOverlayRoot(&node, opacity: opacity)
  }

  let dx = modifiers.offsetX ?? 0
  let dy = modifiers.offsetY ?? 0
  if dx != 0 || dy != 0 {
    translateBounds(&node, dx: dx, dy: dy)
  }
}

private func markTransient(_ node: inout PlacedNode) {
  node.isTransient = true
  var children = node.children
  for i in children.indices {
    markTransient(&children[i])
  }
  node.children = children
}

/// Applies the overlay fade at the subtree root only: draw extraction
/// multiplies every ancestor's factor into descendant commands (the
/// multiplicative opacity cascade), so a recursive write here would square
/// the fade.
private func applyOpacityAtOverlayRoot(
  _ node: inout PlacedNode,
  opacity: Double
) {
  var drawMetadata = node.drawMetadata
  let base = drawMetadata.baseStyle.explicitOpacity ?? 1.0
  drawMetadata.baseStyle.explicitOpacity = base * opacity
  node.drawMetadata = drawMetadata
}

private func translateBounds(
  _ node: inout PlacedNode,
  dx: Int,
  dy: Int
) {
  let delta = CellPoint(x: dx, y: dy)
  node.bounds = CellRect(
    origin: CellPoint(
      x: node.bounds.origin.x + delta.x,
      y: node.bounds.origin.y + delta.y
    ),
    size: node.bounds.size
  )
  node.contentBounds = CellRect(
    origin: CellPoint(
      x: node.contentBounds.origin.x + delta.x,
      y: node.contentBounds.origin.y + delta.y
    ),
    size: node.contentBounds.size
  )
  if let clip = node.clipBounds {
    node.clipBounds = CellRect(
      origin: CellPoint(
        x: clip.origin.x + delta.x,
        y: clip.origin.y + delta.y
      ),
      size: clip.size
    )
  }
  var children = node.children
  for i in children.indices {
    translateBounds(&children[i], dx: dx, dy: dy)
  }
  node.children = children
}

private func injectPlacedOverlays(
  tree: PlacedNode,
  injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]]
) -> PlacedNode {
  var node = tree
  var children = node.children.map { child in
    injectPlacedOverlays(tree: child, injections: injections)
  }
  if let injectionsForNode = injections[node.identity] {
    let sorted = injectionsForNode.sorted { $0.childIndex < $1.childIndex }
    for injection in sorted {
      let insertIndex = min(injection.childIndex, children.count)
      children.insert(injection.snapshot, at: insertIndex)
    }
  }
  node.children = children
  return node
}
