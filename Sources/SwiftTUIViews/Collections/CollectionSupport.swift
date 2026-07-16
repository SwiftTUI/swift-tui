@_spi(Testing) import SwiftTUICore

private enum HostedCollectionContentKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  package var isResolvingHostedCollectionContent: Bool {
    get { self[HostedCollectionContentKey.self] }
    set { self[HostedCollectionContentKey.self] = newValue }
  }
}

@MainActor
package enum CollectionSelectionPolicy<Value: Hashable> {
  case none
  case requiredSingle(Binding<Value>)
  case optionalSingle(Binding<Value?>)
  case multiple(Binding<Set<Value>>)

  package var isSelectable: Bool {
    switch self {
    case .none:
      false
    case .requiredSingle, .optionalSingle, .multiple:
      true
    }
  }

  package var isMultiple: Bool {
    if case .multiple = self {
      return true
    }
    return false
  }

  package func value(from tag: SelectionTag) -> Value? {
    pickerSelectionValue(from: tag, as: Value.self)
  }

  package func contains(_ tag: SelectionTag) -> Bool {
    guard let value = value(from: tag) else {
      return false
    }
    switch self {
    case .none:
      return false
    case .requiredSingle(let binding):
      return binding.wrappedValue == value
    case .optionalSingle(let binding):
      return binding.wrappedValue == value
    case .multiple(let binding):
      return binding.wrappedValue.contains(value)
    }
  }

  package func select(_ tag: SelectionTag) -> Bool {
    guard let value = value(from: tag) else {
      return false
    }
    switch self {
    case .none:
      return false
    case .requiredSingle(let binding):
      if binding.wrappedValue != value {
        binding.wrappedValue = value
      }
    case .optionalSingle(let binding):
      if binding.wrappedValue != value {
        binding.wrappedValue = value
      }
    case .multiple(let binding):
      var values = binding.wrappedValue
      values.insert(value)
      binding.wrappedValue = values
    }
    return true
  }

  package func toggle(_ tag: SelectionTag) -> Bool {
    guard let value = value(from: tag) else {
      return false
    }
    switch self {
    case .none:
      return false
    case .requiredSingle, .optionalSingle:
      return select(tag)
    case .multiple(let binding):
      var values = binding.wrappedValue
      if values.contains(value) {
        values.remove(value)
      } else {
        values.insert(value)
      }
      binding.wrappedValue = values
      return true
    }
  }

  package func step(
    orderedTags: [SelectionTag],
    delta: Int
  ) -> Bool {
    guard let direction = delta == 0 ? nil : delta.signum(), !orderedTags.isEmpty else {
      return false
    }
    guard !isMultiple else {
      // Multi-selection keeps the set independent from keyboard focus. The
      // focus system consumes the unhandled arrow and moves the row cursor.
      return false
    }

    let currentIndex =
      orderedTags.firstIndex(where: contains)
      ?? (direction > 0 ? -1 : orderedTags.count)
    let nextIndex = min(max(currentIndex + delta, 0), orderedTags.count - 1)
    guard nextIndex != currentIndex else {
      return false
    }
    return select(orderedTags[nextIndex])
  }
}

/// Resolve-time interaction descriptors stay bounded for an indexed
/// collection. The layout pass materializes the exact viewport later, so the
/// selection/focus anchor is the only available resolve-time locator. Keeping
/// a generous band around it covers the current terminal viewport and the
/// next navigation step without restoring O(dataset) registry publication.
func collectionInteractionIndices(
  count: Int,
  anchor: Int?,
  capacity: Int = 64
) -> Range<Int> {
  guard count > 0, capacity > 0 else {
    return 0..<0
  }
  let boundedCapacity = min(count, capacity)
  let boundedAnchor = min(max(anchor ?? 0, 0), count - 1)
  let preferredLower = boundedAnchor - boundedCapacity / 2
  let lower = min(max(0, preferredLower), count - boundedCapacity)
  return lower..<(lower + boundedCapacity)
}

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

func applyingHostedRowForegroundStyle(
  _ style: AnyShapeStyle?,
  to source: ResolvedNode
) -> ResolvedNode {
  guard let style else {
    return source
  }
  var node = source
  node.drawMetadata.foregroundStyle = style
  node.children = node.children.map {
    applyingHostedRowForegroundStyle(style, to: $0)
  }
  return node
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
  var tag: SelectionTag?
  var tagCount: Int
  var labelNode: ResolvedNode
  var drawMetadata: DrawMetadata
}

func resolvedListRow(
  from node: ResolvedNode
) -> ResolvedListRow? {
  let row = resolvedHostedListRow(from: node)
  return row.tagCount == 1 ? row : nil
}

func resolvedHostedListRow(
  from node: ResolvedNode
) -> ResolvedListRow {
  let taggedNodes = taggedListRowNodes(in: node)
  let taggedNode = taggedNodes.count == 1 ? taggedNodes.first : nil

  return .init(
    tag: taggedNode?.semanticMetadata.selectionTag,
    tagCount: taggedNodes.count,
    labelNode: node,
    drawMetadata: taggedNode.map { node.drawMetadata.merging($0.drawMetadata) }
      ?? node.drawMetadata
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
