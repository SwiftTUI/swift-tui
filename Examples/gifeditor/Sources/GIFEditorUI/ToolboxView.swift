import GIFEditorCore
import TerminalUI

/// 3-cell-wide tool dock pinned to the left edge. Renders one icon per
/// tool, vertically stacked, with the active tool highlighted. Below
/// the tool list a divider, then a stub area for primary/secondary
/// color chips and a swap glyph — the chips become real clickable
/// `Button`s in Phase 3 of the redesign; for now they act as
/// keyboard-driven indicators only.
///
/// This view replaces the previous 18-cell labeled toolbox. Pixel
/// editors traditionally pin tools to a narrow icon column and rely on
/// the active-tool highlight + the contextual options bar for
/// affordance — see `REDESIGN.md` § "Left tool dock".
struct ToolboxView: View {
  let tool: EditorTool
  let primaryColor: EditorColor
  let secondaryColor: EditorColor

  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      ForEach(EditorTool.allCases, id: \.self) { entry in
        Text(entry.iconGlyph)
          .foregroundStyle(entry == tool ? .tint : .muted)
      }
      Divider()
      Rectangle()
        .fill(primaryColor.toTerminalColor())
        .frame(width: 1, height: 1)
      Rectangle()
        .fill(secondaryColor.toTerminalColor())
        .frame(width: 1, height: 1)
      Text("⇄").foregroundStyle(.muted)
      Spacer(minLength: 0)
    }
    .padding(0)
    .frame(width: 3, alignment: .center)
    .border(.separator, set: .single)
  }
}
