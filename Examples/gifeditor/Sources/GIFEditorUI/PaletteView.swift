import GIFEditorCore
import TerminalUI

/// Two-row palette: meaningful colors first, then padding indicator.
/// Each entry is a 2×1 colored block that the user can pick via
/// `Ctrl+1..9` (primary) or `Alt+1..9` (secondary).
///
/// We only render the first 32 distinct slots — enough to cover the
/// default palette plus headroom; users editing a loaded GIF still
/// have the full 256 slots available via the eyedropper.
struct PaletteView: View {
  let palette: ColorPalette
  let primaryIndex: PaletteIndex
  let secondaryIndex: PaletteIndex

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Palette").foregroundStyle(.muted)
      HStack(spacing: 0) {
        ForEach(0..<16, id: \.self) { index in
          swatch(for: PaletteIndex(index))
        }
      }
      HStack(spacing: 0) {
        ForEach(16..<32, id: \.self) { index in
          swatch(for: PaletteIndex(index))
        }
      }
      Spacer(minLength: 1)
      legend
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

  private var legend: some View {
    VStack(alignment: .leading, spacing: 0) {
      let primary = palette[primaryIndex]
      let secondary = palette[secondaryIndex]
      HStack(spacing: 1) {
        Text("Primary").foregroundStyle(.muted)
        Rectangle()
          .fill(primary.toTerminalColor())
          .frame(width: 4, height: 1)
        Text("#\(hex(primary))").foregroundStyle(.separator)
      }
      HStack(spacing: 1) {
        Text("Second").foregroundStyle(.muted)
        Rectangle()
          .fill(secondary.toTerminalColor())
          .frame(width: 4, height: 1)
        Text("#\(hex(secondary))").foregroundStyle(.separator)
      }
    }
  }

  private func hex(_ c: EditorColor) -> String {
    String(format: "%02X%02X%02X", c.red, c.green, c.blue)
  }
}
