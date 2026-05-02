import GIFEditorCore
import SwiftTUI

/// Middle sub-panel of the right column — a 4×8 grid of the first 32
/// palette slots. Every swatch is a clickable `Button` that sets the
/// primary color slot. The active primary slot wears a `P` overlay,
/// the secondary slot wears `S`, and slots 1..9 carry a trailing digit
/// label that advertises the keyboard shortcut. `Alt+1..9` continues
/// to set the secondary slot via keyboard (mouse parity for that
/// secondary-pick path lands in a future pass once the framework's
/// pointer model exposes shift-click cleanly).
///
/// Users editing a loaded GIF still have access to the full 256 slots
/// via the eyedropper. Phase 5 of the redesign adds a `▼ More…`
/// disclosure that opens an overflow grid when the document uses
/// indices ≥ 32.
struct PaletteView: View {
  let palette: ColorPalette
  let primaryIndex: PaletteIndex
  let secondaryIndex: PaletteIndex
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

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
    .frame(maxWidth: .infinity, alignment: .leading)
    .border(.separator, set: .single)
  }

  private func swatch(for index: PaletteIndex) -> some View {
    let color = palette[index]
    let isPrimary = index == primaryIndex
    let isSecondary = index == secondaryIndex
    // Leading column: P/S role marker (highest priority since the
    // active slot is the most important to telegraph).
    let leading: String
    if isPrimary {
      leading = "P"
    } else if isSecondary {
      leading = "S"
    } else {
      leading = " "
    }
    // Trailing column: 1..9 keyboard-shortcut hint for the first nine
    // slots so the keyboard mapping reads at a glance even when no
    // keyboard help is open.
    let slotNumber = Int(index)
    let trailing: String
    if slotNumber >= 1, slotNumber <= 9 {
      trailing = String(slotNumber)
    } else {
      trailing = " "
    }
    return Button {
      model.setPrimaryColor(index)
      refresh()
    } label: {
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(color.toTerminalColor())
          .frame(width: 2, height: 1)
        HStack(spacing: 0) {
          Text(leading).foregroundStyle(.foreground)
          Text(trailing).foregroundStyle(.muted)
        }
      }
    }
    .buttonStyle(.plain)
  }
}
