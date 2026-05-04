import GalleryDemoViews
import SwiftTUI

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Conway's Life") {
      LifeTab()
    }
    WindowGroup("Details", id: WindowIdentifier("details")) {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 1) {
          Text("Details")
          Divider()
          Text("Reported terminal size: \(geometry.size.width)x\(geometry.size.height)")
          Text("Conway's Game of Life — this whole grid is one SwiftTUI View,")
          Text("compiled to wasm32-wasi and rendered into terminal cells.")
          Text("Scene switching is owned by the web host.")
          Text("Resize updates flow through the synthetic SIGWINCH control message path.")
        }
        .padding(1)
        .frame(maxHeight: .infinity)
      }
    }
  }
}
