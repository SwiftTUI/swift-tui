import GIFEditorCore
import SwiftTUI

/// Modal sheet that lets the user pick a square canvas size from the
/// standard progression (16/24/32/48/64). Replaces the silent cycle
/// behavior of `Ctrl+R` with a deliberate, scannable picker.
///
/// The keyboard binding `Ctrl+R` and the File → Resize Canvas menu
/// item both open this sheet so users can either cycle from muscle
/// memory or jump directly to a specific size.
struct ResizeCanvasSheetView: View {
  let currentSize: GIFEditorCore.PixelSize
  let onSelect: @MainActor @Sendable (GIFEditorCore.PixelSize) -> Void
  let onCancel: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Pick a square canvas size:").foregroundStyle(.muted)
      ForEach(EditorViewModel.canvasSizeProgression, id: \.self) { dimension in
        sizeRow(for: dimension)
      }
      Divider()
      HStack(spacing: 1) {
        Spacer(minLength: 1)
        Button("Cancel", action: onCancel)
          .systemHint("Esc")
      }
    }
    .padding(1)
  }

  private func sizeRow(for dimension: Int) -> some View {
    let target = GIFEditorCore.PixelSize(width: dimension, height: dimension)
    let isCurrent = target == currentSize
    return Button {
      onSelect(target)
    } label: {
      HStack(spacing: 1) {
        Text(isCurrent ? "✓" : " ")
          .foregroundStyle(isCurrent ? .tint : .muted)
        Text("\(dimension) × \(dimension)")
          .foregroundStyle(isCurrent ? .tint : .foreground)
        Spacer(minLength: 1)
        if isCurrent {
          Text("(current)").foregroundStyle(.muted)
        }
      }
    }
    .buttonStyle(.plain)
  }
}
