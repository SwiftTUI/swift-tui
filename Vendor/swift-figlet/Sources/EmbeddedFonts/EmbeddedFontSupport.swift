public import SwiftFiglet

public extension Figlet {
    init(
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
