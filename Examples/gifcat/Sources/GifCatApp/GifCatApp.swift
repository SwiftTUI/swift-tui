import GifCat
import TerminalUI
import TerminalUICLI

@main
struct GifCatApp: App {
  var body: some Scene {
    WindowGroup {
      GifCatView(items: GifCatInput.items(from: CommandLine.arguments))
    }
  }
}
