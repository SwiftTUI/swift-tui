@_exported import EmbeddedFonts
@_spi(Testing) public import SwiftTUICore

/// Displays ASCII-art text using embedded FIGlet fonts.
public struct TextFigure: PrimitiveView, ResolvableView {
  public typealias Font = EmbeddedFigletFont
  public typealias ColorMode = TextFigureColorMode

  public var content: String
  public var font: Font
  public var colorMode: ColorMode

  public init(
    _ content: String,
    font: Font = .standard,
    colorMode: ColorMode = .authored
  ) {
    self.content = content
    self.font = font
    self.colorMode = colorMode
  }

  public static var availableFonts: [Font] {
    Font.allCases
  }

  public func textFigureColorMode(_ colorMode: ColorMode) -> Self {
    var copy = self
    copy.colorMode = colorMode
    return copy
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: "TextFigure",
        drawPayload: .textFigure(
          .init(
            content: content,
            font: font,
            colorMode: colorMode
          )
        ),
        in: context
      )
    ]
  }
}
