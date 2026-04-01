import GalleryDemoViews
import TerminalUI

public struct ExampleApp: App {
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
        }
        .padding(1)
      }
    }
  }
}
