package import Core

/// Declares the cell content for a row in a ``Table``.
public struct TableRow<Content: View>: View, ResolvableView {
  private var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
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
      children: resolveDeclaredChildren(
        content,
        in: context,
        kindName: "Cell"
      ),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: .init(presentationRole: .tableRow)
    )
  }
}

/// Presents row and column data in a terminal table.
public struct Table<SelectionValue: Hashable, Rows: View>: View, ResolvableView {
  public var columns: [TableColumn]
  private var selection: Binding<SelectionValue>?
  private var rows: Rows

  public init(
    selection: Binding<SelectionValue>,
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) {
    self.columns = columns
    self.selection = selection
    self.rows = rows()
  }

  public init(
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) where SelectionValue == Never {
    self.columns = columns
    selection = nil
    self.rows = rows()
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
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isSelectable = selection != nil
    let tableStyle =
      context.environmentValues.listStyle == .plain
      ? ListStyle.plain
      : ListStyle.insetGrouped
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility != .hidden
    let showsHeaders =
      context.environmentValues.tableHeaderVisibility != .hidden
    let resolvedColumns = columns.map(\.resolvedTableColumnPayload)
    let resolvedRows = resolvedRows(in: context.child(component: .named("TableRows")))
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
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let rowChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled, let selection {
      let binding = selection
      let dynamicPropertyScope = currentAuthoringContext()
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

        return withAuthoringContext(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: selectableTags,
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
            orderedTags: selectableTags,
            delta: delta
          )
        }
      }

      for rowIndex in selectableRowIndices {
        guard let tag = resolvedRows[rowIndex].tag else {
          continue
        }

        let routeID = primaryRouteID(
          for: tableRowIdentity(
            for: context.identity,
            rowIndex: rowIndex
          )
        )
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withAuthoringContext(dynamicPropertyScope) {
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
      semanticMetadata: focusableControlMetadata(
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
    let nodes = resolveDeclaredChildren(
      rows,
      in: context,
      kindName: "TableContent"
    )
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
  fileprivate var resolvedTableCellAlignment: TableCellAlignment {
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
  fileprivate var resolvedTableColumnPayload: TableColumnPayload {
    .init(
      title: title,
      width: width,
      alignment: alignment.resolvedTableCellAlignment,
      titleAlignment: titleAlignment.resolvedTableCellAlignment
    )
  }
}
