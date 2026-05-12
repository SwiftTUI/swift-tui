import Foundation
import GIFEditor
import SwiftTUIWebHostCLI

@main
struct GIFEditorApp: App, SwiftTUICommand {

  nonisolated static let configuration = CommandConfiguration(
    commandName: "gifeditor",
    abstract: "Edit a GIF in the terminal.",
    subcommands: [CompletionsCommand.self]
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(help: "Path to a GIF file. Omit to start with a blank 32×32 document.")
  var path: String?

  var body: some Scene {
    WindowGroup {
      GIFEditor(path: path)
    }
    .exitOnKeys([
      KeyPress(.character("q"), modifiers: .ctrl)
    ])
  }

  static func run() async throws {
    try await WebHostCLIRunner.run(GIFEditorApp.self)
  }
}
