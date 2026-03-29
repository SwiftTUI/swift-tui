import Core

/// Groups related collection content with optional header and footer content.
public struct Section: View, ResolvableView {
  private var headerViews: [AnyView]
  private var footerViews: [AnyView]
  private var contentViews: [AnyView]

  public init<Content: View, Header: View, Footer: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header,
    @ViewBuilder footer: () -> Footer
  ) {
    headerViews = parallelBuilderChildren(from: header())
    footerViews = parallelBuilderChildren(from: footer())
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<Content: View, Header: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Header
  ) {
    headerViews = parallelBuilderChildren(from: header())
    footerViews = []
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    @ViewBuilder content: () -> Content
  ) {
    headerViews = [AnyView(Text(String(title)))]
    footerViews = []
    contentViews = parallelBuilderChildren(from: content())
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

    if !headerViews.isEmpty {
      children.append(
        sectionChild(
          in: context,
          component: "Header",
          role: .header,
          views: headerViews
        )
      )
    }

    children.append(
      sectionChild(
        in: context,
        component: "Content",
        role: .content,
        views: contentViews
      )
    )

    if !footerViews.isEmpty {
      children.append(
        sectionChild(
          in: context,
          component: "Footer",
          role: .footer,
          views: footerViews
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

  private func sectionChild(
    in context: ResolveContext,
    component: String,
    role: SectionRole,
    views: [AnyView]
  ) -> ResolvedNode {
    let childContext = context.child(component: component)
    return ResolvedNode(
      identity: childContext.identity,
      kind: .view("Section\(component)"),
      children: combinedView(from: views, kindName: "Section\(component)")
        .resolveElements(in: childContext.child(component: "Views")),
      environmentSnapshot: childContext.environment,
      transactionSnapshot: childContext.transaction,
      semanticMetadata: .init(sectionRole: role)
    )
  }
}

/// Presents selectable rows in a vertically scrollable list.
public struct List<SelectionValue: Hashable>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  private var contentViews: [AnyView]

  public init<Content: View>(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    contentViews = parallelBuilderChildren(from: content())
  }

  package init(
    selection: Binding<SelectionValue>,
    contentViews: [AnyView]
  ) {
    self.selection = selection
    self.contentViews = contentViews
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

/// Declares the cell content for a row in a ``Table``.
public struct TableRow: View, ResolvableView {
  private var contentViews: [AnyView]

  public init<Content: View>(
    @ViewBuilder content: () -> Content
  ) {
    contentViews = parallelBuilderChildren(from: content())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension TableRow {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    return ResolvedNode(
      identity: context.identity,
      kind: .view("TableRow"),
      children: contentViews.enumerated().flatMap { index, view in
        view.resolveElements(
          in: context.indexedChild(kind: "Cell", index: index)
        )
      },
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: .init(presentationRole: .tableRow)
    )
  }
}

extension List {
  private struct RowSelection: Sendable {
    var tag: SelectionTag
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let listStyle =
      context.environmentValues.listStyle == .automatic
      ? ListStyle.insetGrouped
      : context.environmentValues.listStyle
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility != .hidden
    let resolvedContent = resolvedItems(in: context.child(component: "ListItems"))
    let rows = resolvedContent.rows
    let selectedIndex = rows.firstIndex { row in
      pickerSelectionMatches(
        row.tag,
        selection: selection.wrappedValue
      )
    }
    let chrome = context.environmentValues.terminalAppearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let rowChrome = context.environmentValues.terminalAppearance.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled {
      let binding = selection
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
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

        return stepBoundSelection(
          binding,
          orderedTags: rows.map(\.tag),
          delta: delta
        )
      }

      let rootRouteID = parallelPrimaryRouteID(for: context.identity)
      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: rows.map(\.tag),
            delta: delta
          )
        }
      }

      for (rowIndex, row) in rows.enumerated() {
        let routeID = parallelPrimaryRouteID(
          for: parallelListRowIdentity(
            for: context.identity,
            rowIndex: rowIndex
          )
        )
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withDynamicPropertyScope(dynamicPropertyScope) {
            setBoundSelection(binding, to: row.tag)
          }
        }
      }
    }

    let payload = ListPayload(
      items: resolvedContent.items,
      selectedRowIndex: selectedIndex,
      style: listStyle,
      foregroundStyle: chrome.foregroundStyle,
      backgroundStyle: chrome.backgroundStyle,
      borderStyle: chrome.borderStyle,
      selectedRowForegroundStyle: isFocused && showsFocusEffect ? rowChrome.foregroundStyle : nil,
      selectedRowBackgroundStyle: isFocused && showsFocusEffect ? rowChrome.backgroundStyle : nil,
      selectedRowMarkerStyle: isFocused && showsFocusEffect ? rowChrome.borderStyle : nil,
      showsSelectionMarker: isFocused && showsFocusEffect && !rows.isEmpty,
      showsIndicators: showsIndicators,
      opacity: chrome.opacity
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("List"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
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
    let nodes = combinedView(from: contentViews, kindName: "ListContent")
      .resolveElements(in: context)

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
      } else if let row = parallelResolvedListRow(from: node) {
        items.append(parallelListItemPayload(from: row))
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
        let label = parallelNodeLabelText(from: child)
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
        let label = parallelNodeLabelText(from: child)
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
      if let row = parallelResolvedListRow(from: node) {
        items.append(parallelListItemPayload(from: row))
        rows.append(.init(tag: row.tag))
      } else {
        collectItems(from: node.children, into: &items, rows: &rows)
      }
    }
  }
}

/// Presents row and column data in a terminal table.
public struct Table<SelectionValue: Hashable>: View, ResolvableView {
  public var columns: [TableColumn]
  private var selection: Binding<SelectionValue>?
  private var rowViews: [AnyView]

  public init<Rows: View>(
    selection: Binding<SelectionValue>,
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) {
    self.columns = columns
    self.selection = selection
    rowViews = parallelBuilderChildren(from: rows())
  }

  public init<Rows: View>(
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) where SelectionValue == Never {
    self.columns = columns
    selection = nil
    rowViews = parallelBuilderChildren(from: rows())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Table {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isSelectable = selection != nil
    let tableStyle =
      context.environmentValues.listStyle == .insetGrouped
      ? ListStyle.insetGrouped
      : ListStyle.plain
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility != .hidden
    let showsHeaders =
      context.environmentValues.tableHeaderVisibility != .hidden
    let resolvedColumns = columns.map(\.parallelTableColumnPayload)
    let resolvedRows = resolvedRows(in: context.child(component: "TableRows"))
    let selectableRowIndices = resolvedRows.indices.filter { index in
      resolvedRows[index].tag != nil
    }
    let selectedIndex: Int? =
      if let selection {
        resolvedRows.firstIndex { row in
          guard let tag = row.tag else {
            return false
          }
          return pickerSelectionMatches(tag, selection: selection.wrappedValue)
        }
      } else { nil }
    let chrome = context.environmentValues.terminalAppearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let rowChrome = context.environmentValues.terminalAppearance.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled, let selection {
      let binding = selection
      let dynamicPropertyScope = currentDynamicPropertyScope()
      let selectableTags = selectableRowIndices.compactMap { rowIndex in
        resolvedRows[rowIndex].tag
      }
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
        let delta: Int?
        switch event {
        case .arrowUp:
          delta = -1
        case .arrowDown:
          delta = 1
        default:
          delta = nil
        }

        guard let delta, !resolvedRows.isEmpty else {
          return false
        }

        return stepBoundSelection(
          binding,
          orderedTags: selectableTags,
          delta: delta
        )
      }

      let rootRouteID = parallelPrimaryRouteID(for: context.identity)
      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: selectableTags,
            delta: delta
          )
        }
      }

      for rowIndex in selectableRowIndices {
        guard let tag = resolvedRows[rowIndex].tag else {
          continue
        }

        let routeID = parallelPrimaryRouteID(
          for: parallelTableRowIdentity(
            for: context.identity,
            rowIndex: rowIndex
          )
        )
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withDynamicPropertyScope(dynamicPropertyScope) {
            setBoundSelection(binding, to: tag)
          }
        }
      }
    }

    let payload = TablePayload(
      columns: resolvedColumns,
      rows: resolvedRows,
      selectedRowIndex: selectedIndex,
      style: tableStyle,
      foregroundStyle: chrome.foregroundStyle,
      backgroundStyle: chrome.backgroundStyle,
      borderStyle: chrome.borderStyle,
      selectedRowForegroundStyle: isFocused && showsFocusEffect ? rowChrome.foregroundStyle : nil,
      selectedRowBackgroundStyle: isFocused && showsFocusEffect ? rowChrome.backgroundStyle : nil,
      selectedRowMarkerStyle: isFocused && showsFocusEffect ? rowChrome.borderStyle : nil,
      showsHeaders: showsHeaders,
      showsSelectionMarker: isSelectable && isFocused && showsFocusEffect,
      showsIndicators: showsIndicators,
      opacity: chrome.opacity
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Table"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        isFocusable: isSelectable ? nil : false,
        focusInteractions: isSelectable ? .edit : .automatic,
        scrollRole: .table,
        presentationRole: .table
      ),
      drawPayload: .table(payload)
    )
  }

  private func resolvedRows(
    in context: ResolveContext
  ) -> [TableRowPayload] {
    let nodes = combinedView(from: rowViews, kindName: "TableContent")
      .resolveElements(in: context)
    var rows: [TableRowPayload] = []
    collectTableRows(from: nodes, into: &rows)
    return rows
  }

  private func collectTableRows(
    from nodes: [ResolvedNode],
    into rows: inout [TableRowPayload]
  ) {
    for node in nodes {
      if node.semanticMetadata.presentationRole == .tableRow {
        rows.append(
          .init(
            tag: node.semanticMetadata.selectionTag,
            cells: tableRowCellPayloads(from: node),
            style: listItemTextStyle(from: node.drawMetadata),
            rowForegroundStyle: node.drawMetadata.listStyle?.rowForegroundStyle,
            rowBackgroundStyle: node.drawMetadata.listStyle?.rowBackgroundStyle,
            rowSeparators: .init(
              top: node.drawMetadata.listStyle?.rowSeparatorTopVisibility,
              bottom: node.drawMetadata.listStyle?.rowSeparatorBottomVisibility
            )
          )
        )
      } else {
        collectTableRows(from: node.children, into: &rows)
      }
    }
  }
}

extension TableColumnAlignment {
  fileprivate var parallelTableCellAlignment: TableCellAlignment {
    if self == .center {
      return .center
    }
    if self == .trailing {
      return .trailing
    }
    return .leading
  }
}

extension TableColumn {
  fileprivate var parallelTableColumnPayload: TableColumnPayload {
    .init(
      title: title,
      width: width,
      alignment: alignment.parallelTableCellAlignment,
      titleAlignment: titleAlignment.parallelTableCellAlignment
    )
  }
}
