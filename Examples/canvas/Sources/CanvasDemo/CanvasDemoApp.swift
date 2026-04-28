import CanvasDemoViews
import TerminalUI
import TerminalUICLI

@main
struct CanvasDemoApp: App {
  var body: some Scene {
    WindowGroup {
      CanvasDemoView()
    }
  }
}
