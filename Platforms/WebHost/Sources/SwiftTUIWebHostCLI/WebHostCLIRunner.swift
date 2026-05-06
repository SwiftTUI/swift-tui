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
