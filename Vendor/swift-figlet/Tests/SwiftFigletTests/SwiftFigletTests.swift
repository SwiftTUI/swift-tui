import EmbeddedFonts
import SwiftFiglet
import Testing

private let repositoryRoot =
  "/" + #filePath.split(separator: "/").dropLast(3).joined(separator: "/")
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

@Test func listsEmbeddedFonts() {
  let fonts = EmbeddedFigletFont.allCases

  #expect(fonts.contains(.slant))
  #expect(fonts.contains(.standard))
  #expect(fonts.contains(.banner))
  #expect(fonts.contains(.mono9))
}

@Test func embeddedFontEnumMatchesTheGeneratedLibrary() {
  #expect(
    EmbeddedFigletFont.allCases.map(\.rawValue) == EmbeddedFigletFont.library.fontNames)
}
