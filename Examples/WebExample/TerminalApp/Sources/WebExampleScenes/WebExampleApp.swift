import TerminalUI

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Overview", id: WindowIdentifier("main")) {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 1) {
          Text("TerminalUI in the browser")
          Divider()
          Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
          Text("Resize this pane and the running Swift app should redraw in place.")
          Text("This scene is rendered by a Swift WASI executable.")
          Text("The surrounding page is a Bun app that mounts WebTUIGUI.")
          Text("Build inputs come from Examples/WebExample/TerminalApp.")
        }
        .padding(1)
      }
    }

    WindowGroup("Details", id: WindowIdentifier("details")) {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 1) {
          Text("Details")
          Divider()
          Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
          Text("Scene switching is owned by the web host.")
          Text("Terminal output is still rendered through Ghostty-Web.")
          Text("Resize updates flow through the synthetic SIGWINCH control message path.")
        }
        .padding(1)
      }
    }
  }
}
