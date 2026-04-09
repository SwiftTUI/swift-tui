import GalleryDemoViews
import TerminalUI
import TerminalUICLI

@main
struct GalleryDemoApp: App {

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
