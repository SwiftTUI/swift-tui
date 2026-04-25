package import Core

/// Groups related collection content with optional header and footer content.
public struct Section<Content: View, Header: View, Footer: View>: View,
  ResolvableView
{
  private var showsHeader: Bool
  private var showsFooter: Bool
  private var header: Header
  private var footer: Footer
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header,
    @ViewBuilder footer: () -> Footer
  ) {
    showsHeader = true
    showsFooter = true
    self.header = header()
    self.footer = footer()
    self.content = content()
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header
  ) where Footer == EmptyView {
    showsHeader = true
    showsFooter = false
    self.header = header()
    footer = EmptyView()
    self.content = content()
  }

  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) where Header == Text, Footer == EmptyView {
    showsHeader = true
    showsFooter = false
    header = Text(String(title))
    footer = EmptyView()
    self.content = content()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Section {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    var children: [ResolvedNode] = []

    if showsHeader {
      children.append(
        sectionChild(
          in: context,
          component: .named("Header"),
          role: .header,
          view: header
        )
      )
    }

    children.append(
      sectionChild(
        in: context,
        component: .named("Content"),
        role: .content,
        view: content
      )
    )

    if showsFooter {
      children.append(
        sectionChild(
          in: context,
          component: .named("Footer"),
          role: .footer,
          view: footer
        )
      )
    }

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Section"),
      children: children,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: .init(
        sectionRole: .section,
        presentationRole: .section
      )
    )
  }

  private func sectionChild<ViewContent: View>(
    in context: ResolveContext,
    component: IdentityComponent,
    role: SectionRole,
    view: ViewContent
  ) -> ResolvedNode {
    let childContext = context.child(component: component)
    return ResolvedNode(
      identity: childContext.identity,
      kind: .view("Section\(component.rawValue)"),
      children: resolveDeclaredChildren(
        view,
        in: childContext.child(component: .named("Views")),
        kindName: "Section\(component.rawValue)"
      ),
      environmentSnapshot: childContext.environment,
      transactionSnapshot: childContext.transaction,
      semanticMetadata: .init(sectionRole: role)
    )
  }
}

/// Presents selectable rows in a vertically scrollable list.
public struct List<SelectionValue: Hashable, Content: View>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  private var onActivate: (@MainActor (SelectionValue) -> Void)?
  private var content: Content

  public init(
    selection: Binding<SelectionValue>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    self.onActivate = onActivate
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
    var tag: SelectionTag
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
    let resolvedContent = resolvedItems(in: context.child(component: .named("ListItems")))
    let rows = resolvedContent.rows
    let selectedIndex = rows.firstIndex { row in
      pickerSelectionMatches(
        row.tag,
        selection: selection.wrappedValue
      )
    }
    let focusedRowIndex = rows.indices.first { rowIndex in
      context.environmentValues.focusedIdentity
        == listRowIdentity(
          for: context.identity,
          rowIndex: rowIndex
        )
    }
    let isListOrRowFocused = isFocused || focusedRowIndex != nil
    let activeRowIndex = focusedRowIndex ?? selectedIndex
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isListOrRowFocused && showsFocusEffect
    )
    let rowChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isListOrRowFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled {
      let binding = selection
      let dynamicPropertyScope = currentAuthoringContext()
      let activate: @MainActor (SelectionTag) -> Bool = { tag in
        guard let value = pickerSelectionValue(from: tag, as: SelectionValue.self) else {
          return false
        }
        if binding.wrappedValue != value {
          binding.wrappedValue = value
        }
        onActivate?(value)
        return true
      }
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
        let delta: Int?
        switch event {
        case .arrowUp:
          delta = -1
        case .arrowDown:
          delta = 1
        case .return, .space:
          guard let selectedIndex, rows.indices.contains(selectedIndex) else {
            return false
          }
          return withAuthoringContext(dynamicPropertyScope) {
            activate(rows[selectedIndex].tag)
          }
        default:
          delta = nil
        }

        guard let delta, !rows.isEmpty else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: rows.map(\.tag),
            delta: delta
          )
        }
      }

      let rootRouteID = primaryRouteID(for: context.identity)
      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withAuthoringContext(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: rows.map(\.tag),
            delta: delta
          )
        }
      }

      for (rowIndex, row) in rows.enumerated() {
        let rowIdentity = listRowIdentity(
          for: context.identity,
          rowIndex: rowIndex
        )
        context.localActionRegistry?.register(
          identity: rowIdentity,
          handler: {
            withAuthoringContext(dynamicPropertyScope) {
              activate(row.tag)
            }
          },
          followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
        )
        context.localKeyHandlerRegistry?.register(identity: rowIdentity) { event in
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
          _ = withAuthoringContext(dynamicPropertyScope) {
            setBoundSelection(binding, to: rows[targetIndex].tag)
          }
          return false
        }
      }
    }

    let payload = ListPayload(
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
      showsSelectionMarker: isListOrRowFocused && showsFocusEffect && !rows.isEmpty,
      showsIndicators: showsIndicators,
      opacity: chrome.opacity
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("List"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        isFocusable: rows.isEmpty ? nil : false,
        focusInteractions: .edit,
        scrollRole: .list,
        presentationRole: .list
      ),
      drawPayload: .list(payload)
    )
  }

  private func resolvedItems(
    in context: ResolveContext
  ) -> (items: [ListItemPayload], rows: [RowSelection]) {
    let nodes = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "ListContent"
    )

    var items: [ListItemPayload] = []
    var rows: [RowSelection] = []
    var hasEmittedSection = false
    var previousSectionBottomVisibility: Visibility?
    collectTopLevelItems(
      from: nodes,
      into: &items,
      rows: &rows,
      hasEmittedSection: &hasEmittedSection,
      previousSectionBottomVisibility: &previousSectionBottomVisibility
    )
    return (items, rows)
  }

  private func collectTopLevelItems(
    from nodes: [ResolvedNode],
    into items: inout [ListItemPayload],
    rows: inout [RowSelection],
    hasEmittedSection: inout Bool,
    previousSectionBottomVisibility: inout Visibility?
  ) {
    for node in nodes {
      if node.semanticMetadata.sectionRole == .section {
        if hasEmittedSection, !items.isEmpty {
          items.append(
            .init(
              kind: .sectionBreak,
              text: "",
              sectionSeparators: .init(
                top: node.drawMetadata.listStyle?.sectionSeparatorTopVisibility,
                bottom: previousSectionBottomVisibility
              )
            )
          )
        }
        collectSection(node, into: &items, rows: &rows)
        previousSectionBottomVisibility =
          node.drawMetadata.listStyle?.sectionSeparatorBottomVisibility
        hasEmittedSection = true
      } else if let row = resolvedListRow(from: node) {
        items.append(listItemPayload(from: row))
        rows.append(.init(tag: row.tag))
      } else {
        collectTopLevelItems(
          from: node.children,
          into: &items,
          rows: &rows,
          hasEmittedSection: &hasEmittedSection,
          previousSectionBottomVisibility: &previousSectionBottomVisibility
        )
      }
    }
  }

  private func collectSection(
    _ node: ResolvedNode,
    into items: inout [ListItemPayload],
    rows: inout [RowSelection]
  ) {
    for child in node.children {
      switch child.semanticMetadata.sectionRole {
      case .header:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          items.append(
            .init(
              kind: .header,
              text: label,
              style: listItemTextStyle(from: child.drawMetadata)
            )
          )
        }
      case .footer:
        let label = resolvedNodeLabelText(from: child)
        if !label.isEmpty {
          items.append(
            .init(
              kind: .footer,
              text: label,
              style: listItemTextStyle(from: child.drawMetadata)
            )
          )
        }
      default:
        collectItems(from: child.children, into: &items, rows: &rows)
      }
    }
  }

  private func collectItems(
    from nodes: [ResolvedNode],
    into items: inout [ListItemPayload],
    rows: inout [RowSelection]
  ) {
    for node in nodes {
      if let row = resolvedListRow(from: node) {
        items.append(listItemPayload(from: row))
        rows.append(.init(tag: row.tag))
      } else {
        collectItems(from: node.children, into: &items, rows: &rows)
      }
    }
  }
}
