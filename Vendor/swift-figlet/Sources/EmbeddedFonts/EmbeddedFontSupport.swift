public import SwiftFiglet

public extension Figlet {
    init(
        embeddedFont font: FigletFont = .standard,
        configuration: FigletConfiguration = FigletConfiguration()
    ) throws {
        try self.init(
            fontNamed: font.rawValue,
            configuration: configuration,
            fontLibrary: FigletFont.library
        )
    }
}
