import Testing
import Foundation
import swift_figlet

@Test func rendersBundledStandardFont() throws {
    let figlet = try Figlet(fontNamed: "standard")
    let output = try figlet.render("Hi").description

    #expect(output == " _   _ _ \n| | | (_)\n| |_| | |\n|  _  | |\n|_| |_|_|\n         \n")
}

@Test func rendersBundledSlantFont() throws {
    let figlet = try Figlet(fontNamed: "slant")
    let output = try figlet.render("Swift").description

    #expect(output == "   _____         _ ______ \n  / ___/      __(_) __/ /_\n  \\__ \\ | /| / / / /_/ __/\n ___/ / |/ |/ / / __/ /_  \n/____/|__/|__/_/_/  \\__/  \n                          \n")
}

@Test func wrapsAtWordBoundaries() throws {
    let figlet = try Figlet(
        fontNamed: "standard",
        configuration: FigletConfiguration(width: 20)
    )

    let output = try figlet.render("hello world").description

    #expect(output == " _          _ _ \n| |__   ___| | |\n| '_ \\ / _ \\ | |\n| | | |  __/ | |\n|_| |_|\\___|_|_|\n                \n       \n  ___  \n / _ \\ \n| (_) |\n \\___/ \n       \n               \n__      _____  \n\\ \\ /\\ / / _ \\ \n \\ V  V / (_) |\n  \\_/\\_/ \\___/ \n               \n      _     _ \n _ __| | __| |\n| '__| |/ _` |\n| |  | | (_| |\n|_|  |_|\\__,_|\n              \n")
}

@Test func loadsExternalFontFiles() throws {
    let font = try FigletFont(fileURL: URL(fileURLWithPath: "/Users/adamz/Developer/repos/swift-figlet/tmp/pyfiglet/test-fonts/TEST_ONLY.flf"))
    let figlet = Figlet(font: font)
    let output = try figlet.render("0").strippingSurroundingNewlines()

    #expect(output == """
    0000000000  
                
    000    000  
                
    000    000  
                
    000    000  
                
    0000000000
    """)
}

@Test func listsBundledFonts() {
    let fonts = Figlet.availableFonts()
    #expect(fonts.contains("slant"))
    #expect(fonts.contains("standard"))
    #expect(fonts.contains("banner"))
    #expect(fonts.contains("mono9"))
}
