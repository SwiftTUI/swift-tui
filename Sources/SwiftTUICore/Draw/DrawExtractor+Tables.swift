import Synchronization

/// Test instrumentation (the F118 probe pattern), the table twin of
/// ``ListLayoutDerivationProbe``: counts how many times a table's visible
/// layout is DERIVED, as opposed to consumed from the measured product.
/// Increments compile out of release.
package enum TableLayoutDerivationProbe {
  private static let counter = Mutex<Int>(0)

  package static var derivationCount: Int {
    counter.withLock { $0 }
  }

  package static func recordDerivation() {
    #if DEBUG
      counter.withLock { $0 += 1 }
    #endif
  }

  package static func reset() {
    #if DEBUG
      counter.withLock { $0 = 0 }
    #endif
  }
}

/// The visible display lines of a table, the column widths they were laid out
/// against, and the rect they occupy.
///
/// The table twin of ``ListVisibleLayout``: derived once at measure from the
/// real measured row heights, translated by placement, and consumed by draw
/// and semantics rather than re-derived by each.
package struct TableVisibleLayout: Equatable, Sendable {
  package var contentBounds: CellRect
  package var lines: [TableDisplayLine]
  package var widths: [Int]
  /// Total cells the visible lines occupy, which exceeds `lines.count`
  /// whenever a hosted row measured taller than one cell.
  package var totalContentHeight: Int
  /// The largest row anchor from whole-row fitting when taller rows require
  /// a different endpoint from the uniform-row estimate.
  package var maximumAnchorRow: Int? { scrollMetadata?.maximumAnchorRow }
  /// Cell-based position and measured endpoints for browser scroll chaining.
  package var scrollPosition: CollectionScrollPosition? { scrollMetadata?.position }
  package var scrollMetadata: CollectionScrollLayoutMetadata?
  package var bodyClip: CellRect? { scrollMetadata?.bodyClip(in: contentBounds) }

  package init(
    contentBounds: CellRect,
    lines: [TableDisplayLine],
    widths: [Int],
    totalContentHeight: Int? = nil
  ) {
    self.contentBounds = contentBounds
    self.lines = lines
    self.widths = widths
    self.totalContentHeight =
      totalContentHeight ?? lines.reduce(0) { $0 + max(1, $1.height) }
  }

  /// Returns a copy translated into absolute coordinates by `delta`.
  package func translated(by delta: CellPoint) -> TableVisibleLayout {
    var copy = self
    copy.contentBounds = CellRect(
      origin: .init(x: contentBounds.origin.x + delta.x, y: contentBounds.origin.y + delta.y),
      size: contentBounds.size
    )
    return copy
  }
}

extension DrawExtractor {
  func tableCommands(
    for payload: TablePayload,
    in bounds: CellRect,
    hostsCommittedItems: Bool = false,
    columnWidths: [Int]? = nil,
    placedLayout: TableVisibleLayout? = nil,
    effectiveOpacity: Double = 1
  ) -> [DrawCommand] {
    guard bounds.size.width > 0, bounds.size.height > 0 else {
      return []
    }

    // The ancestor opacity cascade applies at emission: segment styles are
    // baked into the (possibly placed) layout product with the payload's own
    // chrome factor already folded in, so the inherited factor multiplies on
    // top.
    func fadedText(_ style: TextStyle) -> TextStyle {
      guard effectiveOpacity != 1 else {
        return style
      }
      var faded = style
      faded.opacity = faded.opacity * effectiveOpacity
      return faded
    }
    func fadedShape(_ style: AnyShapeStyle) -> AnyShapeStyle {
      effectiveOpacity == 1 ? style : style.opacity(effectiveOpacity)
    }

    var commands: [DrawCommand] = []
    if let backgroundStyle = payload.backgroundStyle {
      commands.append(
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: fadedShape(backgroundStyle),
          mode: .full
        )
      )
    }

    // The placed product when there is one — that is what keeps a tall row's
    // borders on the same cells as its content. The recompute stays for
    // payload-only callers, whose rows are all one cell tall.
    let layout =
      placedLayout
      ?? visibleTableLayout(
        for: payload,
        in: bounds,
        columnWidths: columnWidths
      )
    let contentBounds = layout.contentBounds
    let lines = layout.lines

    for line in lines {
      var lineBounds = CellRect(
        origin: .init(x: contentBounds.origin.x, y: contentBounds.origin.y + line.yOffset),
        size: .init(width: contentBounds.size.width, height: max(1, line.height))
      )
      if let clip = layout.bodyClip, line.role == .row {
        guard let visible = lineBounds.intersection(clip) else { continue }
        lineBounds = visible
      }

      if let backgroundStyle = line.backgroundStyle {
        commands.append(
          .fill(
            bounds: lineBounds,
            geometry: .rectangle,
            insetAmount: 0,
            style: fadedShape(backgroundStyle),
            mode: .full
          )
        )
      }

      let segments: [TableDisplaySegment]
      if hostsCommittedItems, line.role == .row, line.segments.count >= 2 {
        // Keep the row's outer border behind committed cell nodes. Column
        // separators are drawn between the hosted cell frames below.
        let borderStyle = TextStyle(
          foregroundStyle: payload.borderStyle ?? payload.style.borderStyle
            ?? .semantic(.separator),
          opacity: payload.opacity
        )
        let widths = layout.widths
        segments = rowSegments(
          cells: widths.map { width in
            .init(content: String(repeating: " ", count: width), style: .init())
          },
          borderStyle: borderStyle,
          glyphs: payload.style.borderGlyphs
        )
      } else {
        segments = line.segments
      }

      // A hosted row taller than one cell needs its outer border on every cell
      // it spans, not just its first — the border is chrome the table owns,
      // and the committed child only paints the interior.
      let cellCount = hostsCommittedItems && line.role == .row ? lineBounds.size.height : 1
      for cellOffset in 0..<max(1, cellCount) {
        var cursorX = lineBounds.origin.x
        let lineMaxX = lineBounds.origin.x + lineBounds.size.width

        for segment in segments {
          let segmentWidth = layoutText(for: segment.content, width: nil).size.width
          guard segmentWidth > 0 else {
            continue
          }
          if cursorX >= lineMaxX {
            break
          }

          let visibleWidth = min(segmentWidth, lineMaxX - cursorX)
          guard visibleWidth > 0 else {
            continue
          }

          commands.append(
            .text(
              bounds: .init(
                origin: .init(x: cursorX, y: lineBounds.origin.y + cellOffset),
                size: .init(width: visibleWidth, height: 1)
              ),
              content: segment.content,
              style: fadedText(segment.style),
              lineLimit: 1,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          )
          cursorX += segmentWidth
        }
      }
    }

    return commands
  }

  /// Chrome display lines a table draws above and below its body.
  ///
  /// The arithmetic form of what ``materializedTableLines(for:widths:)`` emits
  /// for a row-less payload: a top border, the header and its rule when the
  /// table shows headers, and a bottom border. Structural, not stylistic — a
  /// border glyph set that renders as blank still occupies its line, which is
  /// why ``measuredTableIdealSize(for:)`` counts the same cells.
  package func tableChromeLineCounts(
    for payload: TablePayload
  ) -> (top: Int, bottom: Int) {
    (top: 1 + (payload.showsHeaders ? 2 : 0), bottom: 1)
  }

  /// The rect a viewport-backed table lays its body rows into: its bounds
  /// minus the header and border chrome. `nil` for payloads whose line model
  /// is materialized, where the same answer is not O(1).
  ///
  /// Scroll routing publishes this as the collection's viewport instead of the
  /// node's full bounds, for the same reason
  /// ``ListStylePresentation/viewportBackedListContentBounds(for:in:)``
  /// does: publishing the full bounds makes every scroll consumer believe two
  /// to four more rows are visible than are drawn — a table's chrome is
  /// thicker than a list's — so reveal-shaped decisions fire while the target
  /// is still on screen.
  ///
  /// The overflow-indicator lines are deliberately NOT subtracted here: they
  /// live inside this rect, and the body-window arithmetic in
  /// ``viewportBackedVisibleTableLines(for:viewportLineCount:showsIndicators:widths:rowHeights:rowWindow:)``
  /// takes exactly this height as its input.
  package func viewportBackedTableContentBounds(
    for payload: TablePayload,
    in bounds: CellRect
  ) -> CellRect? {
    guard payload.isViewportBacked else {
      return nil
    }
    let chrome = tableChromeLineCounts(for: payload)
    let bounds = tableInsetBounds(for: payload, in: bounds)
    return CellRect(
      origin: .init(x: bounds.origin.x, y: bounds.origin.y + chrome.top),
      size: .init(
        width: bounds.size.width,
        height: max(0, bounds.size.height - chrome.top - chrome.bottom)
      )
    )
  }

  /// The frame and all table lines occupy the area inside the style's insets.
  func tableInsetBounds(for payload: TablePayload, in bounds: CellRect) -> CellRect {
    let insets = payload.style.contentInsets
    return CellRect(
      origin: .init(x: bounds.origin.x + insets.leading, y: bounds.origin.y + insets.top),
      size: .init(
        width: max(0, bounds.size.width - insets.horizontal),
        height: max(0, bounds.size.height - insets.vertical)))
  }

  /// The visible display lines for `payload` inside `bounds`, with each line's
  /// height and content-relative `yOffset` resolved.
  ///
  /// `rowHeights` maps a row index to the cells its hosted child measured.
  /// Absent (payload-only callers, and any row not in the map) a row is one
  /// cell tall — the historical model, so those callers are unaffected.
  /// Supplying it is what makes measure, place, draw, and semantics agree on
  /// where a tall row's borders and separators go (register item D19).
  /// `rowWindow` bounds line GENERATION to a band of rows, on the same terms as
  /// ``ListStylePresentation/visibleListLayout(for:in:rowHeights:rowWindow:)``:
  /// inside a `ScrollView` the table is laid out against its own full content
  /// height, so generating "the visible lines" over those bounds builds a line
  /// per row of the whole dataset even though only a window was realized. The
  /// skipped body lines still occupy their cells, arithmetically: one each, or
  /// the height `rowHeights` retained for a row known to be taller.
  func visibleTableLayout(
    for payload: TablePayload,
    in bounds: CellRect,
    columnWidths: [Int]? = nil,
    rowHeights: [Int: Int]? = nil,
    rowWindow: Range<Int>? = nil
  ) -> TableVisibleLayout {
    TableLayoutDerivationProbe.recordDerivation()
    let bounds = tableInsetBounds(for: payload, in: bounds)
    let geometry = CollectionScrollGeometry(
      rowCount: payload.rowCount, rowSpan: 2, rowHeights: rowHeights ?? [:])
    let widths =
      columnWidths
      ?? measureTableColumnWidths(
        columns: payload.columns,
        rows: payload.isViewportBacked ? [] : payload.rows
      )
    if case .position = payload.scrollAnchor,
      bounds.size.height > tableChromeLineCounts(for: payload).top + 1,
      !payload.isViewportBacked
        || geometry.displayLineCount > bounds.size.height - tableChromeLineCounts(for: payload).top
          - 1
    {
      return positionedTableLayout(
        for: payload, in: bounds, widths: widths, rowHeights: rowHeights ?? [:],
        geometry: geometry)
    }
    if !payload.isViewportBacked, let rowHeights {
      return materializedHostedTableLayout(
        for: payload, in: bounds, widths: widths, rowHeights: rowHeights)
    }
    let generated = visibleTableLines(
      for: payload,
      viewportLineCount: bounds.size.height,
      geometry: geometry,
      showsIndicators: payload.showsIndicators,
      widths: widths,
      rowHeights: rowHeights,
      rowWindow: rowWindow
    )
    var lines = generated.lines
    // `extraCells` is the cells tall rows have added so far. A line's offset is
    // its POSITION in the content plus that. A windowed generation starts with
    // the known-tall rows before the window and ends with those after it.
    let windowRows =
      generated.linePositions == nil
      ? [] : lines.filter { $0.role == .row }.compactMap(\.rowIndex)
    var extraCells =
      windowRows.min().map { first in
        geometry.line(forRow: first) - first * geometry.rowSpan
      } ?? 0
    let extraAfter =
      windowRows.max().map { last in
        geometry.displayLineCount - geometry.lineRange(forRow: last).upperBound
          - (geometry.rowCount - last - 1) * geometry.rowSpan
      } ?? 0
    for index in lines.indices {
      let height =
        lines[index].role == .row
        ? (lines[index].rowIndex.flatMap { rowHeights?[$0] }.map { max(1, $0) } ?? 1)
        : 1
      lines[index].height = height
      lines[index].yOffset = (generated.linePositions?[index] ?? index) + extraCells
      extraCells += height - 1
    }
    var layout = TableVisibleLayout(
      contentBounds: bounds,
      lines: lines,
      widths: widths,
      totalContentHeight: generated.totalLineCount + extraCells + extraAfter
    )
    // Consume the exact body capacity used by whole-row fitting. Small tables
    // may omit an overflow indicator to preserve a row; recomputing capacity
    // from endpoint flags would incorrectly publish an empty viewport.
    let offset = generated.scrollPosition?.cellOffset ?? 0
    let navigation: CollectionScrollLayout?
    if payload.isViewportBacked {
      navigation = CollectionScrollLayout(
        geometry: geometry,
        visibleLines: offset..<(offset + generated.visibleBodyLineCount),
        anchor: payload.scrollAnchor)
    } else {
      navigation = nil
    }
    layout.scrollMetadata = CollectionScrollLayoutMetadata(
      maximumAnchorRow: generated.maximumAnchorRow,
      position: generated.scrollPosition,
      navigation: navigation
    )
    return layout
  }

  private func positionedTableLayout(
    for payload: TablePayload, in bounds: CellRect, widths: [Int],
    rowHeights: [Int: Int], geometry estimatedGeometry: CollectionScrollGeometry
  ) -> TableVisibleLayout {
    var chromePayload = payload
    if payload.isViewportBacked { chromePayload.rows = [] }
    let all = materializedTableLines(for: chromePayload, widths: widths)
    let topCount = min(all.count, tableChromeLineCounts(for: payload).top)
    let top = Array(all.prefix(topCount))
    var bottom = Array(all.suffix(1))
    var body = payload.isViewportBacked ? [] : Array(all.dropFirst(topCount).dropLast())
    var geometry = estimatedGeometry
    if !payload.isViewportBacked {
      var cursor = 0
      var ranges: [Range<Int>] = []
      for index in body.indices {
        body[index].height = body[index].rowIndex.flatMap { rowHeights[$0] }.map { max(1, $0) } ?? 1
        body[index].yOffset = cursor
        if body[index].rowIndex != nil { ranges.append(cursor..<(cursor + body[index].height)) }
        cursor += body[index].height
      }
      geometry = .init(rowRanges: ranges, displayLineCount: cursor)
    }
    let bodyCapacity = max(1, bounds.size.height - top.count - bottom.count)
    let indicators =
      payload.showsIndicators && geometry.displayLineCount > bodyCapacity
      && bodyCapacity >= 3
    let capacity = bodyCapacity - (indicators ? 2 : 0)
    let offset = geometry.positionedOffset(for: payload.scrollAnchor, capacity: capacity) ?? 0
    let end = offset + capacity
    if payload.isViewportBacked, geometry.rowCount > 0 {
      let first = geometry.row(atOrBeforeLine: offset)
      var last = first
      while last < geometry.rowCount, geometry.line(forRow: last) < end { last += 1 }
      let endPosition = min(geometry.rowCount * 2 - 1, last * 2)
      body = viewportBackedTableBodyLines(
        positions: (first * 2)..<endPosition,
        payload: payload, widths: widths)
      for index in body.indices {
        let position = first * 2 + index
        let range = geometry.lineRange(forRow: position / 2)
        body[index].height = position.isMultiple(of: 2) ? range.count : 1
        body[index].yOffset = position.isMultiple(of: 2) ? range.lowerBound : range.upperBound
      }
    }
    let bodyStart = top.count + (indicators ? 1 : 0)
    var lines = top
    for index in lines.indices { lines[index].yOffset = index }
    var visible = body.filter { $0.yOffset < end && $0.yOffset + $0.height > offset }
    for index in visible.indices { visible[index].yOffset += bodyStart - offset }
    lines.append(contentsOf: visible)
    if indicators {
      var above = overflowIndicatorLine(
        widths: widths, payload: payload, symbol: offset == 0 ? "" : "↑")
      above.yOffset = top.count
      lines.append(above)
      var below = overflowIndicatorLine(
        widths: widths, payload: payload,
        symbol: end >= geometry.displayLineCount ? "" : "↓")
      below.yOffset = bodyStart + capacity
      lines.append(below)
    }
    for index in bottom.indices {
      bottom[index].yOffset = bounds.size.height - bottom.count + index
    }
    lines.append(contentsOf: bottom)
    var layout = TableVisibleLayout(
      contentBounds: bounds, lines: lines, widths: widths,
      totalContentHeight: bounds.size.height)
    layout.scrollMetadata = .init(
      maximumAnchorRow: geometry.maxAnchorRow(viewportLineCount: capacity),
      position: .init(
        cellOffset: offset, isAtStart: offset == 0,
        isAtEnd: end >= geometry.displayLineCount),
      navigation: .init(
        geometry: geometry, visibleLines: offset..<end, anchor: payload.scrollAnchor),
      bodyStart: bodyStart)
    return layout
  }

  /// Hosted eager rows retain their measured cells, including optional separators.
  /// Payload-only tables keep the historical single-line materialized path.
  private func materializedHostedTableLayout(
    for payload: TablePayload,
    in bounds: CellRect,
    widths: [Int],
    rowHeights: [Int: Int]
  ) -> TableVisibleLayout {
    let displayLines = materializedTableLines(for: payload, widths: widths)
    let topCount = min(displayLines.count, payload.showsHeaders ? 3 : 1)
    let bottomCount = displayLines.isEmpty ? 0 : 1
    let top = Array(displayLines.prefix(topCount))
    let bottom = Array(displayLines.suffix(bottomCount))
    var body = Array(displayLines.dropFirst(topCount).dropLast(bottomCount))
    var cursor = 0
    var rowRanges: [Range<Int>] = []
    for index in body.indices {
      let height = body[index].rowIndex.flatMap { rowHeights[$0] }.map { max(1, $0) } ?? 1
      body[index].height = height
      body[index].yOffset = cursor
      if body[index].rowIndex != nil { rowRanges.append(cursor..<(cursor + height)) }
      cursor += height
    }
    let geometry = CollectionScrollGeometry(rowRanges: rowRanges, displayLineCount: cursor)
    let bodyCapacity = max(0, bounds.size.height - topCount - bottomCount)
    guard bodyCapacity > 0, !body.isEmpty else {
      var lines = Array(displayLines.prefix(max(0, bounds.size.height)))
      for index in lines.indices { lines[index].yOffset = index }
      return TableVisibleLayout(
        contentBounds: bounds, lines: lines, widths: widths, totalContentHeight: lines.count)
    }

    func window(capacity: Int) -> (offset: Int, end: Int, maximum: Int) {
      var maximum = body.count
      var tailCells = 0
      while maximum > 0, tailCells + body[maximum - 1].height <= capacity {
        maximum -= 1
        tailCells += body[maximum].height
      }
      maximum = min(maximum, body.count - 1)
      let offset: Int
      if cursor <= capacity {
        offset = 0
      } else if let anchor = payload.scrollAnchor {
        switch anchor {
        case .start:
          offset = 0
        case .row(let row), .position(let row, _):
          let target = body.firstIndex { $0.rowIndex == row } ?? maximum
          offset = min(target, maximum)
        case .end:
          offset = maximum
        }
      } else {
        let selected = selectedTableLineIndex(in: body) ?? 0
        let startCell = max(0, body[selected].yOffset - capacity / 2)
        let centred = body.lastIndex { $0.yOffset <= startCell } ?? 0
        let selectedEnd = body[selected].yOffset + min(capacity, body[selected].height)
        if selectedEnd <= body[centred].yOffset + capacity {
          offset = min(centred, maximum)
        } else {
          let fitted = body.firstIndex { $0.yOffset >= selectedEnd - capacity } ?? selected
          offset = min(fitted, maximum)
        }
      }
      var end = offset
      var cells = 0
      while end < body.count, cells + body[end].height <= capacity {
        cells += body[end].height
        end += 1
      }
      // Oversized rows still expose their leading cells and remain navigable.
      return (offset, max(end, offset + 1), maximum)
    }

    let maximumIndicators = min(2, bodyCapacity - 1)
    var showsIndicators =
      payload.showsIndicators && cursor > bodyCapacity && bodyCapacity >= 2
    var capacity = bodyCapacity
    var range = window(capacity: capacity)
    if showsIndicators {
      var reservedIndicators = 0
      // A smaller window can expose another hidden edge. Reservations only
      // increase, so both indicator edges settle in at most two refinements.
      for _ in 0..<2 {
        let hiddenEdges = (range.offset > 0 ? 1 : 0) + (range.end < body.count ? 1 : 0)
        let requiredIndicators = min(hiddenEdges, maximumIndicators)
        guard requiredIndicators > reservedIndicators else { break }
        reservedIndicators = requiredIndicators
        capacity = max(1, bodyCapacity - reservedIndicators)
        range = window(capacity: capacity)
      }
    }
    let firstLineHeight = body[range.offset].height
    let firstLineExceedsWindow = firstLineHeight > capacity
    let firstLineFitsBody = firstLineHeight <= bodyCapacity
    if showsIndicators && firstLineExceedsWindow && firstLineFitsBody {
      // Overflow chrome must not make an otherwise fitting row oversized.
      showsIndicators = false
      capacity = bodyCapacity
      range = window(capacity: capacity)
    }
    var visibleBody: [TableDisplayLine] = []
    let hidesAbove = showsIndicators && range.offset > 0
    if hidesAbove {
      visibleBody.append(overflowIndicatorLine(widths: widths, payload: payload, symbol: "↑"))
    }
    visibleBody.append(contentsOf: body[range.offset..<range.end])
    let hasRoomForLowerIndicator = !hidesAbove || maximumIndicators > 1
    let hidesBelow = showsIndicators && range.end < body.count && hasRoomForLowerIndicator
    let usedCells = visibleBody.reduce(0) { $0 + $1.height }
    if cursor > bodyCapacity {
      let padding = max(0, bodyCapacity - usedCells - (hidesBelow ? 1 : 0))
      visibleBody.append(
        contentsOf: Array(
          repeating: overflowIndicatorLine(widths: widths, payload: payload, symbol: ""),
          count: padding))
    }
    if hidesBelow {
      visibleBody.append(overflowIndicatorLine(widths: widths, payload: payload, symbol: "↓"))
    }
    var lines = top + visibleBody + bottom
    var yOffset = 0
    for index in lines.indices {
      lines[index].yOffset = yOffset
      yOffset += lines[index].height
    }
    let offset = body[range.offset].yOffset
    let position = CollectionScrollPosition(
      cellOffset: offset, isAtStart: range.offset == 0, isAtEnd: range.offset == range.maximum)
    let navigation = CollectionScrollLayout(
      geometry: geometry, visibleLines: offset..<(offset + capacity), anchor: payload.scrollAnchor)
    var layout = TableVisibleLayout(
      contentBounds: bounds, lines: lines, widths: widths, totalContentHeight: yOffset)
    layout.scrollMetadata = CollectionScrollLayoutMetadata(
      maximumAnchorRow: geometry.row(atOrAfterLine: body[range.maximum].yOffset),
      position: position, navigation: navigation)
    return layout
  }

  /// Generated lines, plus what the caller needs when they do not cover the
  /// content contiguously: each line's content-relative POSITION (`nil` when
  /// positions are just the array indices) and the content's total line count.
  private typealias GeneratedTableLines = (
    lines: [TableDisplayLine],
    linePositions: [Int]?,
    totalLineCount: Int,
    maximumAnchorRow: Int?,
    scrollPosition: CollectionScrollPosition?,
    visibleBodyLineCount: Int
  )

  private func visibleTableLines(
    for payload: TablePayload,
    viewportLineCount: Int,
    geometry: CollectionScrollGeometry,
    showsIndicators: Bool,
    widths: [Int],
    rowHeights: [Int: Int]?,
    rowWindow: Range<Int>?
  ) -> GeneratedTableLines {
    if payload.isViewportBacked {
      return viewportBackedVisibleTableLines(
        for: payload,
        viewportLineCount: viewportLineCount,
        geometry: geometry,
        showsIndicators: showsIndicators,
        widths: widths,
        rowHeights: rowHeights,
        rowWindow: rowWindow
      )
    }
    // The materialized line model has no arithmetic row-to-line map, and no
    // hosted children to window against.
    let displayLines = materializedTableLines(
      for: payload,
      widths: widths
    )

    guard viewportLineCount > 0 else {
      return ([], nil, 0, nil, nil, 0)
    }
    guard displayLines.count > viewportLineCount else {
      return (displayLines, nil, displayLines.count, nil, nil, 0)
    }

    let fixedTopCount = min(displayLines.count, payload.showsHeaders ? 3 : 1)
    let fixedBottomCount = displayLines.isEmpty ? 0 : 1
    guard viewportLineCount > fixedTopCount + fixedBottomCount else {
      let clamped = Array(displayLines.prefix(viewportLineCount))
      return (clamped, nil, clamped.count, nil, nil, 0)
    }

    let bodyStart = fixedTopCount
    let bodyEnd = max(bodyStart, displayLines.count - fixedBottomCount)
    let bodyLines = Array(displayLines[bodyStart..<bodyEnd])
    let bodyCapacity = viewportLineCount - fixedTopCount - fixedBottomCount
    let anchorLine = (payload.scrollAnchor?.rowIndex(rowCount: payload.rowCount)).map { row in
      bodyLines.firstIndex { $0.role == .row && ($0.rowIndex ?? -1) >= row }
        ?? max(0, bodyLines.count - 1)
    }

    if bodyLines.count <= bodyCapacity {
      let all =
        Array(displayLines.prefix(fixedTopCount))
        + bodyLines
        + Array(displayLines.suffix(fixedBottomCount))
      return (all, nil, all.count, nil, nil, 0)
    }

    if !showsIndicators {
      let window = visibleTableBodyWindow(
        from: bodyLines,
        lineCapacity: bodyCapacity,
        anchorLine: anchorLine
      )
      let visible =
        Array(displayLines.prefix(fixedTopCount))
        + window.lines
        + Array(displayLines.suffix(fixedBottomCount))
      return (visible, nil, visible.count, nil, nil, 0)
    }

    let anchoredOffset = visibleTableBodyWindow(
      from: bodyLines, lineCapacity: bodyCapacity, anchorLine: anchorLine
    ).offset
    let anchoredEnd = min(bodyLines.count, anchoredOffset + bodyCapacity)
    let initialHiddenAbove = anchoredOffset > 0
    let initialHiddenBelow = anchoredEnd < bodyLines.count
    let reservedIndicators =
      (initialHiddenAbove ? 1 : 0)
      + (initialHiddenBelow ? 1 : 0)
    let bodyWindowCapacity = max(1, bodyCapacity - reservedIndicators)
    let window = visibleTableBodyWindow(
      from: bodyLines,
      lineCapacity: bodyWindowCapacity,
      anchorLine: anchorLine
    )
    let hiddenAbove = window.offset > 0
    let hiddenBelow = window.offset + window.lines.count < bodyLines.count

    var visibleBody: [TableDisplayLine] = []
    visibleBody.reserveCapacity(bodyCapacity)
    if hiddenAbove {
      visibleBody.append(
        overflowIndicatorLine(
          widths: widths,
          payload: payload,
          symbol: "↑"
        )
      )
    }
    visibleBody.append(contentsOf: window.lines)
    if hiddenBelow, visibleBody.count < bodyCapacity {
      visibleBody.append(
        overflowIndicatorLine(
          widths: widths,
          payload: payload,
          symbol: "↓"
        )
      )
    }

    let visible =
      Array(displayLines.prefix(fixedTopCount))
      + Array(visibleBody.prefix(bodyCapacity))
      + Array(displayLines.suffix(fixedBottomCount))
    return (visible, nil, visible.count, nil, nil, 0)
  }

  private func viewportBackedVisibleTableLines(
    for payload: TablePayload,
    viewportLineCount: Int,
    geometry: CollectionScrollGeometry,
    showsIndicators: Bool,
    widths: [Int],
    rowHeights: [Int: Int]?,
    rowWindow: Range<Int>?
  ) -> GeneratedTableLines {
    guard viewportLineCount > 0 else {
      return ([], nil, 0, nil, nil, 0)
    }

    var chromePayload = payload
    chromePayload.rows = []
    chromePayload.selectedRowIndex = nil
    chromePayload.isViewportBacked = false
    let chrome = materializedTableLines(for: chromePayload, widths: widths)
    let top = Array(chrome.dropLast())
    let bottom = chrome.last.map { [$0] } ?? []
    guard viewportLineCount > top.count + bottom.count else {
      let clamped = Array(top.prefix(viewportLineCount))
      return (clamped, nil, clamped.count, nil, nil, 0)
    }

    let bodyLineCount = payload.rowCount == 0 ? 0 : payload.rowCount * 2 - 1
    let bodyCapacity = viewportLineCount - top.count - bottom.count
    // The body's cells: a row line is as tall as its hosted row measured, so
    // the rows `rowHeights` knows are taller add their extra cells.
    let bodyCellCount = geometry.displayLineCount
    func lineHeight(_ position: Int) -> Int {
      position % 2 == 0 ? max(1, rowHeights?[position / 2] ?? 1) : 1
    }
    guard bodyCellCount > bodyCapacity else {
      // These bounds cover the whole content — the `ScrollView` case, and the
      // only one where windowing is sound: nothing is scrolled out, so no
      // overflow indicators shift the lines and every line's position is its
      // position in the content.
      let totalLineCount = top.count + bodyLineCount + bottom.count
      guard let rowWindow, !rowWindow.isEmpty else {
        let all =
          top
          + viewportBackedTableBodyLines(
            positions: 0..<bodyLineCount,
            payload: payload,
            widths: widths
          )
          + bottom
        return (all, nil, totalLineCount, nil, nil, bodyCapacity)
      }

      let windowStart = max(0, rowWindow.lowerBound * 2)
      let windowEnd = min(bodyLineCount, max(0, rowWindow.upperBound * 2))
      guard windowStart < windowEnd, windowEnd - windowStart < bodyLineCount else {
        let all =
          top
          + viewportBackedTableBodyLines(
            positions: 0..<bodyLineCount,
            payload: payload,
            widths: widths
          )
          + bottom
        return (all, nil, totalLineCount, nil, nil, bodyCapacity)
      }

      let body = viewportBackedTableBodyLines(
        positions: windowStart..<windowEnd,
        payload: payload,
        widths: widths
      )
      let positions =
        Array(0..<top.count)
        + (windowStart..<windowEnd).map { top.count + $0 }
        + (bottom.isEmpty ? [] : [top.count + bodyLineCount])
      return (top + body + bottom, positions, totalLineCount, nil, nil, bodyCapacity)
    }

    let selectedLine = min(
      max((payload.selectedRowIndex ?? 0) * 2, 0),
      max(0, bodyLineCount - 1)
    )
    // A stored anchor pins the top of the body window; without one the window
    // stays centred on the selection, which is what payload-only callers get.
    let anchorRow = payload.scrollAnchor?.rowIndex(rowCount: payload.rowCount)
    let anchorLine = anchorRow.map { rowIndex in
      min(max(0, rowIndex) * 2, max(0, bodyLineCount - 1))
    }
    // The window is measured in cells, so tall rows fill it sooner. With
    // one-cell rows every line is one cell and this is plain line arithmetic.
    func window(capacity: Int) -> (offset: Int, end: Int, maxOffset: Int) {
      // The first line from which the rest of the body fits: the offset that
      // shows the bottom of the table. At least the last line is shown.
      var maxOffset = bodyLineCount
      var tailCells = 0
      while maxOffset > 0, tailCells + lineHeight(maxOffset - 1) <= capacity {
        maxOffset -= 1
        tailCells += lineHeight(maxOffset)
      }
      maxOffset = min(maxOffset, max(0, bodyLineCount - 1))
      let offset =
        if let anchorLine {
          min(anchorLine, maxOffset)
        } else {
          min(max(0, selectedLine - capacity / 2), maxOffset)
        }
      var end = offset
      var cells = 0
      while end < bodyLineCount, cells + lineHeight(end) <= capacity {
        cells += lineHeight(end)
        end += 1
      }
      return (offset, max(end, min(bodyLineCount, offset + 1)), maxOffset)
    }
    // Publish the first row at the fitted end window so navigation uses the
    // same whole-row endpoint as placement.
    func maximumAnchorRow(_ range: (offset: Int, end: Int, maxOffset: Int)) -> Int? {
      bodyCellCount > bodyLineCount ? (range.maxOffset + 1) / 2 : nil
    }
    func scrollPosition(_ range: (offset: Int, end: Int, maxOffset: Int))
      -> CollectionScrollPosition
    {
      let row = geometry.lineRange(forRow: range.offset / geometry.rowSpan)
      return CollectionScrollPosition(
        cellOffset: range.offset.isMultiple(of: geometry.rowSpan) ? row.lowerBound : row.upperBound,
        isAtStart: range.offset == 0, isAtEnd: range.offset == range.maxOffset)
    }
    // A window whose next row does not fit leaves cells unused. Blank body
    // lines fill them, so the overflow indicator and the closing border stay
    // on the table's last lines instead of floating up under the rows.
    func filled(_ body: [TableDisplayLine], capacity: Int) -> [TableDisplayLine] {
      let used = body.reduce(0) { $0 + ($1.rowIndex.map { max(1, rowHeights?[$0] ?? 1) } ?? 1) }
      guard used < capacity else {
        return body
      }
      return body
        + Array(
          repeating: overflowIndicatorLine(widths: widths, payload: payload, symbol: ""),
          count: capacity - used)
    }

    guard showsIndicators else {
      let range = window(capacity: bodyCapacity)
      let visible =
        top
        + filled(
          viewportBackedTableBodyLines(
            positions: range.offset..<range.end,
            payload: payload,
            widths: widths
          ),
          capacity: bodyCapacity
        )
        + bottom
      return (
        visible, nil, visible.count, maximumAnchorRow(range), scrollPosition(range), bodyCapacity
      )
    }

    let initial = window(capacity: bodyCapacity)
    let reservedIndicators =
      (initial.offset > 0 ? 1 : 0)
      + (initial.end < bodyLineCount ? 1 : 0)
    let bodyWindowCapacity = max(1, bodyCapacity - reservedIndicators)
    let range = window(capacity: bodyWindowCapacity)
    var visibleBody: [TableDisplayLine] = []
    visibleBody.reserveCapacity(bodyCapacity)
    if range.offset > 0 {
      visibleBody.append(
        overflowIndicatorLine(widths: widths, payload: payload, symbol: "↑")
      )
    }
    visibleBody.append(
      contentsOf: viewportBackedTableBodyLines(
        positions: range.offset..<range.end,
        payload: payload,
        widths: widths
      )
    )
    let hidesRowsBelow = range.end < bodyLineCount
    visibleBody = filled(visibleBody, capacity: bodyCapacity - (hidesRowsBelow ? 1 : 0))
    if hidesRowsBelow, visibleBody.count < bodyCapacity {
      visibleBody.append(
        overflowIndicatorLine(widths: widths, payload: payload, symbol: "↓")
      )
    }
    let visible = top + Array(visibleBody.prefix(bodyCapacity)) + bottom
    return (
      visible, nil, visible.count, maximumAnchorRow(range), scrollPosition(range),
      bodyWindowCapacity
    )
  }

  private func viewportBackedTableBodyLines(
    positions: Range<Int>,
    payload: TablePayload,
    widths: [Int]
  ) -> [TableDisplayLine] {
    let borderStyle = TextStyle(
      foregroundStyle: payload.borderStyle ?? payload.style.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    let glyphs = payload.style.borderGlyphs
    return positions.map { position in
      if position % 2 == 1 {
        return TableDisplayLine(
          segments: borderSegments(
            widths: widths,
            glyphs: glyphs,
            position: .middle,
            style: borderStyle
          ),
          backgroundStyle: nil,
          role: .rowSeparator,
          isSelectedRow: false,
          rowIndex: nil
        )
      }

      let rowIndex = position / 2
      let row =
        payload.rows.indices.contains(rowIndex)
        ? payload.rows[rowIndex] : TableRowPayload(cells: [])
      let isSelected = rowIndex == payload.selectedRowIndex
      let rowTextStyle = resolvedTableRowTextStyle(
        row: row,
        payload: payload,
        isSelected: isSelected
      )
      let cellSegments = widths.enumerated().map { columnIndex, width in
        let content = columnIndex < row.cells.count ? row.cells[columnIndex].text : ""
        let cellStyle =
          columnIndex < row.cells.count
          ? resolvedTableCellTextStyle(
            cell: row.cells[columnIndex],
            rowStyle: rowTextStyle,
            payload: payload,
            isSelected: isSelected
          )
          : rowTextStyle
        let truncationMode =
          columnIndex < row.cells.count
          ? row.cells[columnIndex].truncationMode ?? .tail
          : .tail
        return TableDisplaySegment(
          content: renderTableCell(
            content,
            width: width,
            alignment: payload.columns[columnIndex].alignment,
            truncationMode: truncationMode
          ),
          style: cellStyle
        )
      }
      return TableDisplayLine(
        segments: rowSegments(
          cells: cellSegments,
          borderStyle: borderStyle,
          glyphs: glyphs
        ),
        backgroundStyle: isSelected
          ? (payload.selectedRowBackgroundStyle ?? row.rowBackgroundStyle)
          : row.rowBackgroundStyle,
        role: .row,
        isSelectedRow: isSelected,
        rowIndex: rowIndex
      )
    }
  }

  private func materializedTableLines(
    for payload: TablePayload,
    widths: [Int]
  ) -> [TableDisplayLine] {
    let borderStyle = TextStyle(
      foregroundStyle: payload.borderStyle ?? payload.style.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    let glyphs = payload.style.borderGlyphs
    var lines: [TableDisplayLine] = [
      .init(
        segments: borderSegments(
          widths: widths,
          glyphs: glyphs,
          position: .top,
          style: borderStyle
        ),
        backgroundStyle: nil,
        role: .topBorder,
        isSelectedRow: false,
        rowIndex: nil
      )
    ]

    if payload.showsHeaders {
      var headerStyle = TextStyle(
        foregroundStyle: payload.style.headerForegroundStyle ?? .semantic(.muted)
      )
      headerStyle.opacity *= payload.opacity
      lines.append(
        .init(
          segments: rowSegments(
            cells: payload.columns.enumerated().map { index, column in
              .init(
                content: renderTableCell(
                  column.title,
                  width: widths[index],
                  alignment: column.titleAlignment
                ),
                style: headerStyle
              )
            },
            borderStyle: borderStyle,
            glyphs: glyphs
          ),
          backgroundStyle: payload.style.headerBackgroundStyle,
          role: .header,
          isSelectedRow: false,
          rowIndex: nil
        )
      )
      lines.append(
        .init(
          segments: borderSegments(
            widths: widths,
            glyphs: glyphs,
            position: .middle,
            style: borderStyle
          ),
          backgroundStyle: nil,
          role: .headerSeparator,
          isSelectedRow: false,
          rowIndex: nil
        )
      )
    }

    for (index, row) in payload.rows.enumerated() {
      let isSelected = index == payload.selectedRowIndex
      let rowTextStyle = resolvedTableRowTextStyle(
        row: row,
        payload: payload,
        isSelected: isSelected
      )
      let cellSegments = widths.enumerated().map { columnIndex, width in
        let content = columnIndex < row.cells.count ? row.cells[columnIndex].text : ""
        let cellStyle =
          columnIndex < row.cells.count
          ? resolvedTableCellTextStyle(
            cell: row.cells[columnIndex],
            rowStyle: rowTextStyle,
            payload: payload,
            isSelected: isSelected
          )
          : rowTextStyle
        let truncationMode =
          columnIndex < row.cells.count
          ? row.cells[columnIndex].truncationMode ?? .tail
          : .tail
        return TableDisplaySegment(
          content: renderTableCell(
            content,
            width: width,
            alignment: payload.columns[columnIndex].alignment,
            truncationMode: truncationMode
          ),
          style: cellStyle
        )
      }

      lines.append(
        .init(
          segments: rowSegments(
            cells: cellSegments,
            borderStyle: borderStyle,
            glyphs: glyphs
          ),
          backgroundStyle: isSelected
            ? (payload.selectedRowBackgroundStyle ?? row.rowBackgroundStyle)
            : row.rowBackgroundStyle,
          role: .row,
          isSelectedRow: isSelected,
          rowIndex: index
        )
      )

      if shouldRenderTableRowSeparator(
        current: row,
        next: payload.rows.dropFirst(index + 1).first
      ) {
        lines.append(
          .init(
            segments: borderSegments(
              widths: widths,
              glyphs: glyphs,
              position: .middle,
              style: borderStyle
            ),
            backgroundStyle: nil,
            role: .rowSeparator,
            isSelectedRow: false,
            rowIndex: nil
          )
        )
      }
    }

    lines.append(
      .init(
        segments: borderSegments(
          widths: widths,
          glyphs: glyphs,
          position: .bottom,
          style: borderStyle
        ),
        backgroundStyle: nil,
        role: .bottomBorder,
        isSelectedRow: false,
        rowIndex: nil
      )
    )

    return lines
  }

  private func visibleTableBodyWindow(
    from bodyLines: [TableDisplayLine],
    lineCapacity: Int,
    anchorLine: Int? = nil
  ) -> (offset: Int, lines: [TableDisplayLine]) {
    guard lineCapacity > 0 else {
      return (0, [])
    }

    let selectedIndex = selectedTableLineIndex(in: bodyLines) ?? 0
    let offset = min(
      max(0, anchorLine ?? (selectedIndex - (lineCapacity / 2))),
      max(0, bodyLines.count - lineCapacity)
    )
    let end = min(bodyLines.count, offset + lineCapacity)
    return (offset, Array(bodyLines[offset..<end]))
  }

  private func shouldRenderTableRowSeparator(
    current: TableRowPayload,
    next: TableRowPayload?
  ) -> Bool {
    guard let next else {
      return false
    }
    if current.rowSeparators.bottom == .hidden || next.rowSeparators.top == .hidden {
      return false
    }
    return true
  }

  private func selectedTableLineIndex(
    in lines: [TableDisplayLine]
  ) -> Int? {
    lines.firstIndex(where: \.isSelectedRow)
  }
}
