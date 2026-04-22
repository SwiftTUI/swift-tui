/// Horizontal alignment for cells and headers in a table column.
public enum TableColumnAlignment: Hashable, Sendable {
  case leading
  case center
  case trailing
}

/// Controls whether a table shows its header row.
public enum TableHeaderVisibility: Hashable, Sendable {
  case automatic
  case visible
  case hidden
}

/// Controls whether scroll indicators are shown for a scroll view.
public enum ScrollIndicatorVisibility: Hashable, Sendable {
  case automatic
  case visible
  case hidden
}

/// Controls the border geometry used for bordered buttons.
public enum ButtonBorderShape: Hashable, Sendable {
  case automatic
  case roundedRectangle
}
