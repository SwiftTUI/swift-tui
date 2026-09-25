@_spi(Testing) import SwiftTUIPrimitives

package struct AccessibilityVisualLabelRoutes: Sendable {
  package var inferredRolesByTraversalOrdinal: [Int: AccessibilityRole] = [:]
  package var claimedVisualTraversalOrdinals: Set<Int> = []
}

private struct AccessibilityVisualCandidate: Sendable {
  var traversalOrdinal: Int
  var role: AccessibilityRole
}

private enum AccessibilityVisualCandidateSummary: Sendable {
  case none
  case unique(AccessibilityVisualCandidate)
  case ambiguous

  mutating func merge(_ other: Self) {
    switch (self, other) {
    case (_, .none):
      break
    case (.none, _):
      self = other
    case (.unique, .unique), (.unique, .ambiguous), (.ambiguous, .unique),
      (.ambiguous, .ambiguous):
      self = .ambiguous
    }
  }

  /// An ambiguous summary keeps no members, so it stays ambiguous: an
  /// unclaimed sibling can then only warn, never be claimed further up.
  mutating func remove(_ candidate: AccessibilityVisualCandidate) {
    if case .unique(let unique) = self, unique.traversalOrdinal == candidate.traversalOrdinal {
      self = .none
    }
  }
}

private struct AuthoredAccessibilityLabelSummary {
  struct Source {
    var continuesPrevious: Bool
    var text: [String]
    var acceptsContinuation = true
  }

  var text: [String] = []
  var source: Source?

  mutating func merge(_ other: Self) {
    text.append(contentsOf: other.text)
    if source?.acceptsContinuation == true, let otherSource = other.source,
      otherSource.continuesPrevious
    {
      source?.text.append(contentsOf: otherSource.text)
      source?.acceptsContinuation = otherSource.acceptsContinuation
    } else if source != nil, let otherSource = other.source, !otherSource.continuesPrevious {
      // A repeated placement starts another slot. Ignore that entire slot,
      // including its later roots, rather than appending its continuation.
      source?.acceptsContinuation = false
    } else {
      source = source ?? other.source
    }
  }
}

private struct TextInputAccessibilityPresentation {
  let anchor: CellPoint
  let textInput: AccessibilityTextInput?
}

extension SemanticExtractor {
  func accessibilityNodesAndVisualLabelRoutes(
    from root: PlacedNode,
    focusRegions: [FocusRegion]
  ) -> (nodes: [AccessibilityNode], visualLabelRoutes: AccessibilityVisualLabelRoutes) {
    let focusIdentities = accessibilityFocusIdentities(from: focusRegions)
    let textInputPresentations = textInputAccessibilityPresentations(from: root)
    var visualLabelRoutes = AccessibilityVisualLabelRoutes()
    var visualCandidateSummaries: [Int: AccessibilityVisualCandidateSummary] = [:]
    // The subset of those candidates inside an authored label slot.
    var slotCandidateSummaries: [Int: AccessibilityVisualCandidateSummary] = [:]
    var labelSummaries: [Int: AuthoredAccessibilityLabelSummary] = [:]
    var authoredLabels: [Int: String] = [:]
    var emittedSubtrees: Set<Identity> = []
    var nextTraversalOrdinal = 0
    var stack:
      [(
        node: PlacedNode,
        traversalOrdinal: Int?,
        parentTraversalOrdinal: Int?,
        collectingLabel: Bool
      )] = [(root, nil, nil, false)]

    while let frame = stack.popLast() {
      let node = frame.node
      if let traversalOrdinal = frame.traversalOrdinal {
        var labelSummary =
          labelSummaries.removeValue(forKey: traversalOrdinal)
          ?? AuthoredAccessibilityLabelSummary()
        let metadata = node.semanticMetadata
        if let explicit = metadata.accessibilityLabel {
          labelSummary.text = explicit.isEmpty ? [] : [explicit]
        } else if metadata.usesAuthoredAccessibilityLabel {
          let label =
            labelSummary.source?.text.joined(separator: " ") ?? metadata.accessibilityTitle
          if let label { authoredLabels[traversalOrdinal] = label }
          labelSummary.text = label.map { $0.isEmpty ? [] : [$0] } ?? []
        } else if frame.collectingLabel,
          let text = accessibilityTextLabel(from: node.drawPayload)
        {
          labelSummary.text.insert(text, at: 0)
        }
        // Nested controls and Label own their slots. Their chrome and sources
        // must not escape to an enclosing control's name.
        if metadata.usesAuthoredAccessibilityLabel || metadata.accessibilityLabel != nil {
          labelSummary.source = nil
        }
        if let source = metadata.accessibilityLabelSource {
          labelSummary.source = .init(
            continuesPrevious: source == .continuation, text: labelSummary.text)
        }
        if !frame.collectingLabel { labelSummary.text = [] }
        if let parent = frame.parentTraversalOrdinal {
          labelSummaries[parent, default: .init()].merge(labelSummary)
        }
        var visualCandidateSummary: AccessibilityVisualCandidateSummary = .none
        if node.semanticMetadata.accessibilityRole == .image,
          accessibilityVisualContentIsUnlabeled(node)
        {
          visualCandidateSummary = .unique(
            AccessibilityVisualCandidate(
              traversalOrdinal: traversalOrdinal,
              role: .image
            )
          )
        }
        if let childSummary = visualCandidateSummaries.removeValue(
          forKey: traversalOrdinal
        ) {
          visualCandidateSummary.merge(childSummary)
        }
        var slotCandidateSummary =
          slotCandidateSummaries.removeValue(forKey: traversalOrdinal) ?? .none
        // An explicit label names everything beneath it. An authored name
        // names only the label slot: the rest of a control is chrome or
        // content, such as a DisclosureGroup's expanded content. A Label has
        // no role or content, so its icon is part of what its title names.
        let claimableSummary: AccessibilityVisualCandidateSummary =
          if let explicit = metadata.accessibilityLabel {
            hasNonEmptyAccessibilityLabel(explicit) ? visualCandidateSummary : .none
          } else if hasNonEmptyAccessibilityLabel(authoredLabels[traversalOrdinal]) {
            metadata.accessibilityRole == nil ? visualCandidateSummary : slotCandidateSummary
          } else {
            .none
          }
        if case .unique(let candidate) = claimableSummary {
          visualLabelRoutes.inferredRolesByTraversalOrdinal[traversalOrdinal] = candidate.role
          visualLabelRoutes.claimedVisualTraversalOrdinals.insert(
            candidate.traversalOrdinal
          )
          visualCandidateSummary.remove(candidate)
        }
        // A named node owns its slot; a slot root puts its subtree in the slot
        // of the control that authored it.
        if metadata.usesAuthoredAccessibilityLabel || metadata.accessibilityLabel != nil {
          slotCandidateSummary = .none
        }
        if metadata.accessibilityLabelSource != nil {
          slotCandidateSummary = visualCandidateSummary
        }
        if let parentTraversalOrdinal = frame.parentTraversalOrdinal {
          visualCandidateSummaries[parentTraversalOrdinal, default: .none].merge(
            visualCandidateSummary
          )
          slotCandidateSummaries[parentTraversalOrdinal, default: .none].merge(
            slotCandidateSummary
          )
        }

        let hasEmittedChild = accessibilityHasEmittedChild(
          for: node,
          emittedSubtrees: emittedSubtrees
        )
        if accessibilitySelfIsRelevant(node, focusIdentities: focusIdentities)
          || hasEmittedChild
        {
          emittedSubtrees.insert(node.identity)
        }
      } else {
        let traversalOrdinal = nextTraversalOrdinal
        nextTraversalOrdinal += 1
        if node.isTransient || node.semanticMetadata.accessibilityHidden {
          continue
        }

        let collectingLabel =
          frame.collectingLabel || node.semanticMetadata.accessibilityLabelSource != nil
        stack.append((node, traversalOrdinal, frame.parentTraversalOrdinal, collectingLabel))
        for child in node.children.reversed() {
          stack.append((child, nil, traversalOrdinal, collectingLabel))
        }
      }
    }

    var nodes: [AccessibilityNode] = []
    var nextEmitTraversalOrdinal = 0
    var emitStack: [(node: PlacedNode, emittedParentIdentity: Identity?)] = [(root, nil)]
    while let frame = emitStack.popLast() {
      let node = frame.node
      let traversalOrdinal = nextEmitTraversalOrdinal
      nextEmitTraversalOrdinal += 1
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      let emits = emittedSubtrees.contains(node.identity)
      var childParentIdentity = frame.emittedParentIdentity
      if emits {
        let hasEmittedChild = accessibilityHasEmittedChild(
          for: node,
          emittedSubtrees: emittedSubtrees
        )
        if let accessibilityNode = accessibilityNode(
          for: node,
          parentIdentity: frame.emittedParentIdentity,
          hasEmittedChild: hasEmittedChild,
          focusIdentities: focusIdentities,
          textInputPresentations: textInputPresentations,
          inferredVisualRole:
            visualLabelRoutes.inferredRolesByTraversalOrdinal[traversalOrdinal],
          authoredLabel: authoredLabels[traversalOrdinal]
        ) {
          nodes.append(accessibilityNode)
          childParentIdentity = node.identity
        }
      }

      for child in node.children.reversed() {
        emitStack.append((child, childParentIdentity))
      }
    }

    return (nodes, visualLabelRoutes)
  }

  func accessibilityWarnings(
    from root: PlacedNode,
    visualLabelRoutes: AccessibilityVisualLabelRoutes
  ) -> [AccessibilityWarning] {
    var warnings: [AccessibilityWarning] = []
    var nextTraversalOrdinal = 0
    var stack = [root]

    while let node = stack.popLast() {
      let traversalOrdinal = nextTraversalOrdinal
      nextTraversalOrdinal += 1
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if let visualContent = node.semanticMetadata.accessibilityVisualContent,
        accessibilityVisualContentIsUnlabeled(node),
        !visualLabelRoutes.claimedVisualTraversalOrdinals.contains(traversalOrdinal)
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

  private func accessibilityHasEmittedChild(
    for node: PlacedNode,
    emittedSubtrees: Set<Identity>
  ) -> Bool {
    node.children.contains { !$0.isTransient && emittedSubtrees.contains($0.identity) }
  }

  private func accessibilitySelfIsRelevant(
    _ node: PlacedNode,
    focusIdentities: Set<Identity>,
    textInputPresentations: [Identity: TextInputAccessibilityPresentation] = [:]
  ) -> Bool {
    if accessibilityVisualContentIsUnlabeled(node) {
      return false
    }

    return node.semanticMetadata.accessibilityRole != nil
      || node.semanticMetadata.accessibilityLabel != nil
      || node.semanticMetadata.accessibilityHint != nil
      || node.semanticMetadata.accessibilityLiveRegion != nil
      || node.semanticMetadata.accessibilityCursorAnchor != nil
      || textInputPresentations[node.identity] != nil
      || focusIdentities.contains(node.identity)
  }

  private func accessibilityNode(
    for node: PlacedNode,
    parentIdentity: Identity?,
    hasEmittedChild: Bool,
    focusIdentities: Set<Identity>,
    textInputPresentations: [Identity: TextInputAccessibilityPresentation],
    inferredVisualRole: AccessibilityRole?,
    authoredLabel: String?
  ) -> AccessibilityNode? {
    let selfIsRelevant = accessibilitySelfIsRelevant(
      node,
      focusIdentities: focusIdentities,
      textInputPresentations: textInputPresentations
    )
    guard
      let role = accessibilityRole(
        for: node,
        isRelevant: selfIsRelevant,
        hasEmittedChild: hasEmittedChild,
        inferredVisualRole: inferredVisualRole
      )
    else {
      return nil
    }

    var result = AccessibilityNode(
      viewNodeID: node.viewNodeID,
      // Reported identity is occurrence-free: duplicate siblings compare
      // equal, as authored, and per-owner attribution rides `viewNodeID`.
      // Internal lookups (cursor anchors, focus relevance) stay on the raw
      // occurrence-qualified identity.
      identity: node.identity.strippingEntityOccurrences,
      parentIdentity: parentIdentity?.strippingEntityOccurrences,
      rect: semanticBounds(for: node),
      role: role,
      label: node.semanticMetadata.accessibilityLabel ?? authoredLabel
        ?? accessibilityLabel(for: node, role: role),
      hint: node.semanticMetadata.accessibilityHint,
      // Hidden subtrees were already pruned. A hidden label decoration must
      // not hide its visible control (or ancestors) in browser/native hosts.
      hidden: false,
      liveRegion: node.semanticMetadata.accessibilityLiveRegion,
      cursorAnchor: textInputPresentations[node.identity]?.anchor
        ?? accessibilityCursorAnchor(for: node)
    )
    result.textInput = role == .secureField ? nil : textInputPresentations[node.identity]?.textInput
    result.control = node.semanticMetadata.accessibilityControl
    result.isEnabled = node.environmentSnapshot.style.isEnabled
    if let owner = node.viewNodeID, result.control != nil {
      result.actionTarget = "\(owner.rawValue):\(node.identity.path)"
      result.actionIdentity = node.identity
    }
    return result
  }

  private func textInputAccessibilityPresentations(
    from root: PlacedNode
  ) -> [Identity: TextInputAccessibilityPresentation] {
    var anchors: [Identity: TextInputAccessibilityPresentation] = [:]
    var stack = [root]

    while let node = stack.popLast() {
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if let route = node.semanticMetadata.textInputAccessibilityCursorAnchor {
        let bounds = semanticBounds(for: node)
        let anchor =
          route.wrappedText.map {
            wrappedTextCursorAnchor($0, offset: route.characterOffset, width: bounds.size.width)
          } ?? route.anchor
        anchors[route.ownerIdentity] = TextInputAccessibilityPresentation(
          anchor: CellPoint(x: bounds.origin.x + anchor.x, y: bounds.origin.y + anchor.y),
          textInput: route.text.map {
            accessibilityTextInput($0, bounds: bounds, wraps: route.wrappedText != nil)
          }
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
    hasEmittedChild: Bool,
    inferredVisualRole: AccessibilityRole?
  ) -> AccessibilityRole? {
    if let role = node.semanticMetadata.accessibilityRole {
      return role
    }
    if let inferredVisualRole {
      return inferredVisualRole
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
    case .button, .link, .tab, .menuItem, .heading, .status:
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
