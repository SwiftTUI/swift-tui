import GalleryDemoViews
import TerminalUI

public struct WebExampleApp: App {
  public init() {}

  private let model = GalleryDemoModel()

  public var body: some Scene {
    #if canImport(WASILibc)
      // The full native gallery still exhausts the current WASI resolve budget.
      // Keep the browser demo on a smaller, wasm-safe scene until the deeper
      // allocator pressure in TabView/toolbar/presentation hosting is resolved.
      WindowGroup("WebAssembly Demo") {
        WasmDemoSceneView()
      }
    #else
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
    #endif
  }
}

private struct WasmDemoSceneView: View {
  @State private var activationCount = 0

  var body: some View {
    GeometryReader { geometry in
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 1) {
          Text("TerminalUI WebAssembly Demo")
            .bold()
          Text(
            "This curated scene keeps the browser demo bootable while the full native gallery still exceeds the current WASI resolve-time memory budget."
          )
          .foregroundStyle(.separator)

          Divider()

          detailRow(
            label: "Terminal size",
            value: "\(geometry.size.width)x\(geometry.size.height)"
          )
          detailRow(
            label: "Pipeline",
            value: "resolve -> measure -> place -> semantics -> draw -> raster -> commit"
          )
          detailRow(
            label: "Scene model",
            value: "Single-scene preview for wasm builds"
          )

          Divider()

          Text("Interaction")
            .bold()
          Text(
            "Plain buttons remain stable on wasm, so this stays live without the heavier chrome paths."
          )
          .foregroundStyle(.separator)
          Button(activationCount == 0 ? "Prime render" : "Advance counter") {
            activationCount += 1
          }
          .buttonStyle(.plain)
          Text("Counter: \(activationCount)")

          Divider()

          Text("Links")
            .bold()
          Link("Repository", destination: "https://github.com/adam-zethraeus/swift-terminal-ui")
          Link(
            "Architecture",
            destination:
              "https://github.com/adam-zethraeus/swift-terminal-ui/blob/main/docs/ARCHITECTURE.md")
          Link(
            "Runtime",
            destination:
              "https://github.com/adam-zethraeus/swift-terminal-ui/blob/main/docs/RUNTIME.md")
        }
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func detailRow(
    label: String,
    value: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label)
        .bold()
      Text(value)
        .foregroundStyle(.separator)
    }
  }
}
