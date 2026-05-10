import Foundation
public import SwiftTUI
import SwiftTUIArguments
import SwiftTUICLI
import SwiftTUIWebHost

public enum WebHostCLIRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  @MainActor
  public static func run<A: App>(
    _ appType: A.Type,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(appType.init(), configuration: configuration)
  }

  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    let options = try SwiftTUIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    try await run(app, configuration: options.runtimeConfiguration())
  }

  @MainActor
  public static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(
      app,
      configuration: configuration,
      webRunner: WebHostRunner.run,
      terminalRunner: TerminalRunner.run
    )
  }

  @MainActor
  package static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration,
    webRunner: @MainActor (A, RuntimeConfiguration) async throws -> Void,
    terminalRunner: @MainActor (A, RuntimeConfiguration) async throws -> Void
  ) async throws {
    if configuration.web != nil {
      try await webRunner(app, configuration)
      return
    }

    try await terminalRunner(app, configuration)
  }

  package static func runtimeConfiguration(
    arguments: [String],
    environment: [String: String],
    isStdoutTTY: Bool
  ) throws -> RuntimeConfiguration {
    try SwiftTUIOptions.parse(arguments)
      .runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
  }
}

extension App where Self: SwiftTUICommand {
  @MainActor public func run() async throws {
    let configuration = runtimeConfiguration()
    try await WebHostCLIRunner.run(self, configuration: configuration)
  }

  /// Default entry point for apps that opt into both `SwiftTUICommand`
  /// argument parsing and the combined terminal/WebHost runner.
  public static func main() async {
    do {
      var command = try parseSwiftTUIRootCommand()
      if let script = completionScript(forParsedCommand: command) {
        FileHandle.standardOutput.write(Data(script.utf8))
        return
      }
      if let installedURL = try installCompletionScript(forParsedCommand: command) {
        let message = "Installed completion script at \(installedURL.path)\n"
        FileHandle.standardOutput.write(Data(message.utf8))
        return
      }
      if let appCommand = command as? Self {
        try await appCommand.run()
        return
      }
      try command.run()
    } catch {
      exit(withError: error)
    }
  }
}
