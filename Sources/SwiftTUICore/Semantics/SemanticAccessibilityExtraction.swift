@_spi(Testing) import SwiftTUIPrimitives

extension SemanticExtractor {
  func accessibilityNodes(
    from root: PlacedNode,
    focusRegions: [FocusRegion]
  ) -> [AccessibilityNode] {
    let focusIdentities = accessibilityFocusIdentities(from: focusRegions)
    let textInputCursorAnchors = textInputAccessibilityCursorAnchors(from: root)
    var emittedSubtrees: Set<Identity> = []
    var hiddenDescendantSubtrees: Set<Identity> = []
    var stack: [(node: PlacedNode, isExit: Bool)] = [(root, false)]

    while let frame = stack.popLast() {
      let node = frame.node
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if frame.isExit {
        let childSummary = accessibilityChildSummary(
          for: node,
          emittedSubtrees: emittedSubtrees,
          hiddenDescendantSubtrees: hiddenDescendantSubtrees
        )
        if accessibilitySelfIsRelevant(node, focusIdentities: focusIdentities)
          || childSummary.hasEmittedChild
        {
          emittedSubtrees.insert(node.identity)
        }
        if childSummary.hasHiddenDescendant {
          hiddenDescendantSubtrees.insert(node.identity)
        }
      } else {
        stack.append((node, true))
        for child in node.children.reversed() {
          stack.append((child, false))
        }
      }
    }

    var nodes: [AccessibilityNode] = []
    var emitStack: [(node: PlacedNode, emittedParentIdentity: Identity?)] = [(root, nil)]
    while let frame = emitStack.popLast() {
      let node = frame.node
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      let emits = emittedSubtrees.contains(node.identity)
      var childParentIdentity = frame.emittedParentIdentity
      if emits {
        let childSummary = accessibilityChildSummary(
          for: node,
          emittedSubtrees: emittedSubtrees,
          hiddenDescendantSubtrees: hiddenDescendantSubtrees
        )
        if let accessibilityNode = accessibilityNode(
          for: node,
          parentIdentity: frame.emittedParentIdentity,
          hasEmittedChild: childSummary.hasEmittedChild,
          hasHiddenDescendant: childSummary.hasHiddenDescendant,
          focusIdentities: focusIdentities,
          textInputCursorAnchors: textInputCursorAnchors
        ) {
          nodes.append(accessibilityNode)
          childParentIdentity = node.identity
        }
      }

      for child in node.children.reversed() {
        emitStack.append((child, childParentIdentity))
      }
    }

    return nodes
  }

  func accessibilityWarnings(
    from root: PlacedNode
  ) -> [AccessibilityWarning] {
    var warnings: [AccessibilityWarning] = []
    var stack = [root]

    while let node = stack.popLast() {
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if let visualContent = node.semanticMetadata.accessibilityVisualContent,
        accessibilityVisualContentIsUnlabeled(node)
      {
        warnings.append(
          AccessibilityWarning(
            identity: node.identity,
            kind: visualContent.kind,
            message:
              "\(visualContent.kind) omitted from accessibility output; add accessibilityLabel(...) or accessibilityHidden(true)."
          )
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }

    return warnings
  }

  private func accessibilityFocusIdentities(
    from focusRegions: [FocusRegion]
  ) -> Set<Identity> {
    var identities: Set<Identity> = []
    for region in focusRegions {
      identities.insert(region.identity)
      for scopeIdentity in region.scopePath {
        identities.insert(scopeIdentity)
      }
    }
    return identities
  }

  private func accessibilityChildSummary(
    for node: PlacedNode,
    emittedSubtrees: Set<Identity>,
    hiddenDescendantSubtrees: Set<Identity>
  ) -> (hasEmittedChild: Bool, hasHiddenDescendant: Bool) {
    var hasEmittedChild = false
    var hasHiddenDescendant = false

    for child in node.children where !child.isTransient {
      if emittedSubtrees.contains(child.identity) {
        hasEmittedChild = true
      }
      if child.semanticMetadata.accessibilityHidden
        || hiddenDescendantSubtrees.contains(child.identity)
      {
        hasHiddenDescendant = true
      }
    }

    return (hasEmittedChild, hasHiddenDescendant)
  }

  private func accessibilitySelfIsRelevant(
    _ node: PlacedNode,
    focusIdentities: Set<Identity>,
    textInputCursorAnchors: [Identity: CellPoint] = [:]
  ) -> Bool {
    if accessibilityVisualContentIsUnlabeled(node) {
      return false
    }

    return node.semanticMetadata.accessibilityRole != nil
      || node.semanticMetadata.accessibilityLabel != nil
      || node.semanticMetadata.accessibilityHint != nil
      || node.semanticMetadata.accessibilityLiveRegion != nil
      || node.semanticMetadata.accessibilityCursorAnchor != nil
      || textInputCursorAnchors[node.identity] != nil
      || focusIdentities.contains(node.identity)
  }

  private func accessibilityNode(
    for node: PlacedNode,
    parentIdentity: Identity?,
    hasEmittedChild: Bool,
    hasHiddenDescendant: Bool,
    focusIdentities: Set<Identity>,
    textInputCursorAnchors: [Identity: CellPoint]
  ) -> AccessibilityNode? {
    let selfIsRelevant = accessibilitySelfIsRelevant(
      node,
      focusIdentities: focusIdentities,
      textInputCursorAnchors: textInputCursorAnchors
    )
    guard
      let role = accessibilityRole(
        for: node,
        isRelevant: selfIsRelevant,
        hasEmittedChild: hasEmittedChild
      )
    else {
      return nil
    }

    return AccessibilityNode(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      parentIdentity: parentIdentity,
      rect: semanticBounds(for: node),
      role: role,
      label: accessibilityLabel(for: node, role: role),
      hint: node.semanticMetadata.accessibilityHint,
      hidden: hasHiddenDescendant,
      liveRegion: node.semanticMetadata.accessibilityLiveRegion,
      cursorAnchor: textInputCursorAnchors[node.identity] ?? accessibilityCursorAnchor(for: node)
    )
  }

  private func textInputAccessibilityCursorAnchors(
    from root: PlacedNode
  ) -> [Identity: CellPoint] {
    var anchors: [Identity: CellPoint] = [:]
    var stack = [root]

    while let node = stack.popLast() {
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if let route = node.semanticMetadata.textInputAccessibilityCursorAnchor {
        let bounds = semanticBounds(for: node)
        anchors[route.ownerIdentity] = CellPoint(
          x: bounds.origin.x + route.anchor.x,
          y: bounds.origin.y + route.anchor.y
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }

    return anchors
  }

  private func accessibilityRole(
    for node: PlacedNode,
    isRelevant: Bool,
    hasEmittedChild: Bool
  ) -> AccessibilityRole? {
    if let role = node.semanticMetadata.accessibilityRole {
      return role
    }
    if isRelevant || hasEmittedChild {
      return .group
    }
    return nil
  }

  private func accessibilityLabel(
    for node: PlacedNode,
    role: AccessibilityRole
  ) -> String? {
    if let label = node.semanticMetadata.accessibilityLabel {
      return label
    }
    if accessibilityRoleInfersTextLabel(role),
      let textLabel = accessibilityTextLabel(from: node.drawPayload)
    {
      return textLabel
    }
    if accessibilityRoleInfersTabLabel(role),
      let tabLabel = node.semanticMetadata.tabItemLabel
    {
      return tabLabel.title
    }
    return nil
  }

  private func accessibilityRoleInfersTextLabel(
    _ role: AccessibilityRole
  ) -> Bool {
    switch role {
    case .button, .link, .tab, .menuItem, .heading:
      true
    default:
      false
    }
  }

  private func accessibilityRoleInfersTabLabel(
    _ role: AccessibilityRole
  ) -> Bool {
    switch role {
    case .tab, .tabPanel, .tabView:
      true
    default:
      false
    }
  }

  private func accessibilityTextLabel(
    from payload: DrawPayload
  ) -> String? {
    let label: String?
    switch payload {
    case .text(let value):
      label = value
    case .richText(let payload):
      label = payload.visibleText
    case .none, .textFigure, .image, .shape, .rule, .list, .table, .canvas,
      .foreignSurface:
      label = nil
    }
    guard let label, !label.isEmpty else {
      return nil
    }
    return label
  }

  private func accessibilityCursorAnchor(
    for node: PlacedNode
  ) -> CellPoint? {
    guard let anchor = node.semanticMetadata.accessibilityCursorAnchor else {
      return nil
    }
    let bounds = semanticBounds(for: node)
    return CellPoint(
      x: bounds.origin.x + anchor.x,
      y: bounds.origin.y + anchor.y
    )
  }

  private func accessibilityVisualContentIsUnlabeled(
    _ node: PlacedNode
  ) -> Bool {
    guard node.semanticMetadata.accessibilityVisualContent != nil else {
      return false
    }
    return !hasNonEmptyAccessibilityLabel(node.semanticMetadata.accessibilityLabel)
  }

  private func hasNonEmptyAccessibilityLabel(
    _ label: String?
  ) -> Bool {
    guard let label else {
      return false
    }
    return label.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
        false
      default:
        true
      }
    }
  }

}
