extension LayoutEngine {
  package func measuredListSize(
    for payload: ListPayload,
    proposal: ProposedSize
  ) -> Size {
    let idealSize = measuredListIdealSize(for: payload)

    return Size(
      width: resolvedExpandingListDimension(idealSize.width, proposal: proposal.width),
      height: resolvedExpandingListDimension(idealSize.height, proposal: proposal.height)
    )
  }

  package func measuredListIdealSize(
    for payload: ListPayload
  ) -> Size {
    let horizontalInset =
      payload.style.listContentInsets.leading + payload.style.listContentInsets.trailing
    let verticalInset =
      payload.style.listContentInsets.top + payload.style.listContentInsets.bottom
    let lineMetrics = payload.items.enumerated().reduce(
      into: (width: 0, height: 0, rowIndex: 0)
    ) { partial, element in
      let (index, item) = element
      switch item.kind {
      case .header, .footer:
        partial.width = max(
          partial.width, layoutText(for: item.text, width: nil).size.width)
        partial.height += 1
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
        if payload.style.showsListRowSeparators,
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
        if payload.style.showsListSectionSeparators, listSectionSeparatorIsVisible(item) {
          partial.height += 1
          partial.width = max(partial.width, 1)
        }
      }
    }

    return Size(
      width: lineMetrics.width + horizontalInset,
      height: lineMetrics.height + verticalInset
    )
  }

  package func resolvedListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return min(max(ideal, 0), value)
    }
  }

  package func resolvedExpandingListDimension(
    _ ideal: Int,
    proposal: ProposedDimension
  ) -> Int {
    switch proposal {
    case .unspecified, .infinity:
      return ideal
    case .finite(let value):
      return max(0, value)
    }
  }

  package func listSectionSeparatorIsVisible(
    _ item: ListItemPayload
  ) -> Bool {
    let bottom = item.sectionSeparators.bottom
    let top = item.sectionSeparators.top
    if bottom == .hidden || top == .hidden {
      return false
    }
    return true
  }

  package func listRowSeparatorIsVisible(
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
}
