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
  /// The authored line limit carried from the flattened content, or `nil`
  /// for the single-line default. The windowed visible-layout math assumes
  /// single-line flattened items, so values above 1 are clamped at the
  /// payload-build site with a reported runtime issue.
  public var lineLimit: Int?
  /// The authored truncation mode carried from the flattened content, or
  /// `nil` for the `.tail` default.
  public var truncationMode: TextTruncationMode?

  public init(
    kind: Kind,
    text: String,
    style: TextStyle = .init(),
    rowForegroundStyle: AnyShapeStyle? = nil,
    rowBackgroundStyle: AnyShapeStyle? = nil,
    rowSeparators: ListSeparatorPreferences = .init(),
    sectionSeparators: ListSeparatorPreferences = .init(),
    lineLimit: Int? = nil,
    truncationMode: TextTruncationMode? = nil
  ) {
    self.kind = kind
    self.text = text
    self.style = style
    self.rowForegroundStyle = rowForegroundStyle
    self.rowBackgroundStyle = rowBackgroundStyle
    self.rowSeparators = rowSeparators
    self.sectionSeparators = sectionSeparators
    self.lineLimit = lineLimit
    self.truncationMode = truncationMode
  }
}

/// Low-level payload used to draw lists in the render pipeline.
public struct ListPayload: Equatable, Sendable {
  public var items: [ListItemPayload]
  public var selectedRowIndex: Int?
  public var style: ListStylePresentation
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
  /// Rows a viewport-backed payload stands for without materializing an entry
  /// per row in ``items``.
  ///
  /// A hosted collection's items were N *identical* stubs
  /// (`.init(kind: .row, text: "")`) — the rows themselves are committed child
  /// nodes, so the payload's copies carried no information but their count.
  /// Building and comparing that array was O(dataset) on the resolve path of
  /// every frame (register item D18). `nil` for payload-only callers, whose
  /// items are the real content.
  package var virtualRowCount: Int?

  /// Rows this payload describes, however they are stored.
  ///
  /// Every arithmetic path must read this rather than `items.count`: for a
  /// viewport-backed payload the two disagree, and `items.count` is the wrong
  /// one.
  package var rowCount: Int {
    virtualRowCount ?? items.count
  }

  public init(
    items: [ListItemPayload],
    selectedRowIndex: Int?,
    style: ListStylePresentation,
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
