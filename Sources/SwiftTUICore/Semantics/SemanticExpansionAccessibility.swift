extension SemanticExtractor {
  /// A trigger and its disclosed commands/content are siblings, so a button
  /// never owns interactive descendants in the accessibility tree.
  func expansionAccessibilityNodes(for node: PlacedNode, original: AccessibilityNode)
    -> [AccessibilityNode]?
  {
    guard let expansion = node.semanticMetadata.accessibilityStructure?.expansion else {
      return nil
    }
    let containerID = original.identity.child(.named("AccessibilityContainer"))
    var container = AccessibilityNode(
      identity: containerID, parentIdentity: original.parentIdentity,
      rect: node.bounds, role: .group)
    container.isEnabled = original.isEnabled
    var trigger = original
    trigger.parentIdentity = containerID
    if original.role == .menu || original.role == .disclosureGroup { trigger.role = .button }
    trigger.properties = AccessibilityProperties(
      expanded: expansion.expanded, popup: expansion.popup,
      controls: expansion.expanded ? [expansion.contentIdentity] : []
    ).merging(original.properties ?? .init())
    var stack = [node]
    var triggerRect: CellRect?
    let contentIdentity = expansion.contentIdentity.strippingEntityOccurrences
    var contentRect: CellRect?
    while let child = stack.popLast() {
      if child.isTransient { continue }
      if child.semanticMetadata.accessibilityProperties?.identifier?.strippingEntityOccurrences
        == contentIdentity
      {
        // Menu content and empty disclosure slots already publish their region.
        // Its descendants cannot supply another region for this expansion.
        continue
      }
      if child.semanticMetadata.accessibilityStructure?.parent?.strippingEntityOccurrences
        == contentIdentity
      {
        contentRect = contentRect.map { $0.union(child.bounds) } ?? child.bounds
        // A payload root owns its full layout bounds. Nested disclosure content
        // belongs to its own expansion and is extracted by that owner later.
        continue
      }
      if child.semanticMetadata.accessibilityHidden { continue }
      if triggerRect == nil,
        child.semanticMetadata.explicitRouteIdentity == expansion.visualIdentity
      {
        triggerRect = child.bounds
        // Menu owns a mounted content region, so retain its trigger-only scan.
        // This primitive-owned metadata survives authored role overrides.
        if expansion.popup == .menu { break }
        continue
      }
      stack.append(contentsOf: child.children.reversed())
    }
    trigger.rect =
      triggerRect
      ?? CellRect(
        origin: node.bounds.origin,
        size: .init(width: node.bounds.size.width, height: min(1, node.bounds.size.height)))
    guard expansion.expanded, let contentRect else { return [container, trigger] }
    var content = AccessibilityNode(
      identity: contentIdentity, parentIdentity: original.identity,
      rect: contentRect, role: .region)
    content.isEnabled = original.isEnabled
    content.properties = AccessibilityProperties(labelledBy: [original.identity])
    return [container, trigger, content]
  }
}
