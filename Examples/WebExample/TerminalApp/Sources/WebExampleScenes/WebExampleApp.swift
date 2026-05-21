import GalleryDemoViews
import SwiftTUIRuntime

public struct WebExampleApp: App {
  public init() {}

  public var body: some Scene {
    WindowGroup("Game of Life") {
      LifeTab()
    }
    WindowGroup("Demo Details", id: WindowIdentifier("details")) {
      Panel(id: "details-panel") {
        GeometryReader { geometry in
          VStack(alignment: .leading, spacing: 1) {
            Text("Conway's Game of Life Web Demo")
            Divider()
            Text(
              """
              This is a standard SwiftTUI app with two Scenes: \"Game of Life\", \"Demo Details\".
              The app runs in any of SwiftTUI's Platform hosts including:
              - the standard terminal host
              - the SwiftUI host (for both iOS and macOS)
              - the Web host
              """)
            Text(
              """
              For this demo the app is compiled to wasm32-wasi to run in your browser via the Web host.
              """
            )
            Text(
              """
              The host handles displaying scenes.
              Here, it lets you pick the current scene and displays its output in this page's HTML <canvas>.
              """)
            Spacer()
          }
          .toolbarItem(
            ToolbarItemConfig(
              title: "terminal size: \(geometry.size.width)x\(geometry.size.height)", action: {}))
        }
      }.toolbar(style: .defaultBottom)
    }

  }
}
