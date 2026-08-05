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
///
/// An extensible struct rather than a closed enum, so future visibility
/// modes can be added without breaking exhaustive switches downstream.
public struct ScrollIndicatorVisibility: Hashable, Sendable {
  package enum Storage: Hashable, Sendable {
    case automatic
    case visible
    case hidden
    case never
  }

  package let storage: Storage

  private init(_ storage: Storage) {
    self.storage = storage
  }

  /// Shows indicators when the platform default calls for them.
  public static let automatic = Self(.automatic)

  /// Shows indicators while content overflows the viewport.
  public static let visible = Self(.visible)

  /// Hides indicators; the content stays scrollable.
  public static let hidden = Self(.hidden)

  /// Never shows indicators.
  public static let never = Self(.never)

  /// Whether this visibility allows indicators to be drawn at all.
  package var allowsVisibleIndicators: Bool {
    switch storage {
    case .automatic, .visible: true
    case .hidden, .never: false
    }
  }
}

/// Controls the border geometry used for bordered buttons.
public enum ButtonBorderShape: Hashable, Sendable {
  case automatic
  case roundedRectangle
}
