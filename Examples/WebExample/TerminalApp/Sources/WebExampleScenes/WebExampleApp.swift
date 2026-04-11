import TerminalUI

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      DeployDashboardView()
    }
    WindowGroup("Details", id: WindowIdentifier("details")) {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 1) {
          Text("Details")
          Divider()
          Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
          Text("This web example keeps a curated scene set for wasm reliability.")
          Text("The full component gallery still lives in the native examples.")
          Text("Use the lane buttons, traffic slider, and toggles to reshape the main scene.")
          Text("Scene switching is owned by the web host.")
          Text("Resize updates flow through the synthetic SIGWINCH control message path.")
        }
        .padding(1)
      }
    }
  }
}
