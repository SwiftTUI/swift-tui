import SwiftTUIArguments
import SwiftTUICLI

struct CLIAsyncProbeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-async",
    abstract: "Prove the SwiftTUICLI async dispatch tail ran."
  )

  mutating func run() async throws {
    print("CLIASYNCPROBEOK")
  }
}

@main
struct EntryPointFixtureCLIAsyncVerbDispatch: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "cli-async-verb-dispatch",
    abstract: "SwiftTUICLI async verb-dispatch launch fixture.",
    subcommands: [CLIAsyncProbeCommand.self]
  )

  @OptionGroup var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}
