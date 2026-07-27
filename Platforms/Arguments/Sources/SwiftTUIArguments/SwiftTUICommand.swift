public import ArgumentParser
public import Foundation
public import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// A SwiftTUI command with framework-managed argument parsing.
///
/// Conformers gain:
///   - automatic parsing of `CommandLine.arguments` against `SwiftTUIOptions` +
///     any `@Option`/`@Flag`/`@Argument` they declare;
///   - env-var honoring via `SwiftTUIOptions.runtimeConfiguration(...)`;
///   - `--help` with the SWIFTTUI OPTIONS section rendered separately;
///   - completion-script generation helpers.
///
/// Conformers MUST declare a `swiftTUIOptions` stored property:
///
/// ```swift
/// @main
/// struct MyApp: App, SwiftTUICommand {
///   @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
///   @Option public var widgets: Int = 10
///   var body: some Scene { WindowGroup { ContentView() } }
/// }
/// ```
///
/// This protocol is intentionally additive to `App`: it owns argument parsing
/// and runtime-configuration resolution, while runner products such as
/// `SwiftTUICLI` and `SwiftTUIWebHostCLI` own launch behavior.
@MainActor
public protocol SwiftTUICommand: AsyncParsableCommand {
  /// The framework option group. Conformers MUST declare:
  /// `@OptionGroup public var swiftTUIOptions: SwiftTUIOptions`.
  var swiftTUIOptions: SwiftTUIOptions { get }

  /// Resolves `swiftTUIOptions` + environment into the runtime configuration.
  /// Override to customize (e.g. force `accessible: true` regardless of flags).
  func runtimeConfiguration(
    environment: [String: String],
    isStdoutTTY: Bool
  ) -> RuntimeConfiguration

  /// Claims a subcommand verb from raw arguments, before this root command's
  /// own positional parsing runs.
  ///
  /// Returns the parsed subcommand to run, or `nil` to parse `arguments` as
  /// this root command. **The default implementation returns `nil`**, so an app
  /// that does not implement this behaves exactly as it did before.
  ///
  /// Implement it when the root command declares an `@Argument` *and*
  /// registers subcommands. swift-argument-parser parses the current command's
  /// arguments before it looks for a verb, so a leading bare value binds to the
  /// root's positional and the parser never descends — `myapp info x.gif` means
  /// "open the file named `info`". Most apps want the one-line body:
  ///
  /// ```swift
  /// nonisolated static func swiftTUIRootSubcommand(
  ///   forRawArguments arguments: [String]
  /// ) throws -> (any ParsableCommand)? {
  ///   try registeredSubcommand(forRawArguments: arguments)
  /// }
  /// ```
  ///
  /// This routes; it does not register. `--help` and the generated completion
  /// scripts are both built from ``configuration``, so the verbs must still be
  /// listed in its `subcommands`.
  ///
  /// `completions` is resolved by the framework *before* this is called and
  /// cannot be shadowed, disabled, or forgotten by an implementation.
  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)?
}

@available(*, deprecated, renamed: "SwiftTUICommand")
public typealias SwiftTUIApp = SwiftTUICommand

extension SwiftTUICommand {
  public nonisolated static var configuration: CommandConfiguration {
    CommandConfiguration(subcommands: [CompletionsCommand.self])
  }

  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    swiftTUIOptions.runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
  }

  public nonisolated static func completionScript(
    forParsedCommand command: any ParsableCommand
  ) -> String? {
    guard let printCommand = command as? CompletionsCommand.Print else {
      return nil
    }
    return completionScript(for: printCommand.shell.completionShell)
  }

  /// Installs the completion script for an `install` subcommand and returns the
  /// destination file path, or `nil` when `command` is not an install request.
  ///
  /// Returns a plain path string (not a `URL`) so the batteries-included
  /// `SwiftTUI` layer can consume it without importing Foundation.
  public nonisolated static func installCompletionScript(
    forParsedCommand command: any ParsableCommand
  ) throws -> String? {
    guard let installCommand = command as? CompletionsCommand.Install else {
      return nil
    }
    let script = completionScript(for: installCommand.shell.completionShell)
    return try installCommand.install(script: script, commandName: _commandName).path
  }

  public nonisolated static func completionCommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    guard arguments.first == CompletionsCommand.configuration.commandName else {
      return nil
    }
    return try CompletionsCommand.parseAsRoot(Array(arguments.dropFirst()))
  }

  public nonisolated static func parseSwiftTUIRootCommand(
    arguments: [String] = Array(CommandLine.arguments.dropFirst())
  ) throws -> any ParsableCommand {
    if let completionsCommand = try completionCommand(forRawArguments: arguments) {
      return completionsCommand
    }

    // Resolved after `completions` so a conformer's hook can never shadow it,
    // and before `parseAsRoot` so a claimed verb is not first swallowed by the
    // root's own positional.
    if let subcommand = try swiftTUIRootSubcommand(forRawArguments: arguments) {
      return subcommand
    }

    return try parseAsRoot(arguments)
  }
}

/// The synchronous-launch diagnostic text for a command type named `name`.
///
/// Factored out of `failSynchronousLaunch(commandType:)` so the wording can be
/// asserted by a unit test without terminating the test process.
package func synchronousLaunchDiagnosticMessage(commandTypeName name: String) -> String {
  """
  SwiftTUI: `\(name)` was launched through the synchronous `main()` entry \
  point, so the runtime never started.

  SwiftTUI apps are asynchronous -- `App.main()` is `async`. A bare \
  `\(name).main()` call, or `await \(name).main()`, resolves to \
  swift-argument-parser's synchronous `ParsableCommand.main()` overload \
  instead of the async entry point, and that overload does not start the \
  runtime.

  Launch the app with `@main` and remove any explicit `main()` call:

      @main
      struct \(name): App {
        var body: some Scene { /* ... */ }
      }

  """
}

/// Writes the synchronous-launch diagnostic to standard error and exits.
///
/// Shared by the `static func main() -> Never` diagnostic shims that each
/// launch layer co-locates with its async `main()` (see `SwiftTUI.App`,
/// `SwiftTUICLI`, and `SwiftTUIWebHostCLI`). Kept free of `ArgumentParser`'s own
/// (`#if DEBUG`-only) configuration-failure path so the message is identical and
/// present in DEBUG and release builds alike.
package func failSynchronousLaunch(commandType: Any.Type) -> Never {
  let message = synchronousLaunchDiagnosticMessage(
    commandTypeName: String(describing: commandType)
  )
  writeToStandardError(message)
  #if canImport(Darwin)
    Darwin.exit(EXIT_FAILURE)
  #elseif canImport(Glibc)
    Glibc.exit(EXIT_FAILURE)
  #elseif canImport(WASILibc)
    WASILibc.exit(EXIT_FAILURE)
  #else
    fatalError(message)
  #endif
}

private func writeToStandardError(_ text: String) {
  var text = text
  text.withUTF8 { buffer in
    guard let base = buffer.baseAddress, buffer.count > 0 else {
      return
    }
    _ = unsafe write(STDERR_FILENO, base, buffer.count)
  }
}
