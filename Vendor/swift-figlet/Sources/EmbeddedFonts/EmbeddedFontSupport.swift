public import SwiftFiglet

extension Figlet {
  public init(
    embeddedFont font: EmbeddedFigletFont = .standard,
    configuration: FigletConfiguration = FigletConfiguration()
  ) throws {
    try self.init(
      fontNamed: font.rawValue,
      configuration: configuration,
      fontLibrary: EmbeddedFigletFont.library
    )
  }
}
