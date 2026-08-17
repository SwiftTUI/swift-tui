// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  import Foundation
  import SwiftTUIArguments
  public import SwiftTUIRuntime
  import SwiftTUITerminalCLI
  import SwiftTUIWebHost

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #endif

  /// Installs the web-launch arm into the portable launcher's registry.
  ///
  /// Called explicitly at launch by every entry that links this module (the
  /// umbrella's `App.main()` and the facade entries below) — never via
  /// module-load side effects, which Swift does not guarantee. Idempotent:
  /// installing again replaces the arm with an identical one.
  package func installWebHostRunner() {
    SwiftTUILaunchRegistry.installWebRunner { app, configuration in
      try await WebHostRunner.run(app, configuration: configuration)
    }
  }

  /// Routes a SwiftTUI app between terminal-native and localhost WebHost launch.
  ///
  /// Legacy spelling: the router itself is `SwiftTUITerminalCLI.SwiftTUILauncher`
  /// (Stage 5.2 of the Windows plan), which this facade installs the web arm
  /// into and delegates to. Prefer `SwiftTUILauncher` in new code; a formal
  /// deprecation of this name waits for a release boundary so in-repo
  /// coverage keeps building under warnings-as-errors.
  public enum WebHostCLIRunner {
    /// Constructs an app on the main actor and launches it using parsed CLI options.
    @MainActor
    public static func run<A: App>(_ appType: A.Type) async throws {
      installWebHostRunner()
      try await SwiftTUILauncher.run(appType)
    }

    /// Constructs an app on the main actor and launches it with explicit configuration.
    @MainActor
    public static func run<A: App>(
      _ appType: A.Type,
      configuration: RuntimeConfiguration
    ) async throws {
      installWebHostRunner()
      try await SwiftTUILauncher.run(appType, configuration: configuration)
    }

    /// Parses CLI options and launches an app through terminal or WebHost mode.
    @MainActor
    public static func run<A: App>(_ app: A) async throws {
      installWebHostRunner()
      try await SwiftTUILauncher.run(app)
    }

    /// Launches an app through terminal or WebHost mode with explicit configuration.
    @MainActor
    public static func run<A: App>(
      _ app: A,
      configuration: RuntimeConfiguration
    ) async throws {
      installWebHostRunner()
      try await SwiftTUILauncher.run(app, configuration: configuration)
    }

    @MainActor
    package static func run<A: App>(
      _ app: A,
      configuration: RuntimeConfiguration,
      webRunner: @MainActor (A, RuntimeConfiguration) async throws -> Void,
      terminalRunner: @MainActor (A, RuntimeConfiguration) async throws -> Void
    ) async throws {
      try await SwiftTUILauncher.run(
        app,
        configuration: configuration,
        webRunner: webRunner,
        terminalRunner: terminalRunner
      )
    }

    package static func runtimeConfiguration(
      arguments: [String],
      environment: [String: String],
      isStdoutTTY: Bool
    ) throws -> RuntimeConfiguration {
      try SwiftTUILauncher.runtimeConfiguration(
        arguments: arguments,
        environment: environment,
        isStdoutTTY: isStdoutTTY
      )
    }
  }

  extension App {
    /// Default entry point for apps that opt into the combined terminal/WebHost
    /// runner without defining app-specific command parsing.
    public static func main() async {
      do {
        try await WebHostCLIRunner.run(Self.self)
      } catch {
        exitLaunch(withError: error)
      }
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
      var dispatchedCommandType: (any ParsableCommand.Type)?
      do {
        let command = try parseSwiftTUIRootCommand()
        if let script = completionScript(forParsedCommand: command) {
          FileHandle.standardOutput.write(Data(script.utf8))
          return
        }
        if let installedPath = try installCompletionScript(forParsedCommand: command) {
          let message = "Installed completion script at \(installedPath)\n"
          FileHandle.standardOutput.write(Data(message.utf8))
          return
        }
        if let appCommand = command as? Self {
          try await appCommand.run()
          return
        }
        // Not the root app: a verb the hook claimed, or swift-argument-parser's
        // own help command. Record it before running so a failure is rendered
        // with that command's usage rather than the app's.
        dispatchedCommandType = type(of: command)
        try await runDispatchedRootSubcommand(command)
      } catch {
        exitAttributingDispatchedSubcommand(
          error,
          dispatchedCommandType: dispatchedCommandType,
          root: Self.self
        )
      }
    }

    /// Diagnostic shim for the synchronous-`main()` launch trap.
    /// This shim is next to the asynchronous `main()` method above.
    /// See `SwiftTUI.App.main() -> Never` for the full rationale.
    /// Otherwise, a bare `MyApp.main()` or `await MyApp.main()` selects the synchronous `ParsableCommand.main()` overload.
    /// That overload does not start the runtime.
    /// This `-> Never` overload is the most-derived synchronous `main()` for terminal/WebHost commands.
    /// Thus, a bare call selects this overload and gives an accurate failure.
    /// The overload remains invisible to `@main` synthesis.
    public static func main() -> Never {
      failSynchronousLaunch(commandType: self)
    }
  }

  private func exitLaunch(withError error: any Error) -> Never {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    #if canImport(Darwin)
      Darwin.exit(1)
    #elseif canImport(Glibc)
      Glibc.exit(1)
    #else
      fatalError(String(describing: error))
    #endif
  }
#endif
