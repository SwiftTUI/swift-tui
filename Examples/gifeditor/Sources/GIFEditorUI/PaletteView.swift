import GIFEditorCore
import TerminalUI

/// Middle sub-panel of the right column — a 4×8 grid of the first 32
/// palette slots. The active primary slot wears a `P` overlay; the
/// secondary slot wears `S`. The grid layout mirrors Photoshop's
/// "Swatches" panel.
///
/// Users editing a loaded GIF still have access to the full 256 slots
/// via the eyedropper. Phase 5 of the redesign adds a `▼ More…`
/// disclosure that opens an overflow grid when the document uses
/// indices ≥ 32.
struct PaletteView: View {
  let palette: ColorPalette
  let primaryIndex: PaletteIndex
  let secondaryIndex: PaletteIndex

  private static let columns = 8
  private static let rows = 4

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Palette").foregroundStyle(.muted)
      ForEach(0..<Self.rows, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<Self.columns, id: \.self) { column in
            let slot = row * Self.columns + column
            swatch(for: PaletteIndex(slot))
          }
        }
      }
    }
    .padding(1)
    .border(.separator, set: .single)
  }

  private func swatch(for index: PaletteIndex) -> some View {
    let color = palette[index]
    let isPrimary = index == primaryIndex
    let isSecondary = index == secondaryIndex
    return ZStack(alignment: .center) {
      Rectangle()
        .fill(color.toTerminalColor())
        .frame(width: 2, height: 1)
      if isPrimary {
        Text("P").foregroundStyle(.foreground)
      } else if isSecondary {
        Text("S").foregroundStyle(.foreground)
      }
    }
  }
}
