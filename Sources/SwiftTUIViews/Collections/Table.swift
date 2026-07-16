@_spi(Testing) import SwiftTUICore

/// Declares the cell content for a row in a ``Table``.
public struct TableRow<Content: View>: PrimitiveView, ResolvableView {
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
      semanticMetadata: .init(accessibilityRole: .tableRow)
    )
  }
}

/// Presents row and column data in a terminal table.
public struct Table<SelectionValue: Hashable, Rows: View>: PrimitiveView, ResolvableView {
  public var columns: [TableColumn]
  private var selectionPolicy: CollectionSelectionPolicy<SelectionValue>
  private var rows: Rows
  package var usesIndexedDataSource = false

  @_disfavoredOverload
  public init(
    selection: Binding<SelectionValue>,
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) {
    self.columns = columns
    selectionPolicy = .requiredSingle(selection)
    self.rows = rows()
  }

  public init(
    selection: Binding<SelectionValue?>,
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) {
    self.columns = columns
    selectionPolicy = .optionalSingle(selection)
    self.rows = rows()
  }

  public init(
    selection: Binding<Set<SelectionValue>>,
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) {
    self.columns = columns
    selectionPolicy = .multiple(selection)
    self.rows = rows()
  }

  public init(
    columns: [TableColumn],
    @ViewBuilder rows: () -> Rows
  ) where SelectionValue == Never {
    self.columns = columns
    selectionPolicy = .none
    self.rows = rows()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Table {
  private struct ResolvedRows {
    var payloads: [TableRowPayload] = []
    var children: [ResolvedNode] = []
    var runtimeIssues: [RuntimeIssue] = []
    var indexedSource: (any IndexedChildSource)?
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isSelectable = selectionPolicy.isSelectable
    let tableStyle = context.environmentValues.listStyle.presentation
    let showsIndicators =
      context.environmentValues.scrollIndicatorVisibility != .hidden
    let showsHeaders =
      context.environmentValues.tableHeaderVisibility != .hidden
    let resolvedColumns = columns.map(\.resolvedTableColumnPayload)
    let rowContext = context.child(component: .named("TableRows"))
    var resolvedContent: ResolvedRows
    if usesIndexedDataSource, let source = makeIndexedChildSource(from: rows, in: rowContext) {
      resolvedContent = resolvedIndexedRows(
        from: source,
        in: context,
        columns: resolvedColumns,
        tableStyle: tableStyle
      )
    } else {
      resolvedContent = resolvedRows(in: rowContext)
    }
    let resolvedRows = resolvedContent.payloads
    if resolvedContent.indexedSource == nil {
      resolvedContent.children = hostedTableRowNodes(
        resolvedContent.children,
        columns: resolvedColumns,
        rows: resolvedRows,
        joinGlyph: tableStyle.tableBorderGlyphs.columnJoin
      )
    }
    let selectableRowIndices = resolvedRows.indices.filter { index in
      guard let tag = resolvedRows[index].tag else {
        return false
      }
      return pickerSelectionValue(from: tag, as: SelectionValue.self) != nil
    }
    let selectedIndex = resolvedRows.firstIndex { row in
      row.tag.map(selectionPolicy.contains) == true
    }
    let chrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let rowChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: true
    )

    if isEnabled, selectionPolicy.isSelectable {
      let policy = selectionPolicy
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: nil
      )
      let selectableTags = selectableRowIndices.compactMap { rowIndex in
        resolvedRows[rowIndex].tag
      }
      intake.registerKeyHandler(identity: context.identity) { event in
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

        return policy.step(orderedTags: selectableTags, delta: delta)
      }

      let rootRouteID = runtimePrimaryRouteID(for: context.identity)
      intake.registerPointerHandler(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return policy.step(orderedTags: selectableTags, delta: delta)
      }

      let interactionIndices: any Sequence<Int> =
        if resolvedContent.indexedSource == nil {
          selectableRowIndices
        } else {
          collectionInteractionIndices(count: resolvedRows.count, anchor: selectedIndex)
        }
      for rowIndex in interactionIndices {
        guard let tag = resolvedRows[rowIndex].tag else {
          continue
        }

        let routeID = runtimePrimaryRouteID(
          for: tableRowIdentity(
            for: context.identity,
            rowIndex: rowIndex
          )
        )
        intake.registerPointerHandler(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return policy.isMultiple ? policy.toggle(tag) : policy.select(tag)
        }
      }
    }

    var payload = TablePayload(
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
    payload.isViewportBacked = resolvedContent.indexedSource != nil

    var metadata = focusableControlMetadata(
      isFocusable: isSelectable ? nil : false,
      focusInteractions: isSelectable ? .edit : .automatic,
      scrollRole: .table,
      accessibilityRole: .table
    )
    metadata.hostedCollectionContainer = .init(kind: .table)
    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("Table"),
      children: resolvedContent.children,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: metadata,
      drawPayload: .table(payload),
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

  private func hostedTableRowNodes(
    _ rows: [ResolvedNode],
    columns: [TableColumnPayload],
    rows payloads: [TableRowPayload],
    joinGlyph: String
  ) -> [ResolvedNode] {
    let widths = measureTableColumnWidths(columns: columns, rows: payloads)
    let joinWidth = layoutText(
      for: columns.isEmpty ? "" : joinGlyph,
      width: nil
    ).size.width

    return rows.map { row in
      var row = row
      row.children = row.children.enumerated().map { index, cell in
        let cell = singleLineHostedTableCell(cell)
        let width = widths.indices.contains(index) ? widths[index] : 1
        let alignment =
          columns.indices.contains(index)
          ? hostedCellAlignment(columns[index].alignment)
          : Alignment.leading
        var hostedCell = ResolvedNode(
          identity: row.identity.child(.indexed("HostedTableCell", index: index)),
          kind: .view("HostedTableCell"),
          children: [cell],
          environmentSnapshot: cell.environmentSnapshot,
          transactionSnapshot: cell.transactionSnapshot,
          layoutBehavior: .frame(width: width, height: nil, alignment: alignment),
          semanticMetadata: .init(isFocusable: false)
        )
        hostedCell.drawMetadata.clipsToBounds = true
        return hostedCell
      }
      row.layoutBehavior = .stack(
        axis: .horizontal,
        spacing: 2 + joinWidth,
        horizontalAlignment: .leading,
        verticalAlignment: .center
      )
      return row
    }
  }

  private func hostedCellAlignment(_ alignment: TableCellAlignment) -> Alignment {
    switch alignment {
    case .leading:
      return .leading
    case .center:
      return .center
    case .trailing:
      return .trailing
    }
  }

  private func singleLineHostedTableCell(_ source: ResolvedNode) -> ResolvedNode {
    var node = source
    node.layoutMetadata.lineLimit = 1
    node.layoutMetadata.textTruncationMode = .tail
    node.children = node.children.map(singleLineHostedTableCell)
    return node
  }

  private func resolvedRows(
    in context: ResolveContext
  ) -> ResolvedRows {
    let nodes = resolveDeclaredChildren(
      rows,
      in: context,
      kindName: "TableContent"
    )
    var result = ResolvedRows()
    collectTableRows(from: nodes, into: &result)
    return result
  }

  private func resolvedIndexedRows(
    from source: any IndexedChildSource,
    in context: ResolveContext,
    columns: [TableColumnPayload],
    tableStyle: CollectionStylePresentation
  ) -> ResolvedRows {
    var result = ResolvedRows()
    result.payloads.reserveCapacity(source.count)
    for index in 0..<source.count {
      let candidateTag = source.elementSelectionTag(at: index)
      let compatibleTag = candidateTag.flatMap { tag in
        selectionPolicy.isSelectable && selectionPolicy.value(from: tag) != nil ? tag : nil
      }
      result.payloads.append(
        .init(
          tag: compatibleTag,
          cells: columns.map { _ in .init(text: "") }
        )
      )
    }

    let policy = selectionPolicy
    result.indexedSource = HostedCollectionIndexedChildSource(base: source) { rawNode, index in
      var node = rawNode
      node.semanticMetadata.accessibilityRole = nil
      let tag = node.semanticMetadata.selectionTag
      let compatibleTag = tag.flatMap { tag in
        policy.isSelectable && policy.value(from: tag) != nil ? tag : nil
      }
      let rowPayload = TableRowPayload(
        tag: compatibleTag,
        cells: tableRowCellPayloads(from: node),
        style: listItemTextStyle(from: node.drawMetadata),
        rowForegroundStyle: node.drawMetadata.listStyle?.rowForegroundStyle,
        rowBackgroundStyle: node.drawMetadata.listStyle?.rowBackgroundStyle,
        rowSeparators: .init(
          top: node.drawMetadata.listStyle?.rowSeparatorTopVisibility,
          bottom: node.drawMetadata.listStyle?.rowSeparatorBottomVisibility
        )
      )
      node = applyingHostedRowForegroundStyle(
        node.drawMetadata.listStyle?.rowForegroundStyle,
        to: node
      )
      node.semanticMetadata.hostedCollectionItem = .init(
        role: .tableRow(rowIndex: index),
        isSelectable: compatibleTag != nil
      )
      node =
        hostedTableRowNodes(
          [node],
          columns: columns,
          rows: [rowPayload],
          joinGlyph: tableStyle.tableBorderGlyphs.columnJoin
        )[0]
      return node
    }
    return result
  }

  private func collectTableRows(
    from nodes: [ResolvedNode],
    into result: inout ResolvedRows
  ) {
    for var node in nodes {
      if node.semanticMetadata.accessibilityRole == .tableRow {
        // TableRow is a structural host. Nested cell content contributes its
        // own accessibility normally; the table container owns the table role
        // and row-background selection remains a separate fallback route.
        node.semanticMetadata.accessibilityRole = nil
        let rowIndex = result.payloads.count
        let tag = node.semanticMetadata.selectionTag
        let compatibleTag = tag.flatMap { tag in
          selectionPolicy.value(from: tag) == nil ? nil : tag
        }
        result.payloads.append(
          .init(
            tag: compatibleTag,
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
        node = applyingHostedRowForegroundStyle(
          node.drawMetadata.listStyle?.rowForegroundStyle,
          to: node
        )
        node.semanticMetadata.hostedCollectionItem = .init(
          role: .tableRow(rowIndex: rowIndex),
          isSelectable: compatibleTag != nil
        )
        result.children.append(node)

        guard selectionPolicy.isSelectable else {
          continue
        }
        let issue: RuntimeIssue?
        if tag == nil {
          issue = RuntimeIssue(
            severity: .warning,
            code: "collection.missingSelectionTag",
            message:
              "Selectable Table row has no selection tag; the row remains visible but is not selectable.",
            identity: node.identity,
            source: "Table"
          )
        } else if compatibleTag == nil {
          issue = RuntimeIssue(
            severity: .warning,
            code: "collection.incompatibleSelectionTag",
            message:
              "Selectable Table row has a tag incompatible with the selection value type; the row remains visible but is not selectable.",
            identity: node.identity,
            source: "Table"
          )
        } else {
          issue = nil
        }
        if let issue, !result.runtimeIssues.contains(issue) {
          result.runtimeIssues.append(issue)
        }
      } else {
        collectTableRows(from: node.children, into: &result)
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
