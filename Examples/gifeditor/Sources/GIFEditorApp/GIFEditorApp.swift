import Foundation
import GIFEditor
import TerminalUI
import TerminalUICLI

@main
struct GIFEditorApp: App {
  var body: some Scene {
    WindowGroup {
      GIFEditor.makeRootView(arguments: CommandLine.arguments)
    }
    .exitOnKeys([
      KeyPress(.character("q"), modifiers: .ctrl)
    ])
  }
}
