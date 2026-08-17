public import SwiftTUIArguments
@_spi(Runners) import SwiftTUIRuntime
import Synchronization

/// The installed web-launch arm, when one is linked.
///
/// The launcher routes `--web` here without naming the web-host module: the
/// umbrella (or any host that links the web CLI) installs the runner
/// explicitly at launch — never via module-load side effects, which Swift
/// does not guarantee for a module nothing references. Absent an
/// installation, `--web` fails with the clear not-linked diagnostic.
package enum SwiftTUILaunchRegistry {
  package typealias WebRunner =
    @MainActor @Sendable (any SwiftTUIRuntime.App, RuntimeConfiguration) async throws -> Void

  private static let storage = Mutex<WebRunner?>(nil)

  package static func installWebRunner(_ runner: @escaping WebRunner) {
    storage.withLock { $0 = runner }
  }

  package static var webRunner: WebRunner? {
    storage.withLock { $0 }
  }

  /// Test seam: clears an installed runner so routing tests leave no
  /// process-global state behind.
  package static func resetWebRunnerForTesting() {
    storage.withLock { $0 = nil }
  }
}

/// Routes a SwiftTUI app between terminal-native launch and, when a web
/// runner is installed, the localhost web host.
///
/// This is the platform-neutral launch router (Stage 5.2 of the Windows
/// plan): it lives with the portable terminal half so `import SwiftTUI` +
/// `@main` composes identically on every platform, and only *names* the web
/// arm through ``SwiftTUILaunchRegistry``. The legacy spelling
/// `WebHostCLIRunner` remains in the web CLI module as a delegating facade.
public enum SwiftTUILauncher {
  /// Constructs an app on the main actor and launches it using parsed CLI options.
  @MainActor
  public static func run<A: App>(_ appType: A.Type) async throws {
    try await run(appType.init())
  }

  /// Constructs an app on the main actor and launches it with explicit configuration.
  @MainActor
  public static func run<A: App>(
    _ appType: A.Type,
    configuration: RuntimeConfiguration
  ) async throws {
    try await run(appType.init(), configuration: configuration)
  }

  /// Parses CLI options and launches an app through terminal or web mode.
  @MainActor
  public static func run<A: App>(_ app: A) async throws {
    let options = try SwiftTUIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    try await run(app, configuration: options.runtimeConfiguration())
  }

  /// Launches an app through terminal or web mode with explicit configuration.
  @MainActor
  public static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws {
    guard let webRunner = SwiftTUILaunchRegistry.webRunner else {
      // No web arm installed: TerminalRunner itself rejects `--web` with the
      // clear not-linked diagnostic, so the ordinary launch path stays the
      // single owner of that error.
      try await TerminalRunner.run(app, configuration: configuration)
      return
    }
    try await run(
      app,
      configuration: configuration,
      webRunner: { app, configuration in
        try await webRunner(app, configuration)
      },
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
