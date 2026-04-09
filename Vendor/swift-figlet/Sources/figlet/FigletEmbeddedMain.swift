import EmbeddedFonts

@main
struct FigletEmbeddedMain {
  static func main() {
    FigletCLI.main(fontLibraries: [EmbeddedFigletFont.library])
  }
}
