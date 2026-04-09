import Core

func resolvedNodeLabelText(
  from node: ResolvedNode
) -> String {
  collectedNodeTextParts(from: node)
    .joined(separator: " ")
    .trimmedUnicodeWhitespace()
}

func listItemTextStyle(
  from metadata: DrawMetadata
) -> TextStyle {
  TextStyle(
    foregroundStyle: metadata.foregroundStyle,
    backgroundStyle: metadata.backgroundStyle,
    emphasis: metadata.emphasis,
    underlineStyle: metadata.underlineStyle,
    strikethroughStyle: metadata.strikethroughStyle,
    opacity: metadata.opacity
  )
}

func collectedNodeTextParts(
  from node: ResolvedNode
) -> [String] {
  var parts: [String] = []
  if case .text(let content) = node.drawPayload, !content.isEmpty {
    parts.append(content)
  }
  if case .textFigure(let payload) = node.drawPayload, !payload.content.isEmpty {
    parts.append(payload.content)
  }
  if case .richText(let payload) = node.drawPayload, !payload.visibleText.isEmpty {
    parts.append(payload.visibleText)
  }
  for child in node.children {
    parts.append(contentsOf: collectedNodeTextParts(from: child))
  }
  return parts
}

package struct ResolvedListRow {
  var tag: SelectionTag
  var labelNode: ResolvedNode
  var drawMetadata: DrawMetadata
}

func resolvedListRow(
  from node: ResolvedNode
) -> ResolvedListRow? {
  let taggedNodes = taggedListRowNodes(in: node)
  guard taggedNodes.count == 1,
    let taggedNode = taggedNodes.first,
    let tag = taggedNode.semanticMetadata.selectionTag
  else {
    return nil
  }

  return .init(
    tag: tag,
    labelNode: node,
    drawMetadata: node.drawMetadata.merging(taggedNode.drawMetadata)
  )
}

func listItemPayload(
  from row: ResolvedListRow
) -> ListItemPayload {
  .init(
    kind: .row,
    text: resolvedNodeLabelText(from: row.labelNode),
    style: listItemTextStyle(from: row.drawMetadata),
    rowForegroundStyle: row.drawMetadata.listStyle?.rowForegroundStyle,
    rowBackgroundStyle: row.drawMetadata.listStyle?.rowBackgroundStyle,
    rowSeparators: .init(
      top: row.drawMetadata.listStyle?.rowSeparatorTopVisibility,
      bottom: row.drawMetadata.listStyle?.rowSeparatorBottomVisibility
    )
  )
}

func tableRowCells(
  from node: ResolvedNode
) -> [String] {
  tableRowCellPayloads(from: node).map(\.text)
}

func tableRowCellPayloads(
  from node: ResolvedNode
) -> [TableCellPayload] {
  let usesRowAsSingleCell = node.children.isEmpty
  let cellNodes = usesRowAsSingleCell ? [node] : node.children
  return cellNodes.map { cellNode in
    let trimmedText = resolvedNodeLabelText(from: cellNode)
      .trimmedUnicodeWhitespace()
    let styleMetadata =
      usesRowAsSingleCell
      ? cellNode.drawMetadata
      : node.drawMetadata.merging(cellNode.drawMetadata)
    return .init(
      text: trimmedText,
      style: listItemTextStyle(from: styleMetadata)
    )
  }
}

func resolvedTableColumnWidths(
  columns: [TableColumn],
  rows: [TableRowPayload]
) -> [Int] {
  measureTableColumnWidths(
    columns: columns.map { column in
      .init(
        title: column.title,
        width: column.width,
        alignment: resolvedTableCellAlignment(from: column.alignment),
        titleAlignment: resolvedTableCellAlignment(from: column.titleAlignment)
      )
    },
    rows: rows
  )
}

func formattedTableLine(
  cells: [String],
  widths: [Int],
  columns: [TableColumn],
  usesTitleAlignment: Bool = false
) -> String {
  renderTableLine(
    cells: cells,
    widths: widths,
    columns: columns.map { column in
      .init(
        title: column.title,
        width: column.width,
        alignment: resolvedTableCellAlignment(from: column.alignment),
        titleAlignment: resolvedTableCellAlignment(from: column.titleAlignment)
      )
    },
    usesTitleAlignment: usesTitleAlignment
  )
}

func paddedTableCell(
  _ content: String,
  width: Int,
  alignment: TableColumnAlignment
) -> String {
  renderTableCell(
    content,
    width: width,
    alignment: resolvedTableCellAlignment(from: alignment)
  )
}

private func taggedListRowNodes(
  in node: ResolvedNode
) -> [ResolvedNode] {
  var tagged: [ResolvedNode] = []
  if node.semanticMetadata.selectionTag != nil {
    tagged.append(node)
  }
  for child in node.children {
    tagged.append(contentsOf: taggedListRowNodes(in: child))
  }
  return tagged
}

private func resolvedTableCellAlignment(
  from alignment: TableColumnAlignment
) -> TableCellAlignment {
  if alignment == .center {
    return .center
  }
  if alignment == .trailing {
    return .trailing
  }
  return .leading
}
