import GifCat
import SwiftTUI
import SwiftTUICLI

@main
struct GifCatApp: App {
  var body: some Scene {
    WindowGroup {
      GifCatView(items: GifCatInput.items(from: CommandLine.arguments))
    }
  }
}
