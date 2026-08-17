import Foundation
public import SwiftTUIArguments
@_spi(Runners) import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(ucrt)
  import CRT
#endif

// The `App` terminal launch entry points.
//
// These `App` extensions provide the `@main` entry point for terminal-native
// SwiftTUI apps: the plain `main()` that reads a `RuntimeConfiguration` from
// the environment, and the `SwiftTUICommand` variant that routes through
// argument parsing and shell-completion installation before launching. Both
// delegate the actual run to `TerminalRunner`.
//
// Split out of `TerminalRunner.swift` so that file stays focused on the
// `TerminalRunner` orchestrator. `exitLaunch` travels with them — it is the
// failure path of `App.main()` and has no other caller.

extension App {
  /// Default entry point for terminal-native `SwiftTUI` apps.
  ///
  /// Mark a terminal-only app with `@main` to use this automatically, or call
  /// `TerminalRunner.run(Self.self)` from a custom launcher when you
  /// need explicit error handling.
  ///
  /// Reads env vars (`NO_COLOR`, `LANG=C`, `SWIFTTUI_*`, ...) into a
  /// `RuntimeConfiguration` and passes it through. Bare-mode apps gain
  /// env-var honoring without code change.
  public static func main() async {
    #if os(Windows)
      let isStdoutTTY = _isatty(STDOUT_FILENO) != 0
    #else
      let isStdoutTTY = isatty(STDOUT_FILENO) != 0
    #endif
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: isStdoutTTY
    )
    do {
      try await TerminalRunner.run(Self.self, configuration: configuration)
    } catch {
      exitLaunch(withError: error)
    }
  }
}

extension App where Self: SwiftTUICommand {
  @MainActor public func run() async throws {
    let configuration = runtimeConfiguration()
    try await TerminalRunner.run(self, configuration: configuration)
  }

  /// Default entry point for terminal-native apps that opt into
  /// `SwiftTUICommand` argument parsing.
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
  /// This `-> Never` overload is the most-derived synchronous `main()` for terminal-native commands.
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
  #elseif canImport(ucrt)
    CRT.exit(1)
  #else
    fatalError(String(describing: error))
  #endif
}
