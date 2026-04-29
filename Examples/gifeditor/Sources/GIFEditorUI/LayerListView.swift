import GIFEditorCore
import TerminalUI

/// Vertical list of layers in the current frame, top-to-bottom matching
/// SwiftUI conventions. The selected layer renders highlighted; hidden
/// layers grey out.
struct LayerListView: View {
  let layers: [EditorLayer]
  let selectedIndex: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Layers").foregroundStyle(.muted)
      ForEach(Array(layers.enumerated().reversed()), id: \.element.id) {
        offset, layer in
        row(layer: layer, isSelected: offset == selectedIndex)
      }
    }
    .padding(1)
    .border(.separator, set: .single)
  }

  private func row(layer: EditorLayer, isSelected: Bool) -> some View {
    HStack(spacing: 1) {
      Text(layer.isVisible ? "●" : "○")
        .foregroundStyle(layer.isVisible ? .foreground : .muted)
      Text(layer.name)
        .foregroundStyle(isSelected ? .tint : (layer.isVisible ? .foreground : .muted))
    }
  }
}
