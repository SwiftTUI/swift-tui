import figlet_cli
import swift_figlet_embedded_fonts

@main
struct FigletEmbeddedMain {
    static func main() {
        FigletCLI.main(fontLibraries: [SwiftFigletEmbeddedFonts.library])
    }
}
