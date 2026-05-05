public import ArgumentParser
public import SwiftTUI
import SwiftTUICLI
public import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A SwiftTUI app with framework-managed argument parsing.
///
/// Conformers gain:
///   - automatic parsing of `CommandLine.arguments` against `SwiftTUIOptions` +
///     any `@Option`/`@Flag`/`@Argument` they declare;
///   - env-var honoring via `SwiftTUIOptions.runtimeConfiguration(...)`;
///   - failure-before-TTY-setup: bad flags exit with `EX_USAGE` in cooked mode,
///     never corrupting the terminal;
///   - `--help` (with the SWIFTTUI OPTIONS section rendered separately) for free.
///
/// Conformers MUST declare a `swiftTUIOptions` stored property:
///
/// ```swift
/// @main
/// @MainActor
/// struct MyApp: @preconcurrency SwiftTUIApp {
///   @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
///   @Option public var widgets: Int = 10
///   var body: some Scene { WindowGroup { ContentView() } }
/// }
/// ```
///
/// The `@MainActor` annotation and `@preconcurrency` conformance are required:
/// `App` requires a `@MainActor`-isolated `init()`, while `ParsableArguments`
/// (parent of `AsyncParsableCommand`) requires a nonisolated `init()`.
/// `@preconcurrency` lets the main-actor `init()` satisfy the nonisolated
/// requirement. A future macro (`@SwiftTUIMain`) could absorb both modifiers.
public protocol SwiftTUIApp: App, AsyncParsableCommand {
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

extension SwiftTUIApp {
  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    swiftTUIOptions.runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
  }

  public func run() async throws {
    let configuration = runtimeConfiguration()
    try await TerminalRunner.run(self, configuration: configuration)
  }

  /// Default entry point. Disambiguates between the `static main()` provided
  /// by `SwiftTUICLI`'s `extension App` and `swift-argument-parser`'s
  /// `extension AsyncParsableCommand` — both have the same signature, so
  /// the compiler refuses to pick one without a tie-breaker. This extension
  /// on the more-refined `SwiftTUIApp` protocol is the tie-breaker.
  ///
  /// Behavior: parse argv via `parseAsRoot(_:)`, then call `run()` on the
  /// parsed instance. `run()` resolves the `RuntimeConfiguration` and invokes
  /// `TerminalRunner.run(_:configuration:)`. Inlined rather than delegated to
  /// `AsyncParsableCommand.main(_:)` because dispatch from a `SwiftTUIApp`
  /// context can resolve to the synchronous `ParsableCommand.main(_:)`
  /// overload, which would bypass the async `run()` path.
  public static func main() async {
    do {
      var command = try parseAsRoot(nil)
      if var asyncCommand = command as? any AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}
