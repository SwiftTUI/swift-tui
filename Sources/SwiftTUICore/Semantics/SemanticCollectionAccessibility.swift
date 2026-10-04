@_spi(Testing) import SwiftTUIPrimitives

extension SemanticExtractor {
  func collectionNavigationNodes(for node: PlacedNode, parent: AccessibilityNode)
    -> [AccessibilityNode]
  {
    guard let navigation = node.semanticMetadata.accessibilityStructure?.collectionNavigation else {
      return []
    }
    let identity = navigation.identity.strippingEntityOccurrences
    var item = AccessibilityNode(
      viewNodeID: node.viewNodeID, identity: identity, parentIdentity: parent.parentIdentity,
      rect: node.bounds, role: .stepper,
      label: parent.label.map { "Review items in \($0)" } ?? "Review items")
    var actions = ["Read item", "First item", "Last item", "Previous page", "Next page"]
    if navigation.canReturn { actions.append("Return to previous item") }
    item.control = .init(
      actions: [
        .increment, .decrement, .setValue, .custom, .accessibilityFocus, .accessibilityBlur,
      ],
      value: .number(Double(navigation.position)), minimum: 1, maximum: Double(navigation.count),
      step: 1,
      customActions: actions)
    item.properties = .init(
      valueDescription: "Item \(navigation.position) of \(navigation.count)",
      controls: [parent.identity])
    // Reviewing content is independent of whether its application operations
    // are enabled. The realized row controls retain their disabled state.
    item.isEnabled = true
    item.actionIdentity = navigation.identity
    if let owner = node.viewNodeID { item.actionTarget = "\(owner.rawValue):\(identity.path)" }
    return [item]
  }

  func installCollectionReview(on item: inout AccessibilityNode, for node: PlacedNode) {
    guard let review = node.semanticMetadata.hostedCollectionItem?.review else { return }
    item.viewNodeID = review.ownerNodeID
    item.actionIdentity = review.identity
    item.control = .init(actions: [.accessibilityFocus, .accessibilityBlur])
    if let owner = review.ownerNodeID {
      item.actionTarget = "\(owner.rawValue):\(item.identity.path)"
    }
  }

  /// A row selector is an ordinary operation inside a structural list item or
  /// table cell. Nested authored controls retain their independent operations.
  func collectionSelectionNodes(for node: PlacedNode, parent: Identity, readOnly: Bool?)
    -> [AccessibilityNode]
  {
    guard let selection = node.semanticMetadata.hostedCollectionItem?.selection else { return [] }
    let rowIndex: Int
    let isTable: Bool
    switch node.semanticMetadata.hostedCollectionItem?.role {
    case .tableRow(let index):
      rowIndex = index
      isTable = true
    case .listRow(let index):
      rowIndex = index
      isTable = false
    default: return []
    }
    let bounds = CellRect(
      origin: .init(x: max(0, node.bounds.origin.x - 2), y: node.bounds.origin.y),
      size: .init(width: 2, height: max(1, node.bounds.size.height)))
    let identity = node.identity.strippingEntityOccurrences.child(.named("AccessibilitySelection"))
    var result: [AccessibilityNode] = []
    let buttonParent: Identity
    if isTable {
      buttonParent = identity.child(.named("Cell"))
      var cell = AccessibilityNode(
        identity: buttonParent, parentIdentity: parent, rect: bounds, role: .cell)
      cell.properties = .init(rowIndex: rowIndex + 2, columnIndex: 1)
      result.append(cell)
    } else {
      buttonParent = parent
    }
    var button = AccessibilityNode(
      viewNodeID: selection.ownerNodeID, identity: identity, parentIdentity: buttonParent,
      rect: bounds, role: .button, label: "Select row \(rowIndex + 1)")
    button.control = .init(actions: [.activate], value: .boolean(selection.isSelected))
    button.properties = .init(
      readOnly: readOnly ?? node.semanticMetadata.accessibilityProperties?.readOnly)
    button.isEnabled = node.environmentSnapshot.style.isEnabled
    button.actionIdentity = selection.actionIdentity
    if let owner = selection.ownerNodeID {
      button.actionTarget = "\(owner.rawValue):\(identity.path)"
    }
    result.append(button)
    return result
  }

  /// A structural wrapper leaves the row's authored button/editor role intact.
  func listAccessibilityItem(
    for node: PlacedNode, parent: Identity?, count: Int?
  ) -> AccessibilityNode? {
    guard case .listRow(let index) = node.semanticMetadata.hostedCollectionItem?.role else {
      return nil
    }
    var item = AccessibilityNode(
      identity: node.identity.strippingEntityOccurrences.child(.named("AccessibilityListItem")),
      parentIdentity: parent?.strippingEntityOccurrences, rect: node.bounds,
      role: .custom("listitem"))
    let section = node.semanticMetadata.hostedCollectionItem?.section
    item.properties = .init(
      description: section.map { "\($0.title ?? "Section"), item \($0.position) of \($0.count)" },
      level: node.semanticMetadata.accessibilityProperties?.level,
      positionInSet: node.semanticMetadata.accessibilityProperties?.positionInSet ?? index + 1,
      setSize: node.semanticMetadata.accessibilityProperties?.setSize ?? count)
    item.isEnabled = node.environmentSnapshot.style.isEnabled
    installCollectionReview(on: &item, for: node)
    return item
  }

  /// Header titles are raster chrome, so publish their logical row explicitly.
  /// Keep names available when visual headers are hidden or clipped: body cells
  /// still need their column context. These nodes introduce no input routes.
  func tableAccessibilityHeaders(
    for node: PlacedNode, parent: AccessibilityNode
  ) -> [AccessibilityNode] {
    guard case .table(let payload) = node.drawPayload,
      node.semanticMetadata.hostedCollectionContainer?.kind == .table,
      !payload.columns.isEmpty
    else { return [] }
    let identity = parent.identity.child(.named("AccessibilityColumnHeaders"))
    let bounds = CellRect(
      origin: node.bounds.origin,
      size: .init(width: node.bounds.size.width, height: min(1, node.bounds.size.height)))
    var row = AccessibilityNode(
      identity: identity, parentIdentity: parent.identity, rect: bounds, role: .tableRow)
    row.properties = .init(rowIndex: 1)
    var result = [row]
    let titles =
      (node.semanticMetadata.hostedCollectionContainer?.hasSelection == true ? ["Selection"] : [])
      + payload.columns.map(\.title)
    for (index, title) in titles.enumerated() {
      var header = AccessibilityNode(
        identity: identity.child(.indexed("Column", index: index)), parentIdentity: identity,
        rect: bounds, role: .columnHeader, label: title)
      let columnIndex =
        index - (node.semanticMetadata.hostedCollectionContainer?.hasSelection == true ? 1 : 0)
      let sorts = node.semanticMetadata.hostedCollectionContainer?.headerSorts ?? []
      header.properties = .init(
        rowIndex: 1, columnIndex: index + 1,
        sort: sorts.indices.contains(columnIndex) ? sorts[columnIndex] : nil)
      result.append(header)
    }
    return result
  }
}
