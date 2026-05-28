public import ArgumentParser
public import Foundation
public import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
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

    return try parseAsRoot(arguments)
  }
}
