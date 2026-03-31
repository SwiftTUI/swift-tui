import TerminalUI

public struct WebExampleApp: App {
  public init() {}

  private let model = GalleryDemoModel()

  public var body: some Scene {
    WindowGroup("Component Gallery") {
      GalleryDemoSceneView(model: model)
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
