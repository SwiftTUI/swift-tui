import GIFEditorCore
import SwiftTUI

/// Top sub-panel of the right column — Photoshop-style "Color"
/// inspector. Shows the active primary and secondary colors as
/// labeled swatches with their hex codes plus a `⇄` swap glyph.
///
/// In Phase 1 the chips are decorative readouts; Phase 3 swaps them
/// for clickable `Button`s that open a 4×8 palette picker, and the
/// `⇄` glyph becomes a button mirroring the keyboard `x` shortcut.
struct ColorPanelView: View {
  let primaryColor: EditorColor
  let secondaryColor: EditorColor

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Color").foregroundStyle(.muted)
      colorRow(label: "P", color: primaryColor)
      colorRow(label: "S", color: secondaryColor)
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        Text("⇄").foregroundStyle(.muted)
        Spacer(minLength: 0)
      }
    }
    .padding(1)
    .border(.separator, set: .single)
  }

  private func colorRow(label: String, color: EditorColor) -> some View {
    HStack(spacing: 1) {
      Text(label).foregroundStyle(.muted)
      Rectangle()
        .fill(color.toTerminalColor())
        .frame(width: 4, height: 1)
      Text("#\(hex(color))").foregroundStyle(.separator)
    }
  }

  private func hex(_ c: EditorColor) -> String {
    String(format: "%02X%02X%02X", c.red, c.green, c.blue)
  }
}
