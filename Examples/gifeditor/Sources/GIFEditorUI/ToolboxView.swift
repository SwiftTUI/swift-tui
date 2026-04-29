import GIFEditorCore
import TerminalUI

/// Renders the tool list as a vertical column of glyph + label rows.
/// The active tool is highlighted; non-active rows are muted.
struct ToolboxView: View {
  let tool: EditorTool
  let pendingMarqueeAnchor: GIFEditorCore.PixelPoint?
  let pendingGradientAnchor: GIFEditorCore.PixelPoint?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Tools").foregroundStyle(.muted)
      ForEach(EditorTool.allCases, id: \.self) { entry in
        row(for: entry)
      }
      Spacer(minLength: 1)
      Text(toolHint).foregroundStyle(.separator)
    }
    .padding(1)
    .frame(width: 18, alignment: .leading)
    .border(.separator, set: .single)
  }

  private func row(for entry: EditorTool) -> some View {
    HStack(spacing: 1) {
      Text(entry.glyph)
      Text(entry.label)
    }
    .foregroundStyle(entry == tool ? .tint : .muted)
  }

  private var toolHint: String {
    switch tool {
    case .pen: return "Shift+Space paints"
    case .eraser: return "Shift+Space erases"
    case .fill: return "Shift+Space fills"
    case .gradient:
      if pendingGradientAnchor != nil {
        return "Move; Shift+Space again"
      } else {
        return "Shift+Space sets anchor"
      }
    case .marquee:
      if pendingMarqueeAnchor != nil {
        return "Move; Shift+Space again"
      } else {
        return "Shift+Space sets anchor"
      }
    case .eyedropper: return "Shift+Space samples"
    }
  }
}
