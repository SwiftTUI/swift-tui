import Testing

@testable import GIFEditorUI

@MainActor
@Suite("GIF editor keyboard help")
struct EditorHelpViewTests {
  @Test("Help catalog documents the reachable editor bindings")
  func helpCatalogDocumentsReachableBindings() {
    let rows = EditorShortcutHelp.sections.flatMap(\.rows)
    let shortcuts = Set(rows.map(\.shortcut))

    #expect(shortcuts.contains("?"))
    #expect(shortcuts.contains("1..9"))
    #expect(shortcuts.contains("Alt+1..9"))
    #expect(shortcuts.contains("Alt+S"))
    #expect(shortcuts.contains("Alt+-"))
    #expect(shortcuts.contains("Alt+="))
    #expect(!shortcuts.contains(where: { $0.contains("Ctrl+Shift") }))
    #expect(!shortcuts.contains(where: { $0.contains("Ctrl+1") }))
    #expect(!shortcuts.contains("Alt+["))
  }
}
