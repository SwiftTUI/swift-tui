import Testing
import swift_figlet
import swift_figlet_embedded_fonts

private let repositoryRoot = "/" + #filePath.split(separator: "/").dropLast(3).joined(separator: "/")
private let testDirectory = "/" + #filePath.split(separator: "/").dropLast().joined(separator: "/")
private let bundledFontsDirectory = repositoryRoot + "/Sources/swift-figlet/Resources/Fonts"
private let testOnlyFontData = #"""
flf2a$ 1 1 1 0 0
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
0@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
@@
"""# + "\n"

@Test func rendersBundledStandardFont() throws {
    let figlet = try Figlet(fontNamed: "standard", searchDirectories: [bundledFontsDirectory])
    let output = try figlet.render("Hi").description

    #expect(output == " _   _ _ \n| | | (_)\n| |_| | |\n|  _  | |\n|_| |_|_|\n         \n")
}

@Test func rendersBundledSlantFont() throws {
    let figlet = try Figlet(fontNamed: "slant", searchDirectories: [bundledFontsDirectory])
    let output = try figlet.render("Swift").description

    #expect(output == "   _____         _ ______ \n  / ___/      __(_) __/ /_\n  \\__ \\ | /| / / / /_/ __/\n ___/ / |/ |/ / / __/ /_  \n/____/|__/|__/_/_/  \\__/  \n                          \n")
}

@Test func wrapsAtWordBoundaries() throws {
    let figlet = try Figlet(
        fontNamed: "standard",
        configuration: FigletConfiguration(width: 20),
        searchDirectories: [bundledFontsDirectory]
    )

    let output = try figlet.render("hello world").description

    #expect(output == " _          _ _ \n| |__   ___| | |\n| '_ \\ / _ \\ | |\n| | | |  __/ | |\n|_| |_|\\___|_|_|\n                \n       \n  ___  \n / _ \\ \n| (_) |\n \\___/ \n       \n                    \n__      _____  _ __ \n\\ \\ /\\ / / _ \\| '__|\n \\ V  V / (_) | |   \n  \\_/\\_/ \\___/|_|   \n                    \n _     _ \n| | __| |\n| |/ _` |\n| | (_| |\n|_|\\__,_|\n         \n")
}

@Test func loadsExternalFontFiles() throws {
    let font = try FigletFont(filePath: testDirectory + "/Fixtures/TestOnly.flf")
    let figlet = Figlet(font: font)
    let output = try figlet.render("0").strippingSurroundingNewlines()

    #expect(output == "0")
}

@Test func loadsFontsFromFontLibraryObjects() throws {
    let fontLibrary = FigletFontLibrary(
        name: "Test Fixtures",
        fontData: ["TestOnly": testOnlyFontData]
    )

    let figlet = try Figlet(fontNamed: "TestOnly", fontLibrary: fontLibrary)
    let output = try figlet.render("0").strippingSurroundingNewlines()

    #expect(output == "0")
}

@Test func rendersEmbeddedStandardFontLibrary() throws {
    let figlet = try Figlet(embeddedFont: .standard)
    let output = try figlet.render("Hi").description

    #expect(output == " _   _ _ \n| | | (_)\n| |_| | |\n|  _  | |\n|_| |_|_|\n         \n")
}

@Test func reportsLayoutMetricsForEmbeddedFonts() throws {
    let figlet = try Figlet(embeddedFont: .standard)
    let metrics = try figlet.layoutMetrics(for: "Hi")

    #expect(metrics.minimumWidth == 8)
    #expect(metrics.idealSize == .init(width: 9, height: 6))
}

@Test func measuresRenderedSizeAtConcreteWidths() throws {
    let figlet = try Figlet(embeddedFont: .standard)

    #expect(try figlet.measure("Hi", forWidth: 80) == .init(width: 9, height: 6))
    #expect(try figlet.measure("Hi", forWidth: 8) == .init(width: 7, height: 12))
    #expect(try figlet.measure("hello world", forWidth: 20) == .init(width: 20, height: 24))
}

@Test func listsBundledFonts() {
    let fonts = FigletFont.availableFontNames(in: [bundledFontsDirectory])
    #expect(fonts.contains("slant"))
    #expect(fonts.contains("standard"))
    #expect(fonts.contains("banner"))
    #expect(fonts.contains("mono9"))
}

@Test func listsEmbeddedFonts() {
    let fonts = SwiftFigletEmbeddedFonts.fonts

    #expect(fonts.contains(.slant))
    #expect(fonts.contains(.standard))
    #expect(fonts.contains(.banner))
    #expect(fonts.contains(.mono9))
}

@Test func embeddedFontEnumMatchesTheGeneratedLibrary() {
    #expect(SwiftFigletEmbeddedFonts.fonts.map(\.rawValue) == SwiftFigletEmbeddedFonts.library.fontNames)
}
