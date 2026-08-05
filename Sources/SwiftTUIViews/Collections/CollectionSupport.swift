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

/// Test instrumentation (the F118 probe pattern): counts how many rows a
/// resolve asks the selection policy about. Register item D18 is exactly this
/// count scaling with the dataset rather than the viewport; increments compile
/// out of release.
@MainActor
package enum CollectionSelectionProbe {
  package private(set) static var membershipTests = 0

  package static func recordMembershipTest() {
    #if DEBUG
      membershipTests += 1
    #endif
  }

  package static func reset() {
    #if DEBUG
      membershipTests = 0
    #endif
  }
}

@MainActor
package enum CollectionSelectionPolicy<Value: Hashable & Sendable> {
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
    CollectionSelectionProbe.recordMembershipTest()
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

  /// The bound selection as a tag, without consulting any row.
  ///
  /// A viewport-backed collection pairs this with
  /// ``IndexedChildSource/elementIndex(forSelectionTag:)`` to locate the
  /// selected row by id. The alternative — asking the policy about every
  /// row's tag until one matches — is O(dataset) on the resolve path of every
  /// frame (register item D18).
  package func selectionTag() -> SelectionTag? {
    let value: Value?
    switch self {
    case .none:
      return nil
    case .requiredSingle(let binding):
      value = binding.wrappedValue
    case .optionalSingle(let binding):
      value = binding.wrappedValue
    case .multiple(let binding):
      // Multi-selection has no single anchor; the first member is what the
      // window and the marker follow, matching `selectedIndices.first`.
      value = binding.wrappedValue.first
    }
    return value.map { SelectionTag(value: $0, includeOptional: true) }
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
/// collection: publishing one per row would restore the O(dataset) registry
/// cost the windowed path exists to avoid.
///
/// The band is centred on `anchor` and holds `capacity` indices. Callers with
/// live scroll geometry should pass ``collectionInteractionBand`` — a fixed
/// capacity is a guess, and on a tall terminal it leaves rows that are plainly
/// on screen with no registered handler at all (register item D20).
func collectionInteractionIndices(
  count: Int,
  anchor: Int?,
  capacity: Int = collectionInteractionFallbackCapacity
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

/// The band capacity used before any scroll geometry has synced (frame 1).
let collectionInteractionFallbackCapacity = 64

/// Rows the terminal viewport can hold beyond the visible window, registered
/// so the row just off each edge responds the instant it scrolls in.
private let collectionInteractionMargin = 16

/// The interaction band for a collection, sized from its live viewport when
/// the scroll registry has published geometry for it and centred on the
/// visible window rather than on the selection.
///
/// Anchoring on the scroll anchor alone would centre the band on the window's
/// FIRST row, wasting half its capacity above the viewport; the window's
/// middle is what the band should straddle.
@MainActor
func collectionInteractionBand(
  count: Int,
  scrollAnchorRow: Int?,
  selectionAnchor: Int?,
  visibleRowCount: Int?
) -> Range<Int> {
  guard let visibleRowCount, visibleRowCount > 0, let scrollAnchorRow else {
    return collectionInteractionIndices(count: count, anchor: selectionAnchor)
  }
  return collectionInteractionIndices(
    count: count,
    anchor: scrollAnchorRow + visibleRowCount / 2,
    capacity: visibleRowCount + 2 * collectionInteractionMargin
  )
}

/// Past this many top-level rows, an eagerly-resolved collection is worth
/// reporting: every row is realized and measured on every frame, and the
/// direct-data spelling of the same collection would have been windowed.
private let eagerCollectionRowThreshold = 256

/// The advisory issue for a collection that resolved eagerly at a scale where
/// the windowed path would have mattered, or `nil` below the threshold.
func eagerCollectionRuntimeIssue(
  rowCount: Int,
  identity: Identity,
  source: String
) -> RuntimeIssue? {
  guard rowCount >= eagerCollectionRowThreshold else {
    return nil
  }
  return RuntimeIssue(
    severity: .warning,
    code: "collection.eagerLargeCollection",
    message:
      "\(source) resolved \(rowCount) rows eagerly. Builder-authored content takes the "
      + "unwindowed path; the data-source initializer realizes only the visible band.",
    identity: identity,
    source: source
  )
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

/// The effective text-layout attributes of the first text run inside a
/// flattened row/cell/header subtree — the stamped leaf metadata that the
/// flattening to `String` + `TextStyle` would otherwise destroy.
func flattenedTextLayoutAttributes(
  from node: ResolvedNode
) -> (lineLimit: Int?, truncationMode: TextTruncationMode?) {
  var stack = [node]
  while let current = stack.popLast() {
    switch current.drawPayload {
    case .text, .richText:
      return (
        current.layoutMetadata.lineLimit,
        current.layoutMetadata.textTruncationMode
      )
    default:
      break
    }
    stack.append(contentsOf: current.children.reversed())
  }
  return (nil, nil)
}

func listItemPayload(
  from row: ResolvedListRow
) -> ListItemPayload {
  let textAttributes = flattenedTextLayoutAttributes(from: row.labelNode)
  return .init(
    kind: .row,
    text: resolvedNodeLabelText(from: row.labelNode),
    style: listItemTextStyle(from: row.drawMetadata),
    rowForegroundStyle: row.drawMetadata.listStyle?.rowForegroundStyle,
    rowBackgroundStyle: row.drawMetadata.listStyle?.rowBackgroundStyle,
    rowSeparators: .init(
      top: row.drawMetadata.listStyle?.rowSeparatorTopVisibility,
      bottom: row.drawMetadata.listStyle?.rowSeparatorBottomVisibility
    ),
    lineLimit: textAttributes.lineLimit,
    truncationMode: textAttributes.truncationMode
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
    let textAttributes = flattenedTextLayoutAttributes(from: cellNode)
    return .init(
      text: trimmedText,
      style: listItemTextStyle(from: styleMetadata),
      lineLimit: textAttributes.lineLimit,
      truncationMode: textAttributes.truncationMode
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
