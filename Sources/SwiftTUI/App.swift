public import SwiftTUIArguments
public import SwiftTUIRuntime
import SwiftTUIWebHostCLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The batteries-included SwiftTUI app protocol.
///
/// `SwiftTUI.App` refines the platform-neutral `SwiftTUIRuntime.App` with the
/// command surface that the convenience product already exports. Import
/// A host-managed app can import `SwiftTUIRuntime` directly to remain independent of command-line parsing.
@MainActor
public protocol App: SwiftTUIRuntime.App, SwiftTUICommand {}

extension App {
  /// Source-compatible default for plain apps that do not declare command
  /// options. Apps with app-specific `@Option`, `@Flag`, or `@Argument`
  /// properties must declare a stored `@OptionGroup var swiftTUIOptions`.
  public var swiftTUIOptions: SwiftTUIOptions {
    SwiftTUIOptions()
  }

  /// Default entry point for batteries-included apps.
  public static func main() async {
    var dispatchedCommandType: (any ParsableCommand.Type)?
    do {
      if usesStoredSwiftTUIOptions {
        try await runParsedCommand(dispatchedCommandType: &dispatchedCommandType)
      } else {
        // An app with no stored `swiftTUIOptions` skips
        // `parseSwiftTUIRootCommand` entirely, so its verb-dispatch hook would
        // otherwise be silently ignored on this path. Consult it here too. The
        // default hook returns nil, so this is a no-op for every app that
        // declares none.
        if let subcommand = try swiftTUIRootSubcommand(
          forRawArguments: Array(CommandLine.arguments.dropFirst())
        ) {
          dispatchedCommandType = type(of: subcommand)
          try await runDispatchedRootSubcommand(subcommand)
          return
        }
        try await WebHostCLIRunner.run(Self.self)
      }
    } catch {
      exitAttributingDispatchedSubcommand(
        error,
        dispatchedCommandType: dispatchedCommandType,
        root: Self.self
      )
    }
  }

  /// Diagnostic shim for the synchronous-`main()` launch trap.
  ///
  /// `App` refines `SwiftTUICommand` → `AsyncParsableCommand`, whose entry
  /// point is `static func main() async` — bound correctly by `@main`. A bare
  /// A top-level `MyApp.main()` call can come from experience with the synchronous `SwiftUI.App.main()`.
  /// An `await MyApp.main()` call has the same result.
  /// Both calls resolve to the synchronous `ParsableCommand.main()` overload in swift-argument-parser.
  /// This overload does not start the runtime.
  /// In DEBUG, it stops with the misleading "asynchronous root command needs availability annotation" message.
  /// In release builds, the guard does not exist.
  /// Then the overload parses the app as the root command and prints the usage screen.
  ///
  /// This overload, co-located with the async `main()` above, shadows that
  /// path. It is the most-derived synchronous `main()`, so a call selects it.
  /// The result is one clear failure in DEBUG and release builds.
  /// Its `-> Never` return keeps it invisible to `@main` synthesis.
  /// A `() -> Never` function is not a valid `@main` entry-point signature.
  /// Thus, an `@main` app binds the asynchronous entry point without ambiguity.
  public static func main() -> Never {
    failSynchronousLaunch(commandType: self)
  }

  private nonisolated static var usesStoredSwiftTUIOptions: Bool {
    Mirror(reflecting: Self.init()).children.contains { child in
      child.label == "_swiftTUIOptions" || child.label == "swiftTUIOptions"
    }
  }

  /// Resolves and runs the parsed command.
  ///
  /// Reports the dispatched subcommand through `dispatched` *before* running
  /// it, not as a return value, so the caller's `catch` can attribute an error
  /// thrown by `run()` to the command that threw it.
  @MainActor
  private static func runParsedCommand(
    dispatchedCommandType: inout (any ParsableCommand.Type)?
  ) async throws {
    let command = try parseSwiftTUIRootCommand()
    if let script = completionScript(forParsedCommand: command) {
      writeToStandardOutput(script)
      return
    }
    if let installedPath = try installCompletionScript(forParsedCommand: command) {
      writeToStandardOutput("Installed completion script at \(installedPath)\n")
      return
    }
    if let appCommand = command as? Self {
      try await WebHostCLIRunner.run(
        appCommand,
        configuration: appCommand.runtimeConfiguration()
      )
      return
    }
    // Anything reaching here is not the root app: a verb the hook claimed, or
    // swift-argument-parser's own help command. Record it so a failure from
    // `run()` is rendered with that command's usage rather than the app's.
    dispatchedCommandType = type(of: command)
    try await runDispatchedRootSubcommand(command)
  }
}

/// Writes UTF-8 text to standard output without Foundation, keeping the
/// batteries-included layer free of `import Foundation`.
private func writeToStandardOutput(_ text: String) {
  var text = text
  text.withUTF8 { buffer in
    guard let base = buffer.baseAddress, buffer.count > 0 else {
      return
    }
    _ = unsafe write(STDOUT_FILENO, base, buffer.count)
  }
}
