import GalleryDemoViews
import TerminalUI

public struct ExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Component Gallery") {
      GalleryView()
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
