import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct KeyboardShortcutFormattingTests {
  @Test("formats typed shortcut keys canonically")
  func formatsTypedShortcutKeys() {
    #expect(formattedKeyboardShortcutKey(.character("q")) == "q")
    #expect(formattedKeyboardShortcutKey(.character("S"), modifiers: .ctrl) == "Ctrl+S")
    #expect(formattedKeyboardShortcutKey(.tab, modifiers: .shift) == "Shift+Tab")
    #expect(formattedKeyboardShortcutKey(.space, modifiers: .alt) == "Alt+Space")
    #expect(formattedKeyboardShortcutKey(.return) == "Return")
    #expect(formattedKeyboardShortcutKey(.escape) == "Escape")
    #expect(formattedKeyboardShortcutKey(.arrowUp, modifiers: [.ctrl, .shift]) == "Ctrl+Shift+Up")
    #expect(formattedKeyboardShortcutKey(.home) == "Home")
    #expect(formattedKeyboardShortcutKey(.end) == "End")
  }

  @Test("help surface renders typed shortcuts")
  func helpSurfaceRendersTypedShortcuts() {
    let surface = renderedText(
      KeyboardShortcutHelpView(
        shortcuts: [
          KeyboardShortcut(.character("S"), modifiers: .ctrl, label: "Save", group: "File"),
          KeyboardShortcut(.return, label: "Open", group: "File"),
          KeyboardShortcut(.tab, modifiers: .shift, label: "Back", group: "Navigate"),
        ]
      )
    )

    #expect(surface.contains("File"))
    #expect(surface.contains("[Ctrl+S]"))
    #expect(surface.contains("Save"))
    #expect(surface.contains("[Return]"))
    #expect(surface.contains("Open"))
    #expect(surface.contains("Navigate"))
    #expect(surface.contains("[Shift+Tab]"))
    #expect(surface.contains("Back"))
  }
}

@MainActor
private func renderedText<V: View>(
  _ view: V
) -> String {
  let artifacts = DefaultRenderer().render(
    view,
    context: .init(identity: .init(components: ["KeyboardShortcutTests"]))
  )
  return artifacts.rasterSurface.lines.joined(separator: "\n")
}
