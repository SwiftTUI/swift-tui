import GIFEditorCore
import SwiftTUI

/// 4-cell-wide tool dock pinned to the left edge. Each icon is a
/// `.plain`-styled `Button` that selects the tool when activated; the
/// active tool's icon stays tinted. Below the tool list a divider,
/// then the primary/secondary color cells and a `⇄` swap button that
/// mirrors the keyboard `x` shortcut.
///
/// `.plain` style was chosen so the button chrome stays minimal — no
/// horizontal padding or border. The dock is 4 cells wide to fit a
/// plain button's intrinsic width of 2 cells (a 1-cell focus-rail
/// gutter that the framework reserves on every plain button so focus
/// presentation never overdraws the label, plus the icon glyph itself)
/// with 1 cell of slack on either side so the icon sits visually
/// centred whether or not it is the active tool.
struct ToolboxView: View {
  let tool: EditorTool
  let primaryColor: EditorColor
  let secondaryColor: EditorColor
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .center, spacing: 0) {
      ForEach(EditorTool.allCases, id: \.self) { entry in
        toolButton(entry)
      }
      Divider()
      Rectangle()
        .fill(primaryColor.toTerminalColor())
        .frame(width: 1, height: 1)
      Rectangle()
        .fill(secondaryColor.toTerminalColor())
        .frame(width: 1, height: 1)
      swapButton
      Spacer(minLength: 0)
    }
    .padding(0)
    .frame(width: 4, alignment: .center)
    .border(.separator, set: .single)
  }

  private func toolButton(_ entry: EditorTool) -> some View {
    Button {
      model.selectTool(entry)
      refresh()
    } label: {
      Text(entry.iconGlyph)
        .foregroundStyle(entry == tool ? .tint : .muted)
    }
    .buttonStyle(.plain)
  }

  private var swapButton: some View {
    Button {
      model.swapPrimaryAndSecondary()
      refresh()
    } label: {
      Text("⇄").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }
}
