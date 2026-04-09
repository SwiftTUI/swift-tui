package import Core
@_exported import EmbeddedFonts

/// Displays ASCII-art text using embedded FIGlet fonts.
public struct TextFigure: View, ResolvableView {
  public typealias Font = EmbeddedFigletFont

  public var content: String
  public var font: Font

  public init(
    _ content: String,
    font: Font = .standard
  ) {
    self.content = content
    self.font = font
  }

  public static var availableFonts: [Font] {
    Font.allCases
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
            font: font
          )
        ),
        in: context
      )
    ]
  }
}
