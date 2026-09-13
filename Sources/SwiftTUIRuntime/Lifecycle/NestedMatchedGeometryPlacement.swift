import SwiftTUICore

/// Resolves adoption in displayed coordinates. A node depends on its parent
/// and (when adopting) its source, so source order in the tree is irrelevant.
/// The resulting local deltas compose through the ordinary placed-tree walk.
struct NestedMatchedGeometryPlacement {
  private struct Entry {
    var bounds: CellRect
    var parent: Identity?
  }

  private var entries: [Identity: Entry] = [:]
  private var pairs: [Identity: MatchedGeometryAdoptionPair] = [:]
  private var liveOffsets: [Identity: [PlacedAnimationOverlayOffset]] = [:]
  private var liveScales: [Identity: [PlacedAnimationOverlayScale]] = [:]
  private var resolved: [Identity: CellRect] = [:]
  private var offsets: [Identity: PlacedAnimationOverlayOffset] = [:]
  private var visiting: Set<Identity> = []
  private var cyclicAdoptees: Set<Identity> = []

  static func offsets(
    in tree: PlacedNode,
    pairs: [MatchedGeometryAdoptionPair],
    liveOffsets: [PlacedAnimationOverlayOffset],
    liveScales: [PlacedAnimationOverlayScale]
  ) -> [PlacedAnimationOverlayOffset] {
    var placement = Self()
    var pending: [(PlacedNode, Identity?)] = [(tree, nil)]
    while let (node, parent) = pending.popLast() {
      guard !node.isTransient else { continue }
      if placement.entries[node.identity] == nil {
        placement.entries[node.identity] = Entry(bounds: node.bounds, parent: parent)
      }
      for child in node.children.reversed() {
        pending.append((child, node.identity))
      }
    }
    for pair in pairs { placement.pairs[pair.nonSource] = pair }
    placement.liveOffsets = Dictionary(grouping: liveOffsets, by: \.identity)
    placement.liveScales = Dictionary(grouping: liveScales, by: \.identity)
    for pair in pairs { _ = placement.rect(for: pair.nonSource) }
    if !placement.cyclicAdoptees.isEmpty {
      // A source inside its own adopting ancestor has no independent target.
      // Suppress the cyclic adoption edges, then resolve from clean caches.
      placement.resolved.removeAll(keepingCapacity: true)
      placement.offsets.removeAll(keepingCapacity: true)
      for pair in pairs { _ = placement.rect(for: pair.nonSource) }
    }
    return pairs.compactMap { placement.offsets[$0.nonSource] }
  }

  private mutating func rect(for identity: Identity) -> CellRect? {
    if let rect = resolved[identity] { return rect }
    guard let entry = entries[identity] else { return nil }
    guard visiting.insert(identity).inserted else {
      cyclicAdoptees.formUnion(visiting.filter { pairs[$0] != nil })
      return entry.bounds
    }
    defer { visiting.remove(identity) }
    var rect = entry.bounds
    if let parent = entry.parent, let parentEntry = entries[parent],
      let parentRect = self.rect(for: parent)
    {
      rect.origin.x += parentRect.origin.x - parentEntry.bounds.origin.x
      rect.origin.y += parentRect.origin.y - parentEntry.bounds.origin.y
      if entry.bounds == parentEntry.bounds { rect.size = parentRect.size }
    }
    if let pair = pairs[identity], !cyclicAdoptees.contains(identity),
      let source = self.rect(for: pair.source), !cyclicAdoptees.contains(identity)
    {
      let adopted = MatchedGeometryAdoption.adoptedRect(
        nonSource: rect, source: source, properties: pair.properties, anchor: pair.anchor)
      offsets[identity] = .init(
        identity: identity, dx: adopted.origin.x - rect.origin.x,
        dy: adopted.origin.y - rect.origin.y,
        size: pair.properties.contains(.size) ? adopted.size : nil)
      rect = adopted
    }
    for offset in liveOffsets[identity] ?? [] {
      rect.origin.x += offset.dx
      rect.origin.y += offset.dy
      if let size = offset.size { rect.size = size }
    }
    for scale in liveScales[identity] ?? [] {
      rect = scaledTransitionRect(rect, scale: scale.scale, anchor: scale.anchor)
    }
    resolved[identity] = rect
    return rect
  }

  /// Matched interpolation targets are absolute displacements from baseline.
  /// Convert them to local channel deltas before composing parent dependencies.
  static func localOffsets(
    in tree: PlacedNode, absolute offsets: [PlacedAnimationOverlayOffset]
  ) -> [PlacedAnimationOverlayOffset] {
    guard !offsets.isEmpty else { return [] }
    var byIdentity: [Identity: PlacedAnimationOverlayOffset] = [:]
    for offset in offsets { byIdentity[offset.identity] = offset }
    var result: [PlacedAnimationOverlayOffset] = []
    var seen: Set<Identity> = []
    var pending: [(PlacedNode, Int, Int)] = [(tree, 0, 0)]
    while let (node, inheritedDX, inheritedDY) = pending.popLast() {
      var dx = inheritedDX
      var dy = inheritedDY
      if var offset = byIdentity[node.identity], seen.insert(node.identity).inserted {
        dx = offset.dx
        dy = offset.dy
        offset.dx -= inheritedDX
        offset.dy -= inheritedDY
        result.append(offset)
      }
      for child in node.children.reversed() { pending.append((child, dx, dy)) }
    }
    return result
  }

  /// Absolute adoption displacement for every affected descendant. A departing
  /// subtree can then freeze correctly even when its adopted ancestor survives.
  static func absoluteOffsets(
    in baseline: PlacedNode,
    applying offsets: [PlacedAnimationOverlayOffset]
  ) -> [Identity: PlacedAnimationOverlayOffset] {
    guard !offsets.isEmpty else { return [:] }
    var byIdentity: [Identity: PlacedAnimationOverlayOffset] = [:]
    for offset in offsets { byIdentity[offset.identity] = offset }
    let presented = translatePlacedNodesByIdentity(tree: baseline, offsets: byIdentity)
    var result: [Identity: PlacedAnimationOverlayOffset] = [:]
    var pending = [(baseline, presented)]
    while let (before, after) = pending.popLast() {
      if before.bounds != after.bounds || byIdentity[before.identity] != nil {
        result[before.identity] = .init(
          identity: before.identity,
          dx: after.bounds.origin.x - before.bounds.origin.x,
          dy: after.bounds.origin.y - before.bounds.origin.y,
          size: before.bounds.size == after.bounds.size ? nil : after.bounds.size)
      }
      pending.append(contentsOf: zip(before.children, after.children))
    }
    return result
  }
}
