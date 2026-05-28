import Foundation
public import SwiftTUIArguments
@_spi(Runners) import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
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
    let configuration = RuntimeConfiguration.detect(
      environment: ProcessInfo.processInfo.environment,
      isStdoutTTY: isatty(STDOUT_FILENO) != 0
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
    do {
      var command = try parseSwiftTUIRootCommand()
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
      try command.run()
    } catch {
      exit(withError: error)
    }
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
