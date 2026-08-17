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

  /// Routes a SwiftTUI app between terminal-native and localhost WebHost launch.
  public enum WebHostCLIRunner {
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

    /// Parses CLI options and launches an app through terminal or WebHost mode.
    @MainActor
    public static func run<A: App>(_ app: A) async throws {
      let options = try SwiftTUIOptions.parse(Array(CommandLine.arguments.dropFirst()))
      try await run(app, configuration: options.runtimeConfiguration())
    }

    /// Launches an app through terminal or WebHost mode with explicit configuration.
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
