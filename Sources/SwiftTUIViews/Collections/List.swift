@_spi(Testing) import SwiftTUICore

// `Section` — the header/content/footer grouping view — lives in
// `Section.swift`.

/// Presents selectable rows in a vertically scrollable list.
public struct List<SelectionValue: Hashable, Content: View>: PrimitiveView, ResolvableView {
  private var selectionPolicy: CollectionSelectionPolicy<SelectionValue>
  private var onActivate: (@MainActor (SelectionValue) -> Void)?
  private var content: Content
  package var usesIndexedDataSource = false

  @_disfavoredOverload
  public init(
    selection: Binding<SelectionValue>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .requiredSingle(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    selection: Binding<SelectionValue?>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .optionalSingle(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    selection: Binding<Set<SelectionValue>>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    selectionPolicy = .multiple(selection)
    self.onActivate = onActivate
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content
  ) where SelectionValue == Never {
    selectionPolicy = .none
    onActivate = nil
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension List {
  private struct RowSelection: Sendable {
    var tag: SelectionTag?
    var identity: Identity
  }

  private struct ResolvedItems {
    var items: [ListItemPayload] = []
    var rows: [RowSelection] = []
    var children: [ResolvedNode] = []
    var runtimeIssues: [RuntimeIssue] = []
    var indexedSource: (any IndexedChildSource)?
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let listStyle = context.environmentValues.listStyle.presentation
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility != .hidden
    let itemContext = context.child(component: .named("ListItems"))
    let resolvedContent: ResolvedItems
    if usesIndexedDataSource,
      let source = makeIndexedChildSource(
        from: content,
        in: itemContext.settingEnvironment(\.isResolvingHostedCollectionContent, to: true)
      )
    {
      resolvedContent = resolvedIndexedItems(from: source, in: context)
    } else {
      resolvedContent = resolvedItems(in: itemContext)
    }
    let rows = resolvedContent.rows
    let selectedIndices = rows.indices.filter { index in
      rows[index].tag.map(selectionPolicy.contains) == true
    }
    let selectedIndex = selectedIndices.first
    let focusedRowIndex = rows.indices.first { rowIndex in
      context.environmentValues.focusedIdentity
        == listRowIdentity(
          for: context.identity,
          rowIndex: rowIndex
        )
    }
    let isListOrRowFocused = isFocused || focusedRowIndex != nil
    let activeRowIndex = focusedRowIndex ?? selectedIndex
    // Focus is signalled at the row layer (caret + selected-row chrome);
    // the list container itself stays neutral so the row signal stays visible.
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: false
    )
    let rowChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isListOrRowFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled, selectionPolicy.isSelectable {
      let policy = selectionPolicy
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: nil
      )
      let activate: @MainActor (SelectionTag) -> Bool = { tag in
        guard let value = policy.value(from: tag) else {
          return false
        }
        if !policy.isMultiple {
          _ = policy.select(tag)
        }
        onActivate?(value)
        return true
      }
      intake.registerKeyHandler(identity: context.identity) { event in
        let delta: Int?
        switch event {
        case .arrowUp:
          delta = -1
        case .arrowDown:
          delta = 1
        case .return:
          guard let activeRowIndex, rows.indices.contains(activeRowIndex) else {
            return false
          }
          guard let tag = rows[activeRowIndex].tag else {
            return false
          }
          return activate(tag)
        case .space:
          guard let activeRowIndex, rows.indices.contains(activeRowIndex),
            let tag = rows[activeRowIndex].tag
          else {
            return false
          }
          return policy.isMultiple ? policy.toggle(tag) : activate(tag)
        default:
          delta = nil
        }

        guard let delta, !rows.isEmpty else {
          return false
        }

        return policy.step(orderedTags: rows.compactMap(\.tag), delta: delta)
      }

      let rootRouteID = runtimePrimaryRouteID(for: context.identity)
      intake.registerPointerHandler(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return policy.step(orderedTags: rows.compactMap(\.tag), delta: delta)
      }

      let interactionIndices: any Sequence<Int> =
        if resolvedContent.indexedSource == nil {
          rows.indices
        } else {
          collectionInteractionIndices(count: rows.count, anchor: activeRowIndex)
        }
      for rowIndex in interactionIndices {
        let row = rows[rowIndex]
        guard let tag = row.tag else {
          continue
        }
        let rowIdentity = listRowIdentity(
          for: context.identity,
          rowIndex: rowIndex
        )
        intake.registerAction(identity: rowIdentity) {
          policy.isMultiple ? policy.toggle(tag) : activate(tag)
        }
        intake.registerKeyHandler(identity: rowIdentity) { event in
          let delta: Int?
          switch event {
          case .arrowUp:
            delta = -1
          case .arrowDown:
            delta = 1
          default:
            delta = nil
          }

          guard let delta, !rows.isEmpty else {
            return false
          }

          let targetIndex = min(
            max(rowIndex + delta, rows.startIndex),
            rows.index(before: rows.endIndex)
          )
          guard let targetTag = rows[targetIndex].tag else {
            return false
          }
          if !policy.isMultiple {
            _ = policy.select(targetTag)
          }
          return false
        }
      }
    }

    var payload = ListPayload(
      items: resolvedContent.items,
      selectedRowIndex: activeRowIndex,
      style: listStyle,
      foregroundStyle: chrome.foregroundStyle,
      backgroundStyle: chrome.backgroundStyle,
      borderStyle: chrome.borderStyle,
      selectedRowForegroundStyle: isListOrRowFocused && showsFocusEffect
        ? rowChrome.foregroundStyle : nil,
      selectedRowBackgroundStyle: isListOrRowFocused && showsFocusEffect
        ? rowChrome.backgroundStyle : nil,
      selectedRowMarkerStyle: isListOrRowFocused && showsFocusEffect ? rowChrome.borderStyle : nil,
      // The gutter is structural: reserve it for any non-empty list whose
      // focus effects are enabled, regardless of whether focus is currently
      // inside the list. Toggling the gutter on focus arrival would shift
      // every row's content sideways at the moment of highlighting.
      showsSelectionMarker: showsFocusEffect && !rows.isEmpty,
      showsIndicators: showsIndicators,
      opacity: chrome.opacity
    )
    payload.isViewportBacked = resolvedContent.indexedSource != nil

    var metadata = focusableControlMetadata(
      isFocusable: rows.isEmpty ? nil : false,
      focusInteractions: .edit,
      scrollRole: .list,
      accessibilityRole: .list
    )
    metadata.hostedCollectionContainer = .init(kind: .list)
    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("List"),
      children: resolvedContent.children,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata,
      drawPayload: .list(payload),
      indexedChildSource: resolvedContent.indexedSource
    )
    node.drawMetadata.clipsToBounds = true
    var preferences = node.preferenceValues
    var runtimeIssues = preferences[RuntimeIssuePreferenceKey.self]
    for issue in resolvedContent.runtimeIssues where !runtimeIssues.contains(issue) {
      runtimeIssues.append(issue)
    }
    preferences[RuntimeIssuePreferenceKey.self] = runtimeIssues
    node.preferenceValues = preferences
    return node
  }

  private func resolvedItems(
    in context: ResolveContext
  ) -> ResolvedItems {
    let nodes = resolveDeclaredChildren(
      content,
      in: context.settingEnvironment(\.isResolvingHostedCollectionContent, to: true),
      kindName: "ListContent"
    )
    var result = ResolvedItems()
    var hasEmittedSection = false
    var previousSectionBottomVisibility: Visibility?
    collectTopLevelItems(
      from: nodes,
      into: &result,
      hasEmittedSection: &hasEmittedSection,
      previousSectionBottomVisibility: &previousSectionBottomVisibility
    )
    return result
  }

  private func resolvedIndexedItems(
    from source: any IndexedChildSource,
    in context: ResolveContext
  ) -> ResolvedItems {
    var result = ResolvedItems()
    result.items.reserveCapacity(source.count)
    result.rows.reserveCapacity(source.count)
    for index in 0..<source.count {
      let candidateTag = source.elementSelectionTag(at: index)
      let compatibleTag = candidateTag.flatMap { tag in
        selectionPolicy.isSelectable && selectionPolicy.value(from: tag) != nil ? tag : nil
      }
      result.items.append(.init(kind: .row, text: ""))
      result.rows.append(
        .init(
          tag: compatibleTag,
          identity: source.elementIdentity(at: index)
        )
      )
    }

    let policy = selectionPolicy
    result.indexedSource = HostedCollectionIndexedChildSource(base: source) { rawNode, index in
      var node = rawNode
      let row = resolvedHostedListRow(from: node)
      let compatibleTag = row.tag.flatMap { tag in
        policy.isSelectable && policy.value(from: tag) != nil ? tag : nil
      }
      node = applyingHostedRowForegroundStyle(
        row.drawMetadata.listStyle?.rowForegroundStyle,
        to: node
      )
      node.semanticMetadata.hostedCollectionItem = .init(
        role: .listRow(rowIndex: index),
        isSelectable: compatibleTag != nil
      )
      return node
    }
    return result
  }

  private func collectTopLevelItems(
    from nodes: [ResolvedNode],
    into result: inout ResolvedItems,
    hasEmittedSection: inout Bool,
    previousSectionBottomVisibility: inout Visibility?
  ) {
    for var node in nodes {
      if node.semanticMetadata.sectionRole == .section {
        if hasEmittedSection, !result.items.isEmpty {
          result.items.append(
            .init(
              kind: .sectionBreak,
              text: "",
              sectionSeparators: .init(
                top: node.drawMetadata.listStyle?.sectionSeparatorTopVisibility,
                bottom: previousSectionBottomVisibility
              )
            )
          )
          var breakMetadata = SemanticMetadata(isFocusable: false)
          breakMetadata.hostedCollectionItem = .init(role: .listSectionBreak)
          result.children.append(
            ResolvedNode(
              identity: node.identity.child(.named("ListSectionBreak")),
              kind: .view("ListSectionBreak"),
              environmentSnapshot: node.environmentSnapshot,
              transactionSnapshot: node.transactionSnapshot,
              semanticMetadata: breakMetadata,
              intrinsicSize: .init(width: 1, height: 1)
            )
          )
        }
        collectSection(node, into: &result)
        previousSectionBottomVisibility =
          node.drawMetadata.listStyle?.sectionSeparatorBottomVisibility
        hasEmittedSection = true
      } else if containsHostedCollectionRowBoundary(node) {
        collectItems(from: [node], into: &result)
      } else {
        appendRow(node: &node, to: &result)
      }
    }
  }

  private func collectSection(
    _ node: ResolvedNode,
    into result: inout ResolvedItems
  ) {
    for var child in node.children {
      switch child.semanticMetadata.sectionRole {
      case .header:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          result.items.append(
            .init(
              kind: .header,
              text: label,
              style: listItemTextStyle(from: child.drawMetadata)
            )
          )
          child.semanticMetadata.hostedCollectionItem = .init(role: .listHeader)
          result.children.append(child)
        }
      case .footer:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          result.items.append(
            .init(
              kind: .footer,
              text: label,
              style: listItemTextStyle(from: child.drawMetadata)
            )
          )
          child.semanticMetadata.hostedCollectionItem = .init(role: .listFooter)
          result.children.append(child)
        }
      default:
        collectItems(from: child.children, into: &result)
      }
    }
  }

  private func collectItems(
    from nodes: [ResolvedNode],
    into result: inout ResolvedItems
  ) {
    for var node in nodes {
      if node.semanticMetadata.isHostedCollectionRowBoundary {
        appendRow(node: &node, to: &result)
        continue
      }
      if containsHostedCollectionRowBoundary(node) {
        collectItems(from: node.children, into: &result)
        continue
      }
      let row = resolvedHostedListRow(from: node)
      if row.tagCount > 0 || node.children.isEmpty {
        appendRow(node: &node, row: row, to: &result)
      } else {
        collectItems(from: node.children, into: &result)
      }
    }
  }

  private func containsHostedCollectionRowBoundary(_ node: ResolvedNode) -> Bool {
    node.semanticMetadata.isHostedCollectionRowBoundary
      || node.children.contains(where: containsHostedCollectionRowBoundary)
  }

  private func appendRow(
    node: inout ResolvedNode,
    to result: inout ResolvedItems
  ) {
    appendRow(node: &node, row: resolvedHostedListRow(from: node), to: &result)
  }

  private func appendRow(
    node: inout ResolvedNode,
    row: ResolvedListRow,
    to result: inout ResolvedItems
  ) {
    let rowIndex = result.rows.count
    let compatibleTag = row.tag.flatMap { tag in
      selectionPolicy.value(from: tag) == nil ? nil : tag
    }
    result.items.append(listItemPayload(from: row))
    result.rows.append(.init(tag: compatibleTag, identity: node.identity))
    node = applyingHostedRowForegroundStyle(
      row.drawMetadata.listStyle?.rowForegroundStyle,
      to: node
    )
    node.semanticMetadata.hostedCollectionItem = .init(
      role: .listRow(rowIndex: rowIndex),
      isSelectable: compatibleTag != nil
    )
    result.children.append(node)

    let issue: RuntimeIssue?
    if !selectionPolicy.isSelectable {
      issue = nil
    } else if row.tagCount == 0 {
      issue = RuntimeIssue(
        severity: .warning,
        code: "collection.missingSelectionTag",
        message:
          "Selectable List row has no selection tag; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else if row.tagCount > 1 {
      issue = RuntimeIssue(
        severity: .error,
        code: "collection.ambiguousSelectionTag",
        message:
          "Selectable List row has \(row.tagCount) selection tags; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else if compatibleTag == nil {
      issue = RuntimeIssue(
        severity: .warning,
        code: "collection.incompatibleSelectionTag",
        message:
          "Selectable List row has a tag incompatible with the selection value type; the row remains visible but is not selectable.",
        identity: node.identity,
        source: "List"
      )
    } else {
      issue = nil
    }
    if let issue, !result.runtimeIssues.contains(issue) {
      result.runtimeIssues.append(issue)
    }
  }
}
