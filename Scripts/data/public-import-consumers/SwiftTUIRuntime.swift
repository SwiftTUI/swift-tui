import SwiftTUIRuntime

// Runtime owns scenes and rendering; the view and vocabulary types arrive via
// its re-exports. No umbrella, CLI, Core, Graph, or Primitives import is needed.
@MainActor
func scene() -> some Scene {
  WindowGroup("Runtime-only consumer") {
    Text("Runtime-only consumer").foregroundStyle(Color.blue)
  }
}

func vocabulary(_ size: CellSize, metadata: SemanticMetadata, style: AnyShapeStyle) -> CellSize {
  size
}

@main
enum Consumer {
  @MainActor
  static func main() {
    _ = scene()
    _ = DefaultRenderer()
    _ = vocabulary
  }
}
