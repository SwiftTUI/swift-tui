import SwiftTUIArguments
import SwiftTUIWebHostCLI

struct WebHostCLIAsyncProbeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-async",
    abstract: "Prove the SwiftTUIWebHostCLI async dispatch tail ran."
  )

  mutating func run() async throws {
    print("WEBHOSTCLIASYNCPROBEOK")
  }
}

@main
struct EntryPointFixtureWebHostCLIAsyncVerbDispatch: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "webhost-cli-async-verb-dispatch",
    abstract: "SwiftTUIWebHostCLI async verb-dispatch launch fixture.",
    subcommands: [WebHostCLIAsyncProbeCommand.self]
  )

  @OptionGroup var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}
