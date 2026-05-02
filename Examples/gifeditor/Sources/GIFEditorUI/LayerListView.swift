import GIFEditorCore
import SwiftTUI

/// Bottom sub-panel of the right column — Photoshop-style layers
/// list. Top of the list is the visually-frontmost layer (matches the
/// painter's-stack order users learn from Photoshop). Each row has a
/// clickable visibility toggle, a name, and a delete button; the row
/// body itself is clickable to select that layer. A `＋` footer adds a
/// new layer above the current.
///
/// All shortcuts continue to work via the keyboard:
/// `Alt+H` toggles current visibility, `Alt+J/K` change selection,
/// `Alt+X` deletes, `Alt+N` adds.
struct LayerListView: View {
  let layers: [EditorLayer]
  let selectedIndex: Int
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Layers").foregroundStyle(.muted)
      ForEach(Array(layers.enumerated().reversed()), id: \.element.id) {
        offset, layer in
        row(layer: layer, index: offset, isSelected: offset == selectedIndex)
      }
      Divider()
      newLayerButton
    }
    .padding(1)
    .border(.separator, set: .single)
  }

  private func row(layer: EditorLayer, index: Int, isSelected: Bool) -> some View {
    HStack(spacing: 1) {
      visibilityButton(for: layer, index: index)
      Button {
        model.selectLayer(at: index)
        refresh()
      } label: {
        Text(layer.name)
          .foregroundStyle(
            isSelected
              ? AnyShapeStyle(.tint)
              : AnyShapeStyle(layer.isVisible ? .foreground : .muted)
          )
      }
      .buttonStyle(.plain)
      Spacer(minLength: 1)
      deleteButton(index: index)
    }
  }

  private func visibilityButton(for layer: EditorLayer, index: Int) -> some View {
    Button {
      model.toggleLayerVisibility(at: index)
      refresh()
    } label: {
      Text(layer.isVisible ? "●" : "○")
        .foregroundStyle(layer.isVisible ? .foreground : .muted)
    }
    .buttonStyle(.plain)
  }

  private func deleteButton(index: Int) -> some View {
    Button {
      model.deleteLayer(at: index)
      refresh()
    } label: {
      Text("✕").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  private var newLayerButton: some View {
    Button {
      model.addLayer()
      refresh()
    } label: {
      HStack(spacing: 1) {
        Text("＋").foregroundStyle(.tint)
        Text("New layer").foregroundStyle(.muted)
      }
    }
    .buttonStyle(.plain)
  }
}
