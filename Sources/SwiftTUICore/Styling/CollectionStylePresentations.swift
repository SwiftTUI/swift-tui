/// Resolved container chrome for grouped collection presentations.
public struct CollectionContainerChromePresentation: Equatable, Sendable {
  public var geometry: ShapeGeometry
  public var insetAmount: Int
  public var fillMode: ShapeFillMode
  public var strokeStyle: StrokeStyle
  public var strokeBorder: Bool

  public init(
    geometry: ShapeGeometry,
    insetAmount: Int = 0,
    fillMode: ShapeFillMode = .full,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool = true
  ) {
    self.geometry = geometry
    self.insetAmount = max(0, insetAmount)
    self.fillMode = fillMode
    self.strokeStyle = strokeStyle
    self.strokeBorder = strokeBorder
  }

  public static var insetGrouped: Self {
    .init(
      geometry: .roundedRectangle(cornerRadius: 1),
      fillMode: .interior(strokeWidth: 1),
      strokeStyle: .init(borderSet: .rounded)
    )
  }
}

/// Controls where list container chrome is painted.
public enum ListChromeScope: Equatable, Sendable {
  case wholeList
  case eachSection
}

/// Resolved table border glyphs used by low-level table drawing.
public struct TableBorderGlyphs: Equatable, Sendable {
  public var topLeft: String
  public var top: String
  public var topJoin: String
  public var topRight: String
  public var left: String
  public var columnJoin: String
  public var right: String
  public var middleLeft: String
  public var middle: String
  public var middleJoin: String
  public var middleRight: String
  public var bottomLeft: String
  public var bottom: String
  public var bottomJoin: String
  public var bottomRight: String

  public init(
    topLeft: String,
    top: String,
    topJoin: String,
    topRight: String,
    left: String,
    columnJoin: String,
    right: String,
    middleLeft: String,
    middle: String,
    middleJoin: String,
    middleRight: String,
    bottomLeft: String,
    bottom: String,
    bottomJoin: String,
    bottomRight: String
  ) {
    self.topLeft = topLeft
    self.top = top
    self.topJoin = topJoin
    self.topRight = topRight
    self.left = left
    self.columnJoin = columnJoin
    self.right = right
    self.middleLeft = middleLeft
    self.middle = middle
    self.middleJoin = middleJoin
    self.middleRight = middleRight
    self.bottomLeft = bottomLeft
    self.bottom = bottom
    self.bottomJoin = bottomJoin
    self.bottomRight = bottomRight
  }

  public static var plain: Self {
    .init(
      topLeft: "┌",
      top: "─",
      topJoin: "┬",
      topRight: "┐",
      left: "│",
      columnJoin: "│",
      right: "│",
      middleLeft: "├",
      middle: "─",
      middleJoin: "┼",
      middleRight: "┤",
      bottomLeft: "└",
      bottom: "─",
      bottomJoin: "┴",
      bottomRight: "┘"
    )
  }

  public static var insetGrouped: Self {
    .init(
      topLeft: "╭",
      top: "─",
      topJoin: "┬",
      topRight: "╮",
      left: "│",
      columnJoin: "│",
      right: "│",
      middleLeft: "├",
      middle: "─",
      middleJoin: "┼",
      middleRight: "┤",
      bottomLeft: "╰",
      bottom: "─",
      bottomJoin: "┴",
      bottomRight: "╯"
    )
  }
}

/// Resolved collection presentation shared by list and table payloads.
public struct CollectionStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var listContainer: CollectionContainerChromePresentation?
  public var listChromeScope: ListChromeScope
  public var listContentInsets: EdgeInsets
  public var showsListRowSeparators: Bool
  public var showsListSectionSeparators: Bool
  public var tableBorderGlyphs: TableBorderGlyphs
  public var tableHeaderForegroundStyle: AnyShapeStyle?
  public var tableHeaderBackgroundStyle: AnyShapeStyle?

  public init(
    snapshotLabel: String = "",
    listContainer: CollectionContainerChromePresentation? = nil,
    listChromeScope: ListChromeScope = .wholeList,
    listContentInsets: EdgeInsets = .zero,
    showsListRowSeparators: Bool = true,
    showsListSectionSeparators: Bool = true,
    tableBorderGlyphs: TableBorderGlyphs = .plain,
    tableHeaderForegroundStyle: AnyShapeStyle? = nil,
    tableHeaderBackgroundStyle: AnyShapeStyle? = nil
  ) {
    self.snapshotLabel = snapshotLabel
    self.listContainer = listContainer
    self.listChromeScope = listChromeScope
    self.listContentInsets = listContentInsets
    self.showsListRowSeparators = showsListRowSeparators
    self.showsListSectionSeparators = showsListSectionSeparators
    self.tableBorderGlyphs = tableBorderGlyphs
    self.tableHeaderForegroundStyle = tableHeaderForegroundStyle
    self.tableHeaderBackgroundStyle = tableHeaderBackgroundStyle
  }

  public var description: String {
    snapshotLabel.isEmpty ? "CollectionStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  public static var plain: Self {
    .init(
      snapshotLabel: "CollectionStylePresentation.plain",
      listContainer: nil,
      listContentInsets: .zero,
      showsListRowSeparators: true,
      showsListSectionSeparators: true,
      tableBorderGlyphs: .plain,
      tableHeaderForegroundStyle: .semantic(.muted),
      tableHeaderBackgroundStyle: nil
    )
  }

  public static var insetGrouped: Self {
    .init(
      snapshotLabel: "CollectionStylePresentation.insetGrouped",
      listContainer: .insetGrouped,
      listChromeScope: .eachSection,
      listContentInsets: .init(top: 1, leading: 1, bottom: 1, trailing: 1),
      showsListRowSeparators: false,
      showsListSectionSeparators: false,
      tableBorderGlyphs: .insetGrouped,
      tableHeaderForegroundStyle: AnyShapeStyle(.terminalBorder(.accent)),
      tableHeaderBackgroundStyle: AnyShapeStyle(.terminalRow(.neutral, isOdd: true))
    )
  }
}

extension CollectionStylePresentation {
  package func visibleListLayout(
    for payload: ListPayload,
    in bounds: CellRect
  ) -> ListVisibleLayout {
    let contentBounds = listContentBounds(in: bounds)
    let lines = visibleListLines(
      for: payload,
      viewportLineCount: contentBounds.size.height
    )

    return ListVisibleLayout(
      contentBounds: contentBounds,
      lines: lines,
      sectionChromeBounds: listChromeBounds(for: lines, in: contentBounds)
    )
  }

  package func listChromeBounds(
    for layout: ListVisibleLayout,
    in bounds: CellRect
  ) -> [CellRect] {
    guard listContainer != nil else {
      return []
    }

    switch listChromeScope {
    case .wholeList:
      return [bounds]
    case .eachSection:
      return layout.sectionChromeBounds
    }
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> CellSize {
    let horizontalInset = listContentInsets.leading + listContentInsets.trailing
    let perSectionVerticalInset = listContentInsets.top + listContentInsets.bottom
    let usesSectionChrome = listContainer != nil && listChromeScope == .eachSection
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
        if showsListRowSeparators,
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
        if showsListSectionSeparators, listSectionSeparatorIsVisible(item) {
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

  private func listContentBounds(
    in bounds: CellRect
  ) -> CellRect {
    let verticalInsets =
      listContainer != nil && listChromeScope == .eachSection
      ? (top: 0, bottom: 0)
      : (top: listContentInsets.top, bottom: listContentInsets.bottom)
    return CellRect(
      origin: .init(
        x: bounds.origin.x + listContentInsets.leading,
        y: bounds.origin.y + verticalInsets.top
      ),
      size: .init(
        width: max(0, bounds.size.width - listContentInsets.leading - listContentInsets.trailing),
        height: max(0, bounds.size.height - verticalInsets.top - verticalInsets.bottom)
      )
    )
  }

  private func visibleListLines(
    for payload: ListPayload,
    viewportLineCount: Int
  ) -> [ListDisplayLine] {
    let displayLines = materializedListLines(for: payload)
    guard viewportLineCount > 0 else {
      return []
    }

    if displayLines.count > viewportLineCount {
      let visibleLineCount =
        payload.showsIndicators && viewportLineCount >= 3
        ? max(1, viewportLineCount - 2)
        : viewportLineCount
      let selectedLineIndex = selectedListLineIndex(
        in: displayLines,
        selectedRowIndex: payload.selectedRowIndex
      )
      let lineIndex = min(
        max(selectedLineIndex ?? 0, 0),
        max(0, displayLines.count - 1)
      )
      let offset = min(
        max(0, lineIndex - (visibleLineCount / 2)),
        max(0, displayLines.count - visibleLineCount)
      )
      let end = min(displayLines.count, offset + visibleLineCount)
      guard payload.showsIndicators, viewportLineCount >= 3 else {
        return Array(displayLines[offset..<end])
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
      return visible
    }

    return Array(displayLines.prefix(viewportLineCount))
  }

  private func materializedListLines(
    for payload: ListPayload
  ) -> [ListDisplayLine] {
    var lines: [ListDisplayLine] = []
    var sectionLines: [ListDisplayLine] = []
    var sectionIndex = 0
    var rowIndex = 0
    let usesSectionChrome = listContainer != nil && listChromeScope == .eachSection

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

      let spacerStyle = TextStyle(opacity: payload.opacity)
      lines.append(
        .init(
          kind: .text("", spacerStyle),
          isHeader: true,
          rowIndex: nil,
          sectionIndex: sectionIndex
        )
      )
      lines.append(
        contentsOf: sectionLines.map { line in
          var sectionLine = line
          sectionLine.sectionIndex = sectionIndex
          return sectionLine
        }
      )
      lines.append(
        .init(
          kind: .text("", spacerStyle),
          isHeader: true,
          rowIndex: nil,
          sectionIndex: sectionIndex
        )
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
            rowIndex: nil
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
            rowIndex: nil
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
            rowIndex: rowIndex
          )
        )

        if showsListRowSeparators,
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
        guard showsListSectionSeparators,
          listSectionSeparatorIsVisible(item)
        else {
          continue
        }
        lines.append(
          .init(
            kind: .separator(payload.borderStyle ?? .semantic(.separator)),
            isHeader: true,
            rowIndex: nil
          )
        )
      }
    }

    if usesSectionChrome {
      flushSection()
      if payload.items.isEmpty {
        let spacerStyle = TextStyle(opacity: payload.opacity)
        lines.append(
          .init(
            kind: .text("", spacerStyle),
            isHeader: true,
            rowIndex: nil,
            sectionIndex: sectionIndex
          )
        )
        lines.append(
          .init(
            kind: .text("", spacerStyle),
            isHeader: true,
            rowIndex: nil,
            sectionIndex: sectionIndex
          )
        )
      }
    }

    return lines
  }

  private func listChromeBounds(
    for lines: [ListDisplayLine],
    in contentBounds: CellRect
  ) -> [CellRect] {
    guard listContainer != nil, listChromeScope == .eachSection, !lines.isEmpty else {
      return []
    }

    var bounds: [CellRect] = []
    var rangeStart: Int?
    var activeSectionIndex: Int?

    func appendRange(endingAt endIndex: Int) {
      guard let start = rangeStart else {
        return
      }
      bounds.append(
        CellRect(
          origin: .init(
            x: contentBounds.origin.x - listContentInsets.leading,
            y: contentBounds.origin.y + start
          ),
          size: .init(
            width: contentBounds.size.width + listContentInsets.leading
              + listContentInsets.trailing,
            height: endIndex - start
          )
        )
      )
    }

    for (index, line) in lines.enumerated() {
      guard let sectionIndex = line.sectionIndex else {
        appendRange(endingAt: index)
        rangeStart = nil
        activeSectionIndex = nil
        continue
      }

      if activeSectionIndex != sectionIndex {
        appendRange(endingAt: index)
        rangeStart = index
        activeSectionIndex = sectionIndex
      }
    }

    appendRange(endingAt: lines.count)
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

/// Resolved outline connector and indentation strings.
public struct OutlineStylePresentation:
  Equatable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var snapshotLabel: String
  public var continuingIndenter: String
  public var emptyIndenter: String
  public var branchConnector: String
  public var leafConnector: String

  public init(
    snapshotLabel: String = "",
    continuingIndenter: String,
    emptyIndenter: String,
    branchConnector: String,
    leafConnector: String
  ) {
    self.snapshotLabel = snapshotLabel
    self.continuingIndenter = continuingIndenter
    self.emptyIndenter = emptyIndenter
    self.branchConnector = branchConnector
    self.leafConnector = leafConnector
  }

  public var description: String {
    snapshotLabel.isEmpty ? "OutlineStylePresentation" : snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  public static var rounded: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.rounded",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "╰─ "
    )
  }

  public static var plain: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.plain",
      continuingIndenter: "│ ",
      emptyIndenter: "  ",
      branchConnector: "├─ ",
      leafConnector: "└─ "
    )
  }

  public static var ascii: Self {
    .init(
      snapshotLabel: "OutlineStylePresentation.ascii",
      continuingIndenter: "| ",
      emptyIndenter: "  ",
      branchConnector: "|- ",
      leafConnector: "`- "
    )
  }
}
