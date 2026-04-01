/// A style that controls how text fields are rendered.
public enum TextFieldStyle: Hashable, Sendable {
  case automatic
  case plain
  case roundedBorder
}

/// A style that controls how pickers present their options.
public enum PickerStyle: Hashable, Sendable {
  case automatic
  case inline
  case segmented
  case radioGroup
  case menu
}

/// A style that controls the chrome and separators used by lists and tables.
public enum ListStyle: Hashable, Sendable {
  case automatic
  case plain
  case insetGrouped
}

/// A style that controls the disclosure treatment of outline views.
public enum OutlineStyle: Hashable, Sendable {
  case automatic
  case rounded
  case plain
  case ascii
}

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

/// A style that controls how tab views render their tab bar.
public enum TabViewStyle: Hashable, Sendable {
  /// Default underline-based tab indicator.
  case automatic
  /// Differently weighted underlines to indicate selection and focus.
  case underline
  /// Unicode box-drawing tab shapes.
  case rounded
  /// Powerline-inspired background fills with angled separators.
  case powerline
}

/// Controls the border geometry used for bordered buttons.
public enum ButtonBorderShape: Hashable, Sendable {
  case automatic
  case roundedRectangle
}
