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
    while let child = stack.popLast() {
      if child.isTransient { continue }
      if child.semanticMetadata.explicitRouteIdentity == expansion.visualIdentity {
        triggerRect = child.bounds
        break
      }
      stack.append(contentsOf: child.children.reversed())
    }
    trigger.rect =
      triggerRect
      ?? CellRect(
        origin: node.bounds.origin,
        size: .init(width: node.bounds.size.width, height: min(1, node.bounds.size.height)))
    return [container, trigger]
  }
}
