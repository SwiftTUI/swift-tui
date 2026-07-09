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
