import ArgumentParser
import SwiftTUICLI

struct IndexCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "index",
    abstract: "List available subcommands."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    GitVizRunOnce.print(IndexView(), opts: opts)
  }
}
