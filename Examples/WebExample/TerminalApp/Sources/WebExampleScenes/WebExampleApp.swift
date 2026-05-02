import GalleryDemoViews
import TerminalUI

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Component Gallery") {
      LimitedGalleryView()
    }
    WindowGroup("Details", id: WindowIdentifier("details")) {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 1) {
          Text("Details")
          Divider()
          Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
          Text("The same component gallery used by the SwiftUI demo is running here.")
          Text("Scene switching is owned by the web host.")
          Text("Resize updates flow through the synthetic SIGWINCH control message path.")
        }
        .padding(1)
        .frame(maxHeight: .infinity)
      }
    }
  }
}
