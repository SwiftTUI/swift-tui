import Foundation
import GalleryDemoViews
import TerminalUI
import TerminalUICLI

@main
struct GalleryDemoApp: App {

  var body: some Scene {
    WindowGroup {
      GalleryView()
        .help()
        .helpSheet()
    }
    .commands {
      CommandItem(
        id: "quit",
        title: "Quit",
        key: .ctrl("c"),
        group: "Session"
      ) {
        exit(0)
      }
    }
  }
}
