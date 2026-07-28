import SwiftTUI

// Regression fixture for `EntryPointLaunchTests`: verb dispatch on the launch
// path that never calls `parseSwiftTUIRootCommand`.
//
// `App.main()` branches on whether the conformer declares a *stored*
// `swiftTUIOptions`. This fixture deliberately does not, so it takes the
// `WebHostCLIRunner.run(Self.self)` shortcut — which parses argv with
// `SwiftTUIOptions.parse` and never reaches `parseSwiftTUIRootCommand`. Without
// an explicit consult on that branch, a hook declared here would be silently
// ignored, and no unit test can see it because the decision lives in `main()`.

/// The verb this fixture dispatches. Distinct from the sibling fixture's
/// `probe` only in the marker it prints, so a mixed-up binary is obvious.
struct BareProbeCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe",
    abstract: "Print a value without starting the runtime."
  )

  @Argument var value: String

  func run() throws {
    print("BAREPROBEOK \(value)")
  }
}

struct BareAsyncProbeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe-async",
    abstract: "Prove the no-options dispatch path ran the async witness."
  )

  mutating func run() async throws {
    print("BAREASYNCPROBEOK")
  }
}

@main
struct EntryPointFixtureVerbDispatchNoOptions: App {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "bareverbdispatch",
    abstract: "Verb-dispatch launch fixture with no stored SwiftTUI options.",
    subcommands: [CompletionsCommand.self, BareProbeCommand.self, BareAsyncProbeCommand.self]
  )

  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }

  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    try registeredSubcommand(forRawArguments: arguments)
  }
}
