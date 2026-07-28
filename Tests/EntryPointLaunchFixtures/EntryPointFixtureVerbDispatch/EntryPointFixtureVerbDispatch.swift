import SwiftTUI

// Regression fixture for `EntryPointLaunchTests`: verb dispatch from a root
// command that also declares a positional argument.
//
// The interesting behavior lives entirely in `App.main()` — which command gets
// run, and which command's usage a failure is attributed to — so it is only
// observable by running a real binary. This fixture declares a stored
// `swiftTUIOptions`, so it takes the `parseSwiftTUIRootCommand` path.

/// A headless verb, shaped like the ones a real consumer registers.
struct ProbeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe",
    abstract: "Print a value without starting the runtime."
  )

  @Argument var value: String
  /// Selects a `ValidationError` from `run()`. That error carries no command
  /// stack of its own, so it is the case that proves the launch layer
  /// attributes a dispatched failure to the verb rather than to the root.
  @Flag(name: .long) var failValidation = false

  func run() throws {
    if failValidation {
      throw ValidationError("probe rejected the input")
    }
    print("PROBEOK \(value)")
  }
}

struct AsyncProbeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-async",
    abstract: "Prove the dispatched async witness ran."
  )

  mutating func run() async throws {
    print("ASYNCPROBEOK")
  }
}

@main
struct EntryPointFixtureVerbDispatch: App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "verbdispatch",
    abstract: "Verb-dispatch launch fixture.",
    subcommands: [CompletionsCommand.self, ProbeCommand.self, AsyncProbeCommand.self]
  )

  @OptionGroup(title: "SwiftTUI Options") var swiftTUIOptions: SwiftTUIOptions
  @Argument var path: String?

  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK \(path ?? "none")")
    }
  }

  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    try registeredSubcommand(forRawArguments: arguments)
  }
}
