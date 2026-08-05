@_spi(Testing) public import SwiftTUICore
@_exported import SwiftTUIVendorFigletEmbeddedFonts

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
    // Ambient decorations reach banner output like any other text run (the
    // ambient text-LAYOUT attributes deliberately do not — figlet output is
    // preformatted). The figure has no per-value styling surface, so the
    // stamp is unconditional where the environment carries a value.
    var stampedDrawMetadata = DrawMetadata()
    let decorations = ambientTextDecorations(in: context)
    stampedDrawMetadata.underlineStyle = decorations.underline
    stampedDrawMetadata.strikethroughStyle = decorations.strikethrough
    return [
      resolveLeafNode(
        kindName: "TextFigure",
        drawMetadata: stampedDrawMetadata,
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
