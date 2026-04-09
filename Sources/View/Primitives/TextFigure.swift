package import Core

/// Displays ASCII-art text using embedded FIGlet fonts.
public struct TextFigure: View, ResolvableView {
  public var content: String
  public var font: String

  public init(
    _ content: String,
    font: String = "standard"
  ) {
    self.content = content
    self.font = font
  }

  public static var availableFonts: [String] {
    TextFigureSupport.availableFonts
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let drawPayload: DrawPayload
    if TextFigureSupport.supportsFont(named: font) {
      drawPayload = .textFigure(
        .init(
          content: content,
          font: font
        )
      )
    } else {
      reportTextFigureConfigurationError("Unknown TextFigure font '\(font)'")
      drawPayload = .text(content)
    }

    return [
      resolveLeafNode(
        kindName: "TextFigure",
        drawPayload: drawPayload,
        in: context
      )
    ]
  }
}
