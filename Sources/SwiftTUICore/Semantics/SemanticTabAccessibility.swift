extension SemanticExtractor {
  /// Publish logical tabs independently of the visible strip or overflow style.
  func tabAccessibilityNodes(for node: PlacedNode, parent: AccessibilityNode) -> [AccessibilityNode]
  {
    guard let tabs = node.semanticMetadata.accessibilityStructure?.tabs else { return [] }
    let stripID = parent.identity.child(.named("AccessibilityTabList"))
    let panelID = parent.identity.child(.named("AccessibilityTabPanel"))
    let stripBounds = CellRect(
      origin: node.bounds.origin,
      size: .init(width: node.bounds.size.width, height: min(1, node.bounds.size.height)))
    var strip = AccessibilityNode(
      identity: stripID, parentIdentity: parent.identity,
      rect: stripBounds, role: .tabView, label: parent.label ?? "Tabs")
    strip.isEnabled = node.environmentSnapshot.style.isEnabled
    var result = [strip]
    var placedRoutes: [Identity: CellRect] = [:]
    var panelBounds = node.bounds
    var stack = [node]
    while let child = stack.popLast() {
      if child.isTransient { continue }
      if let identity = child.semanticMetadata.explicitRouteIdentity {
        placedRoutes[identity] = child.bounds
      }
      if child.semanticMetadata.accessibilityStructure?.parent?.strippingEntityOccurrences
        == panelID
      {
        panelBounds = child.bounds
      }
      stack.append(contentsOf: child.children.reversed())
    }
    for tab in tabs {
      let identity = tab.identity.strippingEntityOccurrences
      var item = AccessibilityNode(
        viewNodeID: node.viewNodeID, identity: identity,
        parentIdentity: stripID, rect: placedRoutes[tab.visualIdentity] ?? stripBounds,
        role: .tab, label: tab.label)
      item.properties = .init(
        selected: tab.selected,
        readOnly: parent.properties?.readOnly, controls: [panelID])
      item.control = .init(actions: [.activate, .accessibilityFocus, .accessibilityBlur])
      item.isEnabled = node.environmentSnapshot.style.isEnabled
      item.actionIdentity = tab.identity
      if let owner = node.viewNodeID {
        item.actionTarget = "\(owner.rawValue):\(tab.identity.path)"
      }
      result.append(item)
    }
    var panel = AccessibilityNode(
      identity: panelID, parentIdentity: parent.identity,
      rect: panelBounds, role: .tabPanel)
    panel.properties = .init(
      labelledBy: tabs.filter(\.selected).map { $0.identity.strippingEntityOccurrences })
    result.append(panel)
    return result
  }
}
