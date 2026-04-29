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
    case .pen: return "Space paints"
    case .eraser: return "Space erases"
    case .fill: return "Space fills"
    case .gradient:
      if pendingGradientAnchor != nil {
        return "Move; Space again"
      } else {
        return "Space sets anchor"
      }
    case .marquee:
      if pendingMarqueeAnchor != nil {
        return "Move; Space again"
      } else {
        return "Space sets anchor"
      }
    case .eyedropper: return "Space samples"
    }
  }
}
