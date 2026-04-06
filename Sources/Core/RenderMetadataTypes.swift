/// The payload attached to a draw node.
public enum DrawPayload: Equatable, Sendable {
  case none
  case text(String)
  case richText(RichTextPayload)
  case image(ImagePayload)
  case shape(ShapePayload)
  case rule(StrokeStyle?)
  case list(ListPayload)
  case table(TablePayload)
}

/// Truncation strategy used when text exceeds its available width.
public enum TextTruncationMode: String, Equatable, Hashable, Sendable {
  case head
  case middle
  case tail
}

/// Wrapping strategy used during text layout.
public enum TextWrappingStrategy: String, Equatable, Hashable, Sendable {
  case wordBoundary
}

/// Text styling metadata before semantic styles are resolved.
public struct TextStyle: Equatable, Sendable {
  /// Text emphasis flags such as bold or italic.
  public struct TextEmphasis: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    public static let bold = Self(rawValue: 1 << 0)
    public static let italic = Self(rawValue: 1 << 1)
    public static let faint = Self(rawValue: 1 << 2)
    public static let blink = Self(rawValue: 1 << 3)
    public static let reverse = Self(rawValue: 1 << 4)

    public var debugNames: [String] {
      var names: [String] = []
      if contains(.bold) {
        names.append("bold")
      }
      if contains(.italic) {
        names.append("italic")
      }
      if contains(.faint) {
        names.append("faint")
      }
      if contains(.blink) {
        names.append("blink")
      }
      if contains(.reverse) {
        names.append("reverse")
      }
      return names
    }

  }

  public var baseStyle: BaseStyle

  public init(
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    emphasis: TextEmphasis = [],
    underlineStyle: TextLineStyle? = nil,
    strikethroughStyle: TextLineStyle? = nil,
    opacity: Double? = nil
  ) {
    baseStyle = .init(
      foregroundStyle: foregroundStyle,
      backgroundStyle: backgroundStyle,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  public var foregroundStyle: AnyShapeStyle? {
    get { baseStyle.foregroundStyle }
    set { baseStyle.foregroundStyle = newValue }
  }

  public var backgroundStyle: AnyShapeStyle? {
    get { baseStyle.backgroundStyle }
    set { baseStyle.backgroundStyle = newValue }
  }

  public var emphasis: TextEmphasis {
    get { baseStyle.emphasis }
    set { baseStyle.emphasis = newValue }
  }

  public var underlineStyle: TextLineStyle? {
    get { baseStyle.underlineStyle }
    set { baseStyle.underlineStyle = newValue }
  }

  public var strikethroughStyle: TextLineStyle? {
    get { baseStyle.strikethroughStyle }
    set { baseStyle.strikethroughStyle = newValue }
  }

  public var opacity: Double {
    get { baseStyle.opacity }
    set { baseStyle.opacity = newValue }
  }

  public var explicitOpacity: Double? {
    get { baseStyle.explicitOpacity }
    set { baseStyle.explicitOpacity = newValue }
  }

  public var isDefault: Bool {
    baseStyle.isDefault
  }
}

/// Shared style fields used by text and draw metadata.
public struct BaseStyle: Equatable, Sendable {
  public var foregroundStyle: AnyShapeStyle?
  public var backgroundStyle: AnyShapeStyle?
  public var emphasis: TextStyle.TextEmphasis
  public var underlineStyle: TextLineStyle?
  public var strikethroughStyle: TextLineStyle?
  public var explicitOpacity: Double?

  public init(
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    emphasis: TextStyle.TextEmphasis = [],
    underlineStyle: TextLineStyle? = nil,
    strikethroughStyle: TextLineStyle? = nil,
    opacity: Double? = nil
  ) {
    self.foregroundStyle = foregroundStyle
    self.backgroundStyle = backgroundStyle
    self.emphasis = emphasis
    self.underlineStyle = underlineStyle
    self.strikethroughStyle = strikethroughStyle
    explicitOpacity = opacity
  }

  public var opacity: Double {
    get { explicitOpacity ?? 1 }
    set { explicitOpacity = newValue }
  }

  public var isDefault: Bool {
    foregroundStyle == nil
      && backgroundStyle == nil
      && emphasis.isEmpty
      && underlineStyle == nil
      && strikethroughStyle == nil
      && explicitOpacity == nil
  }

  public func merging(_ other: Self) -> Self {
    var merged = self
    merged.foregroundStyle = other.foregroundStyle ?? foregroundStyle
    merged.backgroundStyle = other.backgroundStyle ?? backgroundStyle
    merged.emphasis.formUnion(other.emphasis)
    merged.underlineStyle = other.underlineStyle ?? underlineStyle
    merged.strikethroughStyle = other.strikethroughStyle ?? strikethroughStyle
    if let opacity = other.explicitOpacity {
      merged.explicitOpacity = opacity
    }
    return merged
  }
}

/// Visual metadata attached to a resolved node before draw extraction.
public struct DrawMetadata: Equatable, Sendable {
  /// List-specific styling preferences carried by draw metadata.
  public struct ListStyleMetadata: Equatable, Sendable {
    public var rowForegroundStyle: AnyShapeStyle?
    public var rowBackgroundStyle: AnyShapeStyle?
    public var rowSeparatorTopVisibility: Visibility?
    public var rowSeparatorBottomVisibility: Visibility?
    public var sectionSeparatorTopVisibility: Visibility?
    public var sectionSeparatorBottomVisibility: Visibility?

    public init(
      rowForegroundStyle: AnyShapeStyle? = nil,
      rowBackgroundStyle: AnyShapeStyle? = nil,
      rowSeparatorTopVisibility: Visibility? = nil,
      rowSeparatorBottomVisibility: Visibility? = nil,
      sectionSeparatorTopVisibility: Visibility? = nil,
      sectionSeparatorBottomVisibility: Visibility? = nil
    ) {
      self.rowForegroundStyle = rowForegroundStyle
      self.rowBackgroundStyle = rowBackgroundStyle
      self.rowSeparatorTopVisibility = rowSeparatorTopVisibility
      self.rowSeparatorBottomVisibility = rowSeparatorBottomVisibility
      self.sectionSeparatorTopVisibility = sectionSeparatorTopVisibility
      self.sectionSeparatorBottomVisibility = sectionSeparatorBottomVisibility
    }

    public var isDefault: Bool {
      rowForegroundStyle == nil
        && rowBackgroundStyle == nil
        && rowSeparatorTopVisibility == nil
        && rowSeparatorBottomVisibility == nil
        && sectionSeparatorTopVisibility == nil
        && sectionSeparatorBottomVisibility == nil
    }

    public func merging(_ other: Self) -> Self {
      .init(
        rowForegroundStyle: other.rowForegroundStyle ?? rowForegroundStyle,
        rowBackgroundStyle: other.rowBackgroundStyle ?? rowBackgroundStyle,
        rowSeparatorTopVisibility: other.rowSeparatorTopVisibility ?? rowSeparatorTopVisibility,
        rowSeparatorBottomVisibility: other.rowSeparatorBottomVisibility
          ?? rowSeparatorBottomVisibility,
        sectionSeparatorTopVisibility: other.sectionSeparatorTopVisibility
          ?? sectionSeparatorTopVisibility,
        sectionSeparatorBottomVisibility: other.sectionSeparatorBottomVisibility
          ?? sectionSeparatorBottomVisibility
      )
    }
  }

  public var baseStyle: BaseStyle
  public var borderShapeStyle: AnyShapeStyle?
  public var borderStrokeStyle: StrokeStyle?
  public var scrollIndicatorAxes: AxisSet?
  public var focusedScrollIndicatorAxes: AxisSet?
  public var scrollIndicatorForegroundStyle: AnyShapeStyle?
  public var listStyle: ListStyleMetadata?
  public var clipsToBounds: Bool
  public var clipIdentifier: String?
  public var compositingHint: String?
  public var imagePreference: String?
  package var ruleStackAxis: Axis?

  public init(
    foregroundStyle: AnyShapeStyle? = nil,
    backgroundStyle: AnyShapeStyle? = nil,
    borderShapeStyle: AnyShapeStyle? = nil,
    borderStrokeStyle: StrokeStyle? = nil,
    scrollIndicatorAxes: AxisSet? = nil,
    focusedScrollIndicatorAxes: AxisSet? = nil,
    scrollIndicatorForegroundStyle: AnyShapeStyle? = nil,
    listStyle: ListStyleMetadata? = nil,
    listRowForegroundStyle: AnyShapeStyle? = nil,
    listRowBackgroundStyle: AnyShapeStyle? = nil,
    listRowSeparatorTopVisibility: Visibility? = nil,
    listRowSeparatorBottomVisibility: Visibility? = nil,
    listSectionSeparatorTopVisibility: Visibility? = nil,
    listSectionSeparatorBottomVisibility: Visibility? = nil,
    emphasis: TextStyle.TextEmphasis = [],
    underlineStyle: TextLineStyle? = nil,
    strikethroughStyle: TextLineStyle? = nil,
    opacity: Double? = nil,
    clipsToBounds: Bool = false,
    clipIdentifier: String? = nil,
    compositingHint: String? = nil,
    imagePreference: String? = nil
  ) {
    baseStyle = .init(
      foregroundStyle: foregroundStyle,
      backgroundStyle: backgroundStyle,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
    self.borderShapeStyle = borderShapeStyle
    self.borderStrokeStyle = borderStrokeStyle
    self.scrollIndicatorAxes = scrollIndicatorAxes
    self.focusedScrollIndicatorAxes = focusedScrollIndicatorAxes
    self.scrollIndicatorForegroundStyle = scrollIndicatorForegroundStyle
    let resolvedListStyle =
      listStyle?.merging(
        .init(
          rowForegroundStyle: listRowForegroundStyle,
          rowBackgroundStyle: listRowBackgroundStyle,
          rowSeparatorTopVisibility: listRowSeparatorTopVisibility,
          rowSeparatorBottomVisibility: listRowSeparatorBottomVisibility,
          sectionSeparatorTopVisibility: listSectionSeparatorTopVisibility,
          sectionSeparatorBottomVisibility: listSectionSeparatorBottomVisibility
        )
      )
      ?? .init(
        rowForegroundStyle: listRowForegroundStyle,
        rowBackgroundStyle: listRowBackgroundStyle,
        rowSeparatorTopVisibility: listRowSeparatorTopVisibility,
        rowSeparatorBottomVisibility: listRowSeparatorBottomVisibility,
        sectionSeparatorTopVisibility: listSectionSeparatorTopVisibility,
        sectionSeparatorBottomVisibility: listSectionSeparatorBottomVisibility
      )
    self.listStyle = resolvedListStyle.isDefault ? nil : resolvedListStyle
    self.clipsToBounds = clipsToBounds
    self.clipIdentifier = clipIdentifier
    self.compositingHint = compositingHint
    self.imagePreference = imagePreference
    ruleStackAxis = nil
  }

  public var foregroundStyle: AnyShapeStyle? {
    get { baseStyle.foregroundStyle }
    set { baseStyle.foregroundStyle = newValue }
  }

  public var backgroundStyle: AnyShapeStyle? {
    get { baseStyle.backgroundStyle }
    set { baseStyle.backgroundStyle = newValue }
  }

  public var emphasis: TextStyle.TextEmphasis {
    get { baseStyle.emphasis }
    set { baseStyle.emphasis = newValue }
  }

  public var underlineStyle: TextLineStyle? {
    get { baseStyle.underlineStyle }
    set { baseStyle.underlineStyle = newValue }
  }

  public var strikethroughStyle: TextLineStyle? {
    get { baseStyle.strikethroughStyle }
    set { baseStyle.strikethroughStyle = newValue }
  }

  public var opacity: Double {
    get { baseStyle.opacity }
    set { baseStyle.opacity = newValue }
  }

  public var explicitOpacity: Double? {
    get { baseStyle.explicitOpacity }
    set { baseStyle.explicitOpacity = newValue }
  }

  public var listRowForegroundStyle: AnyShapeStyle? {
    get { listStyle?.rowForegroundStyle }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.rowForegroundStyle = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public var listRowBackgroundStyle: AnyShapeStyle? {
    get { listStyle?.rowBackgroundStyle }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.rowBackgroundStyle = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public var listRowSeparatorTopVisibility: Visibility? {
    get { listStyle?.rowSeparatorTopVisibility }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.rowSeparatorTopVisibility = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public var listRowSeparatorBottomVisibility: Visibility? {
    get { listStyle?.rowSeparatorBottomVisibility }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.rowSeparatorBottomVisibility = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public var listSectionSeparatorTopVisibility: Visibility? {
    get { listStyle?.sectionSeparatorTopVisibility }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.sectionSeparatorTopVisibility = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public var listSectionSeparatorBottomVisibility: Visibility? {
    get { listStyle?.sectionSeparatorBottomVisibility }
    set {
      var listStyle = self.listStyle ?? .init()
      listStyle.sectionSeparatorBottomVisibility = newValue
      self.listStyle = listStyle.isDefault ? nil : listStyle
    }
  }

  public func merging(_ other: Self) -> Self {
    var merged = self
    merged.baseStyle = baseStyle.merging(other.baseStyle)
    merged.borderShapeStyle = other.borderShapeStyle ?? borderShapeStyle
    merged.borderStrokeStyle = other.borderStrokeStyle ?? borderStrokeStyle
    merged.scrollIndicatorAxes = other.scrollIndicatorAxes ?? scrollIndicatorAxes
    merged.focusedScrollIndicatorAxes =
      other.focusedScrollIndicatorAxes ?? focusedScrollIndicatorAxes
    merged.scrollIndicatorForegroundStyle =
      other.scrollIndicatorForegroundStyle ?? scrollIndicatorForegroundStyle
    merged.listStyle =
      switch (listStyle, other.listStyle) {
      case (let lhs?, let rhs?):
        lhs.merging(rhs)
      case (_, let rhs?):
        rhs
      case (let lhs?, nil):
        lhs
      case (nil, nil):
        nil
      }
    merged.clipsToBounds = clipsToBounds || other.clipsToBounds
    merged.clipIdentifier = other.clipIdentifier ?? clipIdentifier
    merged.compositingHint = other.compositingHint ?? compositingHint
    merged.imagePreference = other.imagePreference ?? imagePreference
    merged.ruleStackAxis = other.ruleStackAxis ?? ruleStackAxis
    return merged
  }
}

/// A type-erased selection identity used by lists, tables, and pickers.
// SAFETY: Selection tags are authored from hashable values but stored in
// `AnyHashable`, which the compiler cannot prove Sendable through type
// erasure. The unsafe boundary is limited to the erased payload member.
public struct SelectionTag: Equatable, Sendable {
  nonisolated(unsafe) public var value: AnyHashable
  public var includeOptional: Bool

  public init(value: AnyHashable, includeOptional: Bool = true) {
    self.value = value
    self.includeOptional = includeOptional
  }
}

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
  public var style: ListStyle
  public var foregroundStyle: AnyShapeStyle?
  public var backgroundStyle: AnyShapeStyle?
  public var borderStyle: AnyShapeStyle?
  public var selectedRowForegroundStyle: AnyShapeStyle?
  public var selectedRowBackgroundStyle: AnyShapeStyle?
  public var selectedRowMarkerStyle: AnyShapeStyle?
  public var showsSelectionMarker: Bool
  public var showsIndicators: Bool
  public var opacity: Double

  public init(
    items: [ListItemPayload],
    selectedRowIndex: Int?,
    style: ListStyle,
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
