public import SwiftTUI

public enum WebHostRunnerError: Error, Equatable, Sendable, CustomStringConvertible {
  case serverNotImplemented

  public var description: String {
    switch self {
    case .serverNotImplemented:
      return "SwiftTUIWebHost server startup is not implemented yet."
    }
  }
}

public enum WebHostRunner {
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
    try await run(app, configuration: .default)
  }

  @MainActor
  public static func run<A: App>(
    _: A,
    configuration _: RuntimeConfiguration
  ) async throws {
    throw WebHostRunnerError.serverNotImplemented
  }
}
