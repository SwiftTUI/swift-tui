public import swift_figlet

public extension SwiftFigletEmbeddedFonts {
    static var fonts: [Font] {
        Font.allCases
    }
}

public extension FigletFont {
    init(embeddedFont font: SwiftFigletEmbeddedFonts.Font) throws {
        try self.init(named: font.rawValue, fontLibrary: SwiftFigletEmbeddedFonts.library)
    }
}

public extension Figlet {
    init(
        embeddedFont font: SwiftFigletEmbeddedFonts.Font = .standard,
        configuration: FigletConfiguration = FigletConfiguration()
    ) throws {
        try self.init(
            fontNamed: font.rawValue,
            configuration: configuration,
            fontLibrary: SwiftFigletEmbeddedFonts.library
        )
    }

    static var embeddedFonts: [SwiftFigletEmbeddedFonts.Font] {
        SwiftFigletEmbeddedFonts.fonts
    }
}
