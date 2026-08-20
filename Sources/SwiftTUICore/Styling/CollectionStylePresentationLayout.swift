import Synchronization

/// Instrumentation (the F118 probe pattern): counts how many times a
/// list's visible layout is DERIVED, as opposed to consumed from the measured
/// product. Register item D19 is exactly this count being one per phase.
///
/// Armed by ``FeatureGate/collectionProbes`` (`SWIFTTUI_COLLECTION_PROBES`):
/// always on in DEBUG, opt-in in release. The run loop resets it at each frame
/// head and samples it at commit into the `list_layout_derivations` column of
/// `frames.tsv`.
///
/// Unlike its sibling ``IndexedChildRealizationProbe`` this probe is not
/// main-actor isolated — list layout derivation runs on the frame-tail worker —
/// so the armed latch lives inside the same `Mutex` as the counter. Folding it
/// in costs nothing: a call already takes that lock, and the probe fires once
/// per derivation rather than once per row.
package enum ListLayoutDerivationProbe {
  private struct State {
    var isArmed: Bool
    var derivationCount: Int
  }

  private static let state = Mutex(
    State(
      isArmed: FeatureGate.collectionProbes.initialIsEnabled(),
      derivationCount: 0
    )
  )

  /// Whether the probe counts. Settable so a test can measure the disarmed
  /// path (DEBUG defaults armed, so an unarmed assertion has no other way to
  /// reach that state).
  package static var isArmed: Bool {
    get { state.withLock { $0.isArmed } }
    set { state.withLock { $0.isArmed = newValue } }
  }

  /// Derivations since the last ``reset()``. Always readable — the existing
  /// DEBUG suites assert on it directly and arming is additive to them.
  package static var derivationCount: Int {
    state.withLock { $0.derivationCount }
  }

  /// The same count, or `nil` when the probe is disarmed — the read the
  /// per-frame diagnostics sample takes. See
  /// ``IndexedChildRealizationProbe/realizedChildCountIfArmed`` for why the
  /// disarmed case must not collapse to zero.
  package static var derivationCountIfArmed: Int? {
    state.withLock { $0.isArmed ? $0.derivationCount : nil }
  }

  package static func recordDerivation() {
    state.withLock {
      guard $0.isArmed else {
        return
      }
      $0.derivationCount += 1
    }
  }

  package static func reset() {
    state.withLock { $0.derivationCount = 0 }
  }
}

/// The resolved display-line window of a list, and the line arithmetic it was
/// derived from.
///
/// Display line 0 is row 0: chrome border rows are layout-bearing content
/// insets outside the scrollable stream, never lines of the stream itself.
package struct ListLineWindow: Equatable, Sendable {
  /// The first visible display line.
  package var offset: Int
  /// How many display lines the viewport shows, after reserving the two
  /// overflow-indicator lines when they apply.
  package var visibleLineCount: Int
  /// The list's total display-line count.
  package var displayLineCount: Int
  /// Display lines per row: 2 when the style draws row separators.
  package var rowSpan: Int

  package var end: Int {
    min(displayLineCount, offset + visibleLineCount)
  }
}

extension ListStylePresentation {
  /// Display lines one row of a viewport-backed list occupies.
  package var listRowDisplaySpan: Int {
    showsRowSeparators ? 2 : 1
  }

  /// The display-line window a viewport-backed list shows.
  ///
  /// This is the single place the window offset is derived: the draw-side line
  /// builder and the input-side scroll currency both call it, so "where am I
  /// looking" has one definition instead of one per phase.
  ///
  /// `anchorRowIndex` is the stored scroll currency. When it is `nil` the
  /// offset falls back to the historical selection-centred derivation, which
  /// keeps payload-only callers byte-identical.
  package func viewportBackedListWindow(
    itemCount: Int,
    selectedRowIndex: Int?,
    anchorRowIndex: Int?,
    showsIndicators: Bool,
    viewportLineCount: Int
  ) -> ListLineWindow {
    let rowSpan = listRowDisplaySpan
    let displayLineCount = itemCount <= 0 ? 0 : itemCount * rowSpan - (rowSpan - 1)
    let visibleLineCount =
      displayLineCount > viewportLineCount && showsIndicators && viewportLineCount >= 3
      ? max(1, viewportLineCount - 2)
      : viewportLineCount
    let maxOffset = max(0, displayLineCount - visibleLineCount)
    let offset: Int
    if let anchorRowIndex {
      let anchorRow = min(max(0, anchorRowIndex), max(0, itemCount - 1))
      offset = min(max(0, anchorRow * rowSpan), maxOffset)
    } else {
      let selectedRow = min(max(selectedRowIndex ?? 0, 0), max(0, itemCount - 1))
      let selectedLine = selectedRow * rowSpan
      offset = min(max(0, selectedLine - (visibleLineCount / 2)), maxOffset)
    }

    return ListLineWindow(
      offset: offset,
      visibleLineCount: visibleLineCount,
      displayLineCount: displayLineCount,
      rowSpan: rowSpan
    )
  }

  /// The visible display lines for `payload` inside `bounds`, with each line's
  /// height and content-relative `yOffset` resolved.
  ///
  /// `rowHeights` maps a row index to the cells its hosted child measured.
  /// Absent (payload-only callers, and any row not in the map) a row is one
  /// cell tall — the historical model, so those callers are unaffected.
  /// Supplying it is what makes measure, place, draw, and semantics agree on
  /// where a tall row's chrome goes (register item D19).
  /// `rowWindow` bounds line GENERATION to a band of rows, for the case where
  /// `bounds` is not the viewport: inside a `ScrollView` a hosted collection is
  /// laid out against its own full content height, so asking for "the visible
  /// lines" over those bounds builds one display line per row of the whole
  /// dataset even though only a window of rows was ever realized. Passing the
  /// measured window keeps the line array O(window); the skipped rows still
  /// occupy their cells, arithmetically, because an unrealized row is one cell
  /// tall by definition.
  package func visibleListLayout(
    for payload: ListPayload,
    in bounds: CellRect,
    rowHeights: [Int: Int]? = nil,
    rowWindow: Range<Int>? = nil
  ) -> ListVisibleLayout {
    ListLayoutDerivationProbe.recordDerivation()
    let contentBounds = listContentBounds(in: bounds)
    let generated = visibleListLines(
      for: payload,
      viewportLineCount: contentBounds.size.height,
      rowWindow: rowWindow
    )
    var lines = generated.lines
    var cursor = generated.firstLinePosition
    for index in lines.indices {
      let height =
        lines[index].rowIndex.flatMap { rowHeights?[$0] }.map { max(1, $0) } ?? 1
      lines[index].height = height
      lines[index].yOffset = cursor
      cursor += height
    }
    let totalContentHeight = cursor + generated.trailingLineCount

    return ListVisibleLayout(
      contentBounds: contentBounds,
      lines: lines,
      sectionChromeBounds: sectionChromeBounds(
        for: payload,
        lines: lines,
        in: contentBounds,
        totalContentHeight: totalContentHeight,
        isWindowed: generated.isWindowed
      ),
      totalContentHeight: totalContentHeight
    )
  }

  package func listChromeBounds(
    for layout: ListVisibleLayout,
    in bounds: CellRect
  ) -> [CellRect] {
    guard container != nil else {
      return []
    }

    switch chromeScope {
    case .wholeList:
      return [bounds]
    case .eachSection:
      return layout.sectionChromeBounds
    }
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> CellSize {
    if payload.isViewportBacked {
      let horizontalInset = contentInsets.leading + contentInsets.trailing
      let verticalInset = contentInsets.top + contentInsets.bottom
      let rowCount = payload.rowCount
      let separatorCount = showsRowSeparators ? max(0, rowCount - 1) : 0
      let markerWidth = payload.showsSelectionMarker && rowCount > 0 ? 2 : 0
      return CellSize(
        width: markerWidth + horizontalInset,
        height: rowCount + separatorCount + verticalInset
      )
    }
    let horizontalInset = contentInsets.leading + contentInsets.trailing
    let perSectionVerticalInset = contentInsets.top + contentInsets.bottom
    let usesSectionChrome = container != nil && chromeScope == .eachSection
    let lineMetrics = payload.items.enumerated().reduce(
      into: (width: 0, height: 0, rowIndex: 0, sectionCount: 0, sectionHasContent: false)
    ) { partial, element in
      let (index, item) = element
      switch item.kind {
      case .header, .footer:
        partial.width = max(
          partial.width, layoutText(for: item.text, width: nil).size.width)
        partial.height += 1
        partial.sectionHasContent = true
      case .row:
        let prefix =
          if payload.showsSelectionMarker {
            partial.rowIndex == payload.selectedRowIndex ? "> " : "  "
          } else {
            ""
          }
        partial.width = max(
          partial.width,
          layoutText(for: prefix + item.text, width: nil).size.width
        )
        partial.height += 1
        partial.sectionHasContent = true
        if showsRowSeparators,
          listRowSeparatorIsVisible(
            current: item,
            next: payload.items.dropFirst(index + 1).first
          )
        {
          partial.width = max(partial.width, 1)
          partial.height += 1
        }
        partial.rowIndex += 1
      case .sectionBreak:
        if usesSectionChrome {
          if partial.sectionHasContent {
            partial.sectionCount += 1
            partial.sectionHasContent = false
          }
          return
        }
        if showsSectionSeparators, listSectionSeparatorIsVisible(item) {
          partial.height += 1
          partial.width = max(partial.width, 1)
        }
      }
    }
    let sectionCount =
      if usesSectionChrome {
        lineMetrics.sectionCount + (lineMetrics.sectionHasContent ? 1 : 0)
      } else {
        0
      }
    let verticalInset =
      if usesSectionChrome {
        max(1, sectionCount) * perSectionVerticalInset
      } else {
        perSectionVerticalInset
      }

    return CellSize(
      width: lineMetrics.width + horizontalInset,
      height: lineMetrics.height + verticalInset
    )
  }

  /// The rect a list lays its display lines into: its bounds minus the
  /// style's content insets. Serves both payload paths — the materialized
  /// line model shares the same O(1) band arithmetic.
  ///
  /// Scroll routing publishes this as the collection's viewport instead of the
  /// node's full bounds. The difference is the container chrome and content
  /// insets — the cells that the node occupies but never draws rows
  /// into. Publishing the full bounds makes every scroll consumer believe that
  /// many more rows are visible than are drawn, so reveal-shaped decisions
  /// fire while the target is still on screen — and, with the border rows now
  /// layout-bearing, the anchor arithmetic pins a top row the real window
  /// never shows.
  ///
  /// The overflow-indicator lines are deliberately NOT subtracted here: they
  /// live inside this rect, and the consumers that care re-derive them through
  /// ``viewportBackedListWindow(itemCount:selectedRowIndex:anchorRowIndex:showsIndicators:viewportLineCount:)``,
  /// which takes exactly this height as its input.
  package func viewportBackedListContentBounds(
    for payload: ListPayload,
    in bounds: CellRect
  ) -> CellRect? {
    listContentBounds(in: bounds)
  }

  /// The cells a list's display lines are laid into for `bounds`.
  package func listContentHeight(
    in bounds: CellRect
  ) -> Int {
    listContentBounds(in: bounds).size.height
  }

  private func listContentBounds(
    in bounds: CellRect
  ) -> CellRect {
    // Vertical insets are layout-bearing for every chrome scope, matching the
    // horizontal axis and `measuredListIdealSize` (which reserves them on
    // both payload paths). `eachSection` styles used to zero them and model
    // the border rows as scrollable spacer lines instead — so an overflowing
    // list slid a real row under the stroked box (only one spacer fits in a
    // contiguous window) and the row erased the border's horizontal run.
    CellRect(
      origin: .init(
        x: bounds.origin.x + contentInsets.leading,
        y: bounds.origin.y + contentInsets.top
      ),
      size: .init(
        width: max(0, bounds.size.width - contentInsets.leading - contentInsets.trailing),
        height: max(0, bounds.size.height - contentInsets.top - contentInsets.bottom)
      )
    )
  }

  /// Generated lines, plus what the caller needs to place them inside content
  /// they do not fully cover: the content-relative line position the first
  /// generated line sits at, and how many one-cell lines follow the last one.
  /// Both are zero unless `rowWindow` bounded the generation.
  private typealias GeneratedListLines = (
    lines: [ListDisplayLine],
    firstLinePosition: Int,
    trailingLineCount: Int,
    isWindowed: Bool
  )

  private func visibleListLines(
    for payload: ListPayload,
    viewportLineCount: Int,
    rowWindow: Range<Int>?
  ) -> GeneratedListLines {
    if payload.isViewportBacked {
      return viewportBackedVisibleListLines(
        for: payload,
        viewportLineCount: viewportLineCount,
        rowWindow: rowWindow
      )
    }
    // The materialized line model has no arithmetic row-to-line map (headers,
    // footers, and section separators interleave), so it cannot be windowed
    // this way; it is also the path with no hosted children to window against.
    let displayLines = materializedListLines(for: payload)
    guard viewportLineCount > 0 else {
      return ([], 0, 0, false)
    }

    if displayLines.count > viewportLineCount {
      let visibleLineCount =
        payload.showsIndicators && viewportLineCount >= 3
        ? max(1, viewportLineCount - 2)
        : viewportLineCount
      let maxOffset = max(0, displayLines.count - visibleLineCount)
      let offset: Int
      if let anchorRowIndex = payload.scrollAnchorRowIndex {
        // The materialized line array is not uniformly spaced (headers,
        // footers, and section separators interleave), so the anchor ROW is
        // mapped to its line here rather than by arithmetic. Falling back to
        // the last line keeps a stale anchor past the end from collapsing the
        // window to the top.
        let anchorLineIndex =
          displayLines.firstIndex { $0.rowIndex == anchorRowIndex }
          ?? (anchorRowIndex > 0 ? displayLines.count - 1 : 0)
        offset = min(max(0, anchorLineIndex), maxOffset)
      } else {
        let selectedLineIndex = selectedListLineIndex(
          in: displayLines,
          selectedRowIndex: payload.selectedRowIndex
        )
        let lineIndex = min(
          max(selectedLineIndex ?? 0, 0),
          max(0, displayLines.count - 1)
        )
        offset = min(max(0, lineIndex - (visibleLineCount / 2)), maxOffset)
      }
      let end = min(displayLines.count, offset + visibleLineCount)
      guard payload.showsIndicators, viewportLineCount >= 3 else {
        return (Array(displayLines[offset..<end]), 0, 0, false)
      }
      var visible: [ListDisplayLine] = []
      visible.reserveCapacity(visibleLineCount + 2)
      visible.append(
        .init(
          kind: .text(
            "↑", .init(foregroundStyle: .semantic(.separator), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      )
      if offset == 0 {
        visible[0] = .init(
          kind: .text("", .init(foregroundStyle: .semantic(.muted), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      }
      visible.append(contentsOf: displayLines[offset..<end])
      visible.append(
        .init(
          kind: .text(
            "↓", .init(foregroundStyle: .semantic(.separator), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      )
      if end >= displayLines.count {
        visible[visible.count - 1] = .init(
          kind: .text("", .init(foregroundStyle: .semantic(.muted), opacity: payload.opacity)),
          isHeader: true,
          rowIndex: nil
        )
      }
      return (visible, 0, 0, false)
    }

    return (Array(displayLines.prefix(viewportLineCount)), 0, 0, false)
  }

  private func viewportBackedVisibleListLines(
    for payload: ListPayload,
    viewportLineCount: Int,
    rowWindow: Range<Int>?
  ) -> GeneratedListLines {
    guard viewportLineCount > 0, payload.rowCount > 0 else {
      return ([], 0, 0, false)
    }

    let usesSectionChrome = container != nil && chromeScope == .eachSection
    let window = viewportBackedListWindow(
      itemCount: payload.rowCount,
      selectedRowIndex: payload.selectedRowIndex,
      anchorRowIndex: payload.scrollAnchorRowIndex,
      showsIndicators: payload.showsIndicators,
      viewportLineCount: viewportLineCount
    )
    let rowSpan = window.rowSpan
    let displayLineCount = window.displayLineCount
    var offset = window.offset
    var end = window.end
    // Bound generation to the rows that were actually realized — but ONLY when
    // these bounds cover the whole content, which is the `ScrollView` case the
    // window exists for. That condition is what makes a windowed line's
    // `yOffset` mean the same thing as an unwindowed one's: with the content
    // fully covered, `offset` is 0 and no overflow indicators are inserted, so
    // a line's offset is its position in the content. Where the bounds really
    // are a viewport, offsets are viewport-relative and windowing them would
    // shift every row.
    var isWindowed = false
    if let rowWindow, !rowWindow.isEmpty, viewportLineCount >= displayLineCount {
      let windowStart = max(offset, rowWindow.lowerBound * rowSpan)
      let windowEnd = min(end, rowWindow.upperBound * rowSpan)
      if windowStart < windowEnd, windowEnd - windowStart < end - offset {
        offset = windowStart
        end = windowEnd
        isWindowed = true
      }
    }
    var visible = (offset..<end).map { position in
      viewportBackedListLine(
        at: position,
        payload: payload,
        usesSectionChrome: usesSectionChrome,
        rowSpan: rowSpan
      )
    }

    if isWindowed {
      // No overflow indicators: a windowed generation only happens when the
      // bounds cover the whole content, where nothing is hidden to indicate.
      return (visible, offset, max(0, displayLineCount - end), true)
    }

    guard displayLineCount > viewportLineCount,
      payload.showsIndicators,
      viewportLineCount >= 3
    else {
      return (visible, 0, 0, false)
    }

    let indicatorStyle = TextStyle(
      foregroundStyle: .semantic(.separator),
      opacity: payload.opacity
    )
    visible.insert(
      .init(
        kind: .text(offset == 0 ? "" : "↑", indicatorStyle),
        isHeader: true,
        rowIndex: nil
      ),
      at: 0
    )
    visible.append(
      .init(
        kind: .text(end >= displayLineCount ? "" : "↓", indicatorStyle),
        isHeader: true,
        rowIndex: nil
      )
    )
    return (visible, 0, 0, false)
  }

  private func viewportBackedListLine(
    at position: Int,
    payload: ListPayload,
    usesSectionChrome: Bool,
    rowSpan: Int
  ) -> ListDisplayLine {
    if rowSpan == 2, position % 2 == 1 {
      return .init(
        kind: .separator(payload.borderStyle ?? .semantic(.separator)),
        isHeader: false,
        rowIndex: nil,
        sectionIndex: usesSectionChrome ? 0 : nil
      )
    }

    let rowIndex = position / rowSpan
    // A viewport-backed payload stores no items: the row is a committed child
    // node and the payload's copy was an empty stub carrying only defaults, so
    // the default is exactly what the stub would have supplied.
    let item =
      payload.items.indices.contains(rowIndex)
      ? payload.items[rowIndex]
      : ListItemPayload(kind: .row, text: "")
    let isSelected = rowIndex == payload.selectedRowIndex
    var style = item.style
    if let rowForegroundStyle = item.rowForegroundStyle {
      style.foregroundStyle = rowForegroundStyle
    } else if style.foregroundStyle == nil {
      style.foregroundStyle = payload.foregroundStyle ?? .semantic(.foreground)
    }
    if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
      style.foregroundStyle = selectedForegroundStyle
    }
    style.opacity *= payload.opacity
    let marker = payload.showsSelectionMarker ? (isSelected ? "▌ " : "  ") : ""
    let markerStyle = TextStyle(
      foregroundStyle: isSelected
        ? (payload.selectedRowMarkerStyle ?? payload.selectedRowForegroundStyle
          ?? payload.foregroundStyle ?? .semantic(.foreground))
        : payload.borderStyle ?? .semantic(.separator),
      opacity: payload.opacity
    )
    return .init(
      kind: .row(
        marker: marker,
        markerStyle: markerStyle,
        text: item.text,
        textStyle: style,
        backgroundStyle: isSelected
          ? (payload.selectedRowBackgroundStyle ?? item.rowBackgroundStyle)
          : item.rowBackgroundStyle
      ),
      isHeader: false,
      rowIndex: rowIndex,
      sectionIndex: usesSectionChrome ? 0 : nil,
      itemIndex: rowIndex,
      truncationMode: item.truncationMode ?? .tail
    )
  }

  private func materializedListLines(
    for payload: ListPayload
  ) -> [ListDisplayLine] {
    var lines: [ListDisplayLine] = []
    var sectionLines: [ListDisplayLine] = []
    var sectionIndex = 0
    var rowIndex = 0
    let usesSectionChrome = container != nil && chromeScope == .eachSection

    func appendLine(_ line: ListDisplayLine) {
      if usesSectionChrome {
        sectionLines.append(line)
      } else {
        lines.append(line)
      }
    }

    func flushSection() {
      guard usesSectionChrome, !sectionLines.isEmpty else {
        return
      }

      // Two spacer lines separate consecutive sections: the previous
      // section's bottom-border row and this section's top-border row.
      // They carry no section index, so the chrome ranges break across them.
      // The outermost border rows are not lines at all — they live in the
      // vertical content insets, which the chrome rects expand back into.
      if sectionIndex > 0 {
        let spacerStyle = TextStyle(opacity: payload.opacity)
        for _ in 0..<2 {
          lines.append(
            .init(
              kind: .text("", spacerStyle),
              isHeader: true,
              rowIndex: nil
            )
          )
        }
      }
      lines.append(
        contentsOf: sectionLines.map { line in
          var sectionLine = line
          sectionLine.sectionIndex = sectionIndex
          return sectionLine
        }
      )
      sectionLines.removeAll(keepingCapacity: true)
      sectionIndex += 1
    }

    for (index, item) in payload.items.enumerated() {
      switch item.kind {
      case .header:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = AnyShapeStyle(.terminalBorder(.accent))
        }
        styleOverride.opacity *= payload.opacity
        appendLine(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index,
            truncationMode: item.truncationMode ?? .tail
          )
        )
      case .footer:
        var styleOverride = item.style
        if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = .semantic(.muted)
        }
        styleOverride.opacity *= payload.opacity
        appendLine(
          .init(
            kind: .text(item.text, styleOverride),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index,
            truncationMode: item.truncationMode ?? .tail
          )
        )
      case .row:
        var styleOverride = item.style
        if let rowForegroundStyle = item.rowForegroundStyle {
          styleOverride.foregroundStyle = rowForegroundStyle
        } else if styleOverride.foregroundStyle == nil {
          styleOverride.foregroundStyle = payload.foregroundStyle ?? .semantic(.foreground)
        }
        styleOverride.opacity *= payload.opacity
        let isSelected = rowIndex == payload.selectedRowIndex
        let marker =
          payload.showsSelectionMarker
          ? (isSelected ? "▌ " : "  ")
          : ""
        let markerStyle = TextStyle(
          foregroundStyle: isSelected
            ? (payload.selectedRowMarkerStyle ?? payload.selectedRowForegroundStyle ?? payload
              .foregroundStyle ?? .semantic(.foreground))
            : payload.borderStyle ?? .semantic(.separator),
          opacity: payload.opacity
        )
        if isSelected, let selectedForegroundStyle = payload.selectedRowForegroundStyle {
          styleOverride.foregroundStyle = selectedForegroundStyle
        }
        appendLine(
          .init(
            kind: .row(
              marker: marker,
              markerStyle: markerStyle,
              text: item.text,
              textStyle: styleOverride,
              backgroundStyle: isSelected
                ? (payload.selectedRowBackgroundStyle ?? item.rowBackgroundStyle)
                : item.rowBackgroundStyle
            ),
            isHeader: false,
            rowIndex: rowIndex,
            itemIndex: index,
            truncationMode: item.truncationMode ?? .tail
          )
        )

        if showsRowSeparators,
          listRowSeparatorIsVisible(
            current: item,
            next: payload.items.dropFirst(index + 1).first
          )
        {
          appendLine(
            .init(
              kind: .separator(payload.borderStyle ?? .semantic(.separator)),
              isHeader: false,
              rowIndex: nil
            )
          )
        }
        rowIndex += 1
      case .sectionBreak:
        if usesSectionChrome {
          flushSection()
          continue
        }
        guard showsSectionSeparators,
          listSectionSeparatorIsVisible(item)
        else {
          continue
        }
        lines.append(
          .init(
            kind: .separator(payload.borderStyle ?? .semantic(.separator)),
            isHeader: true,
            rowIndex: nil,
            itemIndex: index
          )
        )
      }
    }

    if usesSectionChrome {
      flushSection()
      // An empty payload emits no lines; its empty two-row box comes from the
      // chrome derivation, which strokes the bare vertical insets.
    }

    return lines
  }

  /// The stroked chrome rects for `eachSection` styles. Every rect expands
  /// the content-relative line range back out by the content insets on both
  /// axes, so the border rows/columns land in the reserved insets (or, for
  /// inter-section boundaries, in the spacer lines between the sections) —
  /// never on cells a row occupies.
  ///
  /// A viewport-backed payload has exactly one section, so its box hugs the
  /// visible content directly (clamped to the band, wrapping the overflow
  /// indicators when they show) instead of being derived from line ranges —
  /// which would misplace the border onto the indicator rows. `isWindowed`
  /// (the `ScrollView` case, where the bounds cover the whole content)
  /// strokes the full content extent for the same single section.
  private func sectionChromeBounds(
    for payload: ListPayload,
    lines: [ListDisplayLine],
    in contentBounds: CellRect,
    totalContentHeight: Int,
    isWindowed: Bool
  ) -> [CellRect] {
    guard container != nil, chromeScope == .eachSection else {
      return []
    }

    func chromeRect(fromLine start: Int, toLine end: Int) -> CellRect {
      CellRect(
        origin: .init(
          x: contentBounds.origin.x - contentInsets.leading,
          y: contentBounds.origin.y + start - contentInsets.top
        ),
        size: .init(
          width: contentBounds.size.width + contentInsets.leading
            + contentInsets.trailing,
          height: end - start + contentInsets.top + contentInsets.bottom
        )
      )
    }

    if isWindowed {
      return [chromeRect(fromLine: 0, toLine: totalContentHeight)]
    }

    if payload.isViewportBacked {
      guard payload.rowCount > 0 else {
        return []
      }
      let visibleContentHeight = min(totalContentHeight, contentBounds.size.height)
      return [chromeRect(fromLine: 0, toLine: visibleContentHeight)]
    }

    if lines.isEmpty {
      // An empty grouped payload keeps its empty box: the bare border rows.
      return payload.items.isEmpty ? [chromeRect(fromLine: 0, toLine: 0)] : []
    }

    var bounds: [CellRect] = []
    var rangeStart: Int?
    var activeSectionIndex: Int?

    func appendRange(endingAt endIndex: Int) {
      guard let start = rangeStart else {
        return
      }
      bounds.append(chromeRect(fromLine: start, toLine: endIndex))
    }

    for line in lines {
      guard let sectionIndex = line.sectionIndex else {
        appendRange(endingAt: line.yOffset)
        rangeStart = nil
        activeSectionIndex = nil
        continue
      }

      if activeSectionIndex != sectionIndex {
        appendRange(endingAt: line.yOffset)
        rangeStart = line.yOffset
        activeSectionIndex = sectionIndex
      }
    }

    appendRange(endingAt: lines.last.map { $0.yOffset + max(1, $0.height) } ?? 0)

    // When the visible slice's outermost lines carry no section index (an
    // overflow indicator, or a window boundary that landed on a spacer), the
    // ±inset expansion above would stroke the outer border on that line's
    // row instead of the band's reserved border row. Extend the outermost
    // boxes to the band edges so the indicators sit inside the box and the
    // reserved rows carry the border — the same geometry the viewport-backed
    // branch produces directly.
    if !bounds.isEmpty {
      if lines.first?.sectionIndex == nil {
        let first = bounds[0]
        let bandTop = contentBounds.origin.y - contentInsets.top
        bounds[0] = CellRect(
          origin: .init(x: first.origin.x, y: bandTop),
          size: .init(
            width: first.size.width,
            height: first.size.height + (first.origin.y - bandTop)
          )
        )
      }
      if lines.last?.sectionIndex == nil {
        let last = bounds[bounds.count - 1]
        let bandBottom =
          contentBounds.origin.y + contentBounds.size.height + contentInsets.bottom
        bounds[bounds.count - 1] = CellRect(
          origin: last.origin,
          size: .init(
            width: last.size.width,
            height: max(last.size.height, bandBottom - last.origin.y)
          )
        )
      }
    }
    return bounds
  }

  private func selectedListLineIndex(
    in lines: [ListDisplayLine],
    selectedRowIndex: Int?
  ) -> Int? {
    if let selectedRowIndex,
      let selectedIndex = lines.firstIndex(where: { line in
        line.rowIndex == selectedRowIndex
      })
    {
      return selectedIndex
    }

    return lines.firstIndex { line in line.rowIndex != nil }
  }

  private func listRowSeparatorIsVisible(
    current: ListItemPayload,
    next: ListItemPayload?
  ) -> Bool {
    guard let next, next.kind == .row else {
      return false
    }
    if current.rowSeparators.bottom == .hidden || next.rowSeparators.top == .hidden {
      return false
    }
    return true
  }

  private func listSectionSeparatorIsVisible(
    _ item: ListItemPayload
  ) -> Bool {
    if item.sectionSeparators.bottom == .hidden || item.sectionSeparators.top == .hidden {
      return false
    }
    return true
  }
}
