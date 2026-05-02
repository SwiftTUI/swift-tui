import SwiftTUI

struct EditorShortcutRow: Identifiable, Equatable, Sendable {
  let shortcut: String
  let action: String

  var id: String {
    "\(shortcut)|\(action)"
  }
}

struct EditorShortcutSection: Identifiable, Equatable, Sendable {
  let title: String
  let rows: [EditorShortcutRow]

  var id: String {
    title
  }
}

enum EditorShortcutHelp {
  static let sections: [EditorShortcutSection] = [
    EditorShortcutSection(
      title: "Tools",
      rows: [
        EditorShortcutRow(shortcut: "p", action: "Pen"),
        EditorShortcutRow(shortcut: "e", action: "Eraser"),
        EditorShortcutRow(shortcut: "b", action: "Bucket fill"),
        EditorShortcutRow(shortcut: "g", action: "Gradient"),
        EditorShortcutRow(shortcut: "m", action: "Marquee selection"),
        EditorShortcutRow(shortcut: "i", action: "Eyedropper"),
        EditorShortcutRow(shortcut: "x", action: "Swap primary and secondary colors"),
        EditorShortcutRow(shortcut: "Space / Enter", action: "Apply or confirm the active tool"),
        EditorShortcutRow(shortcut: "Escape", action: "Clear selection"),
      ]
    ),
    EditorShortcutSection(
      title: "Cursor",
      rows: [
        EditorShortcutRow(shortcut: "Arrows", action: "Move cursor by 1 pixel"),
        EditorShortcutRow(shortcut: "h / j / k / l", action: "Vi-style 1-pixel movement"),
        EditorShortcutRow(shortcut: "Ctrl+Arrows", action: "Move cursor by 8 pixels"),
      ]
    ),
    EditorShortcutSection(
      title: "Frames",
      rows: [
        EditorShortcutRow(shortcut: "Alt+,", action: "Previous frame"),
        EditorShortcutRow(shortcut: "Alt+.", action: "Next frame"),
        EditorShortcutRow(shortcut: "Ctrl+N", action: "New blank frame after current"),
        EditorShortcutRow(shortcut: "Ctrl+D", action: "Duplicate current frame"),
        EditorShortcutRow(shortcut: "Alt+D", action: "Delete current frame"),
        EditorShortcutRow(shortcut: "Alt+-", action: "Decrease current frame delay"),
        EditorShortcutRow(shortcut: "Alt+=", action: "Increase current frame delay"),
        EditorShortcutRow(shortcut: "Alt+0", action: "Set all frame delays to current"),
      ]
    ),
    EditorShortcutSection(
      title: "Layers",
      rows: [
        EditorShortcutRow(shortcut: "Alt+N", action: "New empty layer above current"),
        EditorShortcutRow(shortcut: "Alt+J", action: "Select layer below"),
        EditorShortcutRow(shortcut: "Alt+K", action: "Select layer above"),
        EditorShortcutRow(shortcut: "Alt+H", action: "Toggle current layer visibility"),
        EditorShortcutRow(shortcut: "Alt+X", action: "Delete current layer"),
      ]
    ),
    EditorShortcutSection(
      title: "Clipboard",
      rows: [
        EditorShortcutRow(shortcut: "Ctrl+C", action: "Copy selection or current layer"),
        EditorShortcutRow(shortcut: "Ctrl+V", action: "Paste at cursor"),
      ]
    ),
    EditorShortcutSection(
      title: "History",
      rows: [
        EditorShortcutRow(shortcut: "Ctrl+Z", action: "Undo last document edit"),
        EditorShortcutRow(shortcut: "Ctrl+Y", action: "Redo last undone edit"),
      ]
    ),
    EditorShortcutSection(
      title: "Palette",
      rows: [
        EditorShortcutRow(shortcut: "1..9", action: "Pick primary color slot"),
        EditorShortcutRow(shortcut: "Alt+1..9", action: "Pick secondary color slot"),
      ]
    ),
    EditorShortcutSection(
      title: "File and help",
      rows: [
        EditorShortcutRow(shortcut: "Ctrl+S", action: "Save"),
        EditorShortcutRow(shortcut: "Alt+S", action: "Save As to ./untitled.gif"),
        EditorShortcutRow(shortcut: "Ctrl+R", action: "Cycle canvas size"),
        EditorShortcutRow(shortcut: "Ctrl+Q", action: "Quit"),
        EditorShortcutRow(shortcut: "?", action: "Open this help page"),
      ]
    ),
  ]
}

struct EditorHelpView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Keyboard shortcuts")
        .foregroundStyle(.tint)
      Text("Escape closes this page.")
        .foregroundStyle(.muted)

      ForEach(EditorShortcutHelp.sections) { section in
        shortcutSection(section)
      }
    }
  }

  private func shortcutSection(_ section: EditorShortcutSection) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(section.title)
        .foregroundStyle(.foreground)
      ForEach(section.rows) { row in
        HStack(spacing: 1) {
          Text(row.shortcut)
            .foregroundStyle(.tint)
            .frame(width: 16, alignment: .leading)
          Text(row.action)
            .foregroundStyle(.muted)
        }
      }
    }
  }
}
