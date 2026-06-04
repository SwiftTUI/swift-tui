@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

package struct PlacedAnimationOverlaySnapshot: Sendable {
  package var removalOverlays: [PlacedRemovalOverlaySnapshot]
  package var insertionOffsets: [PlacedAnimationOverlayOffset]
  package var matchedGeometryOffsets: [PlacedAnimationOverlayOffset]

  package init(
    removalOverlays: [PlacedRemovalOverlaySnapshot] = [],
    insertionOffsets: [PlacedAnimationOverlayOffset] = [],
    matchedGeometryOffsets: [PlacedAnimationOverlayOffset] = []
  ) {
    self.removalOverlays = removalOverlays
    self.insertionOffsets = insertionOffsets
    self.matchedGeometryOffsets = matchedGeometryOffsets
  }

  package var isEmpty: Bool {
    removalOverlays.isEmpty
      && insertionOffsets.isEmpty
      && matchedGeometryOffsets.isEmpty
  }
}

package struct PlacedRemovalOverlaySnapshot: Sendable {
  package var parentIdentity: Identity
  package var childIndex: Int
  package var snapshot: PlacedNode
  package var modifiers: TransitionModifiers

  package init(
    parentIdentity: Identity,
    childIndex: Int,
    snapshot: PlacedNode,
    modifiers: TransitionModifiers
  ) {
    self.parentIdentity = parentIdentity
    self.childIndex = childIndex
    self.snapshot = snapshot
    self.modifiers = modifiers
  }
}

package struct PlacedAnimationOverlayOffset: Sendable {
  package var identity: Identity
  package var dx: Int
  package var dy: Int

  package init(
    identity: Identity,
    dx: Int,
    dy: Int
  ) {
    self.identity = identity
    self.dx = dx
    self.dy = dy
  }
}

package func applyPlacedAnimationOverlaySnapshot(
  _ snapshot: PlacedAnimationOverlaySnapshot,
  to tree: inout PlacedNode
) {
  if !snapshot.removalOverlays.isEmpty {
    var injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]] = [:]
    for removal in snapshot.removalOverlays {
      var clone = removal.snapshot
      applyPlacedOverlayModifiers(
        removal.modifiers.resolvingEdgeOffset(surfaceSize: tree.bounds.size),
        to: &clone
      )
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
}

private func overlayOffsetMap(
  _ offsets: [PlacedAnimationOverlayOffset]
) -> [Identity: (dx: Int, dy: Int)] {
  var result: [Identity: (dx: Int, dy: Int)] = [:]
  for offset in offsets {
    result[offset.identity] = (dx: offset.dx, dy: offset.dy)
  }
  return result
}

private func translatePlacedNodesByIdentity(
  tree: PlacedNode,
  offsets: [Identity: (dx: Int, dy: Int)]
) -> PlacedNode {
  var node = tree
  if let delta = offsets[node.identity] {
    var translated = node
    translateBounds(&translated, dx: delta.dx, dy: delta.dy)
    return translated
  }
  let walked = node.children.map { child in
    translatePlacedNodesByIdentity(tree: child, offsets: offsets)
  }
  node.children = walked
  return node
}

private func applyPlacedOverlayModifiers(
  _ modifiers: TransitionModifiers,
  to node: inout PlacedNode
) {
  markTransient(&node)

  if let opacity = modifiers.opacity {
    applyOpacityCascadingPlaced(&node, opacity: opacity)
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

private func applyOpacityCascadingPlaced(
  _ node: inout PlacedNode,
  opacity: Double
) {
  var drawMetadata = node.drawMetadata
  let base = drawMetadata.baseStyle.explicitOpacity ?? 1.0
  drawMetadata.baseStyle.explicitOpacity = base * opacity
  node.drawMetadata = drawMetadata

  var children = node.children
  for i in children.indices {
    applyOpacityCascadingPlaced(&children[i], opacity: opacity)
  }
  node.children = children
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
