import SwiftTUI

@main
struct ArgParseDemoApp: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "argparse-demo",
    abstract: "Demonstrates consumer flags + SwiftTUI framework flags coexisting.",
    subcommands: [CompletionsCommand.self]
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Option(name: .shortAndLong, help: "How many widgets to show.")
  var widgets: Int = 5

  @Flag(name: .customLong("show-ids"), help: "Show widget IDs alongside their labels.")
  var showIds: Bool = false

  var body: some Scene {
    WindowGroup {
      Text("widgets: \(widgets), showIds: \(showIds)")
    }
  }
}
