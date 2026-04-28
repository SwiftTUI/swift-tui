/// The payload attached to a draw node.
@_spi(Testing) public indirect enum DrawPayload: Equatable, Sendable {
  case none
  case text(String)
  case textFigure(TextFigurePayload)
  case richText(RichTextPayload)
  case image(ImagePayload)
  case shape(ShapePayload)
  case rule(StrokeStyle?)
  case list(ListPayload)
  case table(TablePayload)
  case canvas(CanvasPayload)
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
package struct DrawMetadata: Equatable, Sendable {
  /// List-specific styling preferences carried by draw metadata.
  package struct ListStyleMetadata: Equatable, Sendable {
    package var rowForegroundStyle: AnyShapeStyle?
    package var rowBackgroundStyle: AnyShapeStyle?
    package var rowSeparatorTopVisibility: Visibility?
    package var rowSeparatorBottomVisibility: Visibility?
    package var sectionSeparatorTopVisibility: Visibility?
    package var sectionSeparatorBottomVisibility: Visibility?

    package init(
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

    package var isDefault: Bool {
      rowForegroundStyle == nil
        && rowBackgroundStyle == nil
        && rowSeparatorTopVisibility == nil
        && rowSeparatorBottomVisibility == nil
        && sectionSeparatorTopVisibility == nil
        && sectionSeparatorBottomVisibility == nil
    }

    package func merging(_ other: Self) -> Self {
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

  package struct HeavyFields: Equatable, Sendable {
    var baseStyle: BaseStyle
    var borderShapeStyle: AnyShapeStyle?
    var borderStrokeStyle: StrokeStyle?
    var scrollIndicatorAxes: AxisSet?
    var focusedScrollIndicatorAxes: AxisSet?
    var scrollIndicatorForegroundStyle: AnyShapeStyle?
    var listStyle: ListStyleMetadata?

    init(
      foregroundStyle: AnyShapeStyle? = nil,
      backgroundStyle: AnyShapeStyle? = nil,
      borderShapeStyle: AnyShapeStyle? = nil,
      borderStrokeStyle: StrokeStyle? = nil,
      scrollIndicatorAxes: AxisSet? = nil,
      focusedScrollIndicatorAxes: AxisSet? = nil,
      scrollIndicatorForegroundStyle: AnyShapeStyle? = nil,
      listStyle: ListStyleMetadata? = nil,
      emphasis: TextStyle.TextEmphasis = [],
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
      self.borderShapeStyle = borderShapeStyle
      self.borderStrokeStyle = borderStrokeStyle
      self.scrollIndicatorAxes = scrollIndicatorAxes
      self.focusedScrollIndicatorAxes = focusedScrollIndicatorAxes
      self.scrollIndicatorForegroundStyle = scrollIndicatorForegroundStyle
      self.listStyle = listStyle
    }

    func merging(_ other: Self) -> Self {
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
      return merged
    }
  }

  package var heavyFields: Boxed<HeavyFields>
  package var clipsToBounds: Bool
  package var clipIdentifier: String?
  package var compositingHint: String?
  package var imagePreference: String?
  package var ruleStackAxis: Axis?

  package init(
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
    heavyFields = Boxed(
      HeavyFields(
        foregroundStyle: foregroundStyle,
        backgroundStyle: backgroundStyle,
        borderShapeStyle: borderShapeStyle,
        borderStrokeStyle: borderStrokeStyle,
        scrollIndicatorAxes: scrollIndicatorAxes,
        focusedScrollIndicatorAxes: focusedScrollIndicatorAxes,
        scrollIndicatorForegroundStyle: scrollIndicatorForegroundStyle,
        listStyle: resolvedListStyle.isDefault ? nil : resolvedListStyle,
        emphasis: emphasis,
        underlineStyle: underlineStyle,
        strikethroughStyle: strikethroughStyle,
        opacity: opacity
      )
    )
    self.clipsToBounds = clipsToBounds
    self.clipIdentifier = clipIdentifier
    self.compositingHint = compositingHint
    self.imagePreference = imagePreference
    ruleStackAxis = nil
  }

  package var baseStyle: BaseStyle {
    get { heavyFields.value.baseStyle }
    set { heavyFields.value.baseStyle = newValue }
  }

  package var foregroundStyle: AnyShapeStyle? {
    get { baseStyle.foregroundStyle }
    set { baseStyle.foregroundStyle = newValue }
  }

  package var backgroundStyle: AnyShapeStyle? {
    get { baseStyle.backgroundStyle }
    set { baseStyle.backgroundStyle = newValue }
  }

  package var emphasis: TextStyle.TextEmphasis {
    get { baseStyle.emphasis }
    set { baseStyle.emphasis = newValue }
  }

  package var underlineStyle: TextLineStyle? {
    get { baseStyle.underlineStyle }
    set { baseStyle.underlineStyle = newValue }
  }

  package var strikethroughStyle: TextLineStyle? {
    get { baseStyle.strikethroughStyle }
    set { baseStyle.strikethroughStyle = newValue }
  }

  package var opacity: Double {
    get { baseStyle.opacity }
    set { baseStyle.opacity = newValue }
  }

  package var explicitOpacity: Double? {
    get { baseStyle.explicitOpacity }
    set { baseStyle.explicitOpacity = newValue }
  }

  package var listRowForegroundStyle: AnyShapeStyle? {
    get { listStyle?.rowForegroundStyle }
    set {
      var updated = listStyle ?? .init()
      updated.rowForegroundStyle = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowBackgroundStyle: AnyShapeStyle? {
    get { listStyle?.rowBackgroundStyle }
    set {
      var updated = listStyle ?? .init()
      updated.rowBackgroundStyle = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowSeparatorTopVisibility: Visibility? {
    get { listStyle?.rowSeparatorTopVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.rowSeparatorTopVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listRowSeparatorBottomVisibility: Visibility? {
    get { listStyle?.rowSeparatorBottomVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.rowSeparatorBottomVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listSectionSeparatorTopVisibility: Visibility? {
    get { listStyle?.sectionSeparatorTopVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.sectionSeparatorTopVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package var listSectionSeparatorBottomVisibility: Visibility? {
    get { listStyle?.sectionSeparatorBottomVisibility }
    set {
      var updated = listStyle ?? .init()
      updated.sectionSeparatorBottomVisibility = newValue
      listStyle = updated.isDefault ? nil : updated
    }
  }

  package func merging(_ other: Self) -> Self {
    var merged = self
    merged.heavyFields.value = heavyFields.value.merging(other.heavyFields.value)
    merged.clipsToBounds = clipsToBounds || other.clipsToBounds
    merged.clipIdentifier = other.clipIdentifier ?? clipIdentifier
    merged.compositingHint = other.compositingHint ?? compositingHint
    merged.imagePreference = other.imagePreference ?? imagePreference
    merged.ruleStackAxis = other.ruleStackAxis ?? ruleStackAxis
    return merged
  }

  package var borderShapeStyle: AnyShapeStyle? {
    get { heavyFields.value.borderShapeStyle }
    set { heavyFields.value.borderShapeStyle = newValue }
  }

  package var borderStrokeStyle: StrokeStyle? {
    get { heavyFields.value.borderStrokeStyle }
    set { heavyFields.value.borderStrokeStyle = newValue }
  }

  package var scrollIndicatorAxes: AxisSet? {
    get { heavyFields.value.scrollIndicatorAxes }
    set { heavyFields.value.scrollIndicatorAxes = newValue }
  }

  package var focusedScrollIndicatorAxes: AxisSet? {
    get { heavyFields.value.focusedScrollIndicatorAxes }
    set { heavyFields.value.focusedScrollIndicatorAxes = newValue }
  }

  package var scrollIndicatorForegroundStyle: AnyShapeStyle? {
    get { heavyFields.value.scrollIndicatorForegroundStyle }
    set { heavyFields.value.scrollIndicatorForegroundStyle = newValue }
  }

  package var listStyle: ListStyleMetadata? {
    get { heavyFields.value.listStyle }
    set { heavyFields.value.listStyle = newValue }
  }
}

private protocol SelectionTagValueBox: Sendable {
  var baseValue: Any { get }

  func isEqual(
    to other: any SelectionTagValueBox
  ) -> Bool
}

private struct TypedSelectionTagValueBox<Value: Hashable & Sendable>: SelectionTagValueBox {
  let value: Value

  var baseValue: Any {
    value
  }

  func isEqual(
    to other: any SelectionTagValueBox
  ) -> Bool {
    guard let otherValue = other.baseValue as? Value else {
      return false
    }
    return otherValue == value
  }
}

/// A type-erased selection identity used by lists, tables, and pickers.
public struct SelectionTag: Equatable, Sendable {
  private let valueBox: any SelectionTagValueBox
  public var includeOptional: Bool

  public init<Value: Hashable & Sendable>(
    value: Value,
    includeOptional: Bool = true
  ) {
    valueBox = TypedSelectionTagValueBox(value: value)
    self.includeOptional = includeOptional
  }

  package func value<Value>(
    as _: Value.Type = Value.self
  ) -> Value? {
    valueBox.baseValue as? Value
  }

  package var baseValue: Any {
    valueBox.baseValue
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.includeOptional == rhs.includeOptional
      && lhs.valueBox.isEqual(to: rhs.valueBox)
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
