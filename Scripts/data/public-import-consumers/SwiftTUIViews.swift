import SwiftTUIViews

struct ConsumerView: View {
  var body: some View {
    Text("Views-only consumer")
      .foregroundStyle(Color.red)
      .frame(width: 24, height: 3)
  }
}

// Names owned by Primitives, Graph, and Core remain usable through Views.
func vocabulary(_ size: CellSize, metadata: SemanticMetadata, style: AnyShapeStyle) -> CellSize {
  size
}

@main
enum Consumer {
  @MainActor
  static func main() {
    _ = ConsumerView()
    _ = vocabulary
  }
}
