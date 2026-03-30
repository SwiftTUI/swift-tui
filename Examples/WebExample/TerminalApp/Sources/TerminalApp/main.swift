import TerminalUI
import TerminalUIScenes

struct WebExampleApp: App {
  var body: some Scene {
    WindowGroup("Overview", id: WindowIdentifier("main")) {
      VStack(alignment: .leading, spacing: 1) {
        Text("TerminalUI in the browser")
        Divider()
        Text("This scene is rendered by a Swift WASI executable.")
        Text("The surrounding page is a Bun app that mounts WebTUIGUI.")
        Text("Build inputs come from Examples/WebExample/TerminalApp.")
      }
      .padding(1)
    }

    WindowGroup("Details", id: WindowIdentifier("details")) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Details")
        Divider()
        Text("Scene switching is owned by the web host.")
        Text("Terminal output is still rendered through Ghostty-Web.")
        Text("Resize updates flow through the synthetic SIGWINCH control message path.")
      }
      .padding(1)
    }
  }
}

let app = await MainActor.run { WebExampleApp() }
try await MultiSceneLauncher.run(app)
