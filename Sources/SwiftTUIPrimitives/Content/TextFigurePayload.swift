@_exported import EmbeddedFonts

public typealias TextFigureFont = EmbeddedFigletFont

public struct TextFigureColorMode: Equatable, Sendable {
  package enum Storage: Equatable, Sendable {
    case authored
    case fillUnstyled(AnyShapeStyle?)
    case monochrome
    case override(AnyShapeStyle?)
    case tinted(AnyShapeStyle?)
  }

  package var storage: Storage

  public static let authored = Self(storage: .authored)
  public static let fillUnstyled = Self(storage: .fillUnstyled(nil))
  public static let monochrome = Self(storage: .monochrome)
  public static let `override` = Self(storage: .override(nil))
  public static let tinted = Self(storage: .tinted(nil))

  public static func fillUnstyled<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .fillUnstyled(AnyShapeStyle(style)))
  }

  public static func `override`<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .override(AnyShapeStyle(style)))
  }

  public static func tinted<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .tinted(AnyShapeStyle(style)))
  }
}

public struct TextFigurePayload: Equatable, Hashable, Sendable {
  public var content: String
  public var font: TextFigureFont
  public var colorMode: TextFigureColorMode

  public init(
    content: String,
    font: TextFigureFont,
    colorMode: TextFigureColorMode = .authored
  ) {
    self.content = content
    self.font = font
    self.colorMode = colorMode
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(content)
    hasher.combine(font)
  }
}
