/// Per-row separator visibility preferences for low-level list payloads.
public struct ListSeparatorPreferences: Equatable, Sendable {
  public var top: Visibility?
  public var bottom: Visibility?

  public init(
    top: Visibility? = nil,
    bottom: Visibility? = nil
  ) {
    self.top = top
    self.bottom = bottom
  }
}

/// A single rendered item within a low-level list payload.
public struct ListItemPayload: Equatable, Sendable {
  /// The semantic role of a list item.
  public enum Kind: String, Equatable, Sendable {
    case header
    case footer
    case row
    case sectionBreak
  }

  public var kind: Kind
  public var text: String
  public var style: TextStyle
  public var rowForegroundStyle: AnyShapeStyle?
  public var rowBackgroundStyle: AnyShapeStyle?
  public var rowSeparators: ListSeparatorPreferences
  public var sectionSeparators: ListSeparatorPreferences

  public init(
    kind: Kind,
    text: String,
    style: TextStyle = .init(),
    rowForegroundStyle: AnyShapeStyle? = nil,
    rowBackgroundStyle: AnyShapeStyle? = nil,
    rowSeparators: ListSeparatorPreferences = .init(),
    sectionSeparators: ListSeparatorPreferences = .init()
  ) {
    self.kind = kind
    self.text = text
    self.style = style
    self.rowForegroundStyle = rowForegroundStyle
    self.rowBackgroundStyle = rowBackgroundStyle
    self.rowSeparators = rowSeparators
    self.sectionSeparators = sectionSeparators
  }
}

/// Low-level payload used to draw lists in the render pipeline.
public struct ListPayload: Equatable, Sendable {
  public var items: [ListItemPayload]
  public var selectedRowIndex: Int?
  public var style: CollectionStylePresentation
  public var foregroundStyle: AnyShapeStyle?
  public var backgroundStyle: AnyShapeStyle?
  public var borderStyle: AnyShapeStyle?
  public var selectedRowForegroundStyle: AnyShapeStyle?
  public var selectedRowBackgroundStyle: AnyShapeStyle?
  public var selectedRowMarkerStyle: AnyShapeStyle?
  public var showsSelectionMarker: Bool
  public var showsIndicators: Bool
  public var opacity: Double
  package var isViewportBacked: Bool = false
  /// The stored scroll currency: the dataset row pinned to the top of the
  /// viewport. `nil` keeps the historical selection-centred window, which is
  /// what payload-only callers of the public `init` get — `ListPayload` is
  /// public API and its behaviour must not change because a `package` field
  /// was added. Carried on the payload (rather than through a side channel)
  /// so an anchor change denies retained-measurement reuse through payload
  /// equality, the same channel selection changes already use.
  package var scrollAnchorRowIndex: Int?

  public init(
    items: [ListItemPayload],
    selectedRowIndex: Int?,
    style: CollectionStylePresentation,
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil,
    selectedRowForegroundStyle: AnyShapeStyle? = nil,
    selectedRowBackgroundStyle: AnyShapeStyle? = nil,
    selectedRowMarkerStyle: AnyShapeStyle? = nil,
    showsSelectionMarker: Bool = true,
    showsIndicators: Bool = true,
    opacity: Double = 1
  ) {
    self.items = items
    self.selectedRowIndex = selectedRowIndex
    self.style = style
    self.foregroundStyle = foregroundStyle
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
    self.selectedRowForegroundStyle = selectedRowForegroundStyle
    self.selectedRowBackgroundStyle = selectedRowBackgroundStyle
    self.selectedRowMarkerStyle = selectedRowMarkerStyle
    self.showsSelectionMarker = showsSelectionMarker
    self.showsIndicators = showsIndicators
    self.opacity = opacity
  }
}
