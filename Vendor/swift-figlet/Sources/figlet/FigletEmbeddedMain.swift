import EmbeddedFonts

@main
struct FigletEmbeddedMain {
    static func main() {
        FigletCLI.main(fontLibraries: [FigletFont.library])
    }
}
