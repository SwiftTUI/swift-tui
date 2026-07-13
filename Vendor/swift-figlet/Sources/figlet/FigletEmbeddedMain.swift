import SwiftTUIVendorFigletEmbeddedFonts

@main
struct FigletEmbeddedMain {
  static func main() {
    FigletCLI.main(fontLibraries: [EmbeddedFigletFont.library])
  }
}
