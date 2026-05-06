public import SwiftTUI
import SwiftTUIArguments
import SwiftTUICLI
import SwiftTUIWebHost

public enum WebHostCLIRunner {
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init(), configuration: .default)
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
    try await run(app, configuration: .default)
  }

  @MainActor
  public static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    if configuration.web != nil {
      try await WebHostRunner.run(app, configuration: configuration)
      return
    }

    try await TerminalRunner.run(app, configuration: configuration)
  }
}
