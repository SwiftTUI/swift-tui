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
/// `SwiftTUIRuntime` directly when a host-managed app should stay independent
/// from command-line parsing.
@MainActor
public protocol App: SwiftTUIRuntime.App, SwiftTUICommand {}

extension App {
  /// Source-compatible default for plain apps that do not declare command
  /// options. Apps with app-specific `@Option`, `@Flag`, or `@Argument`
  /// properties should declare a stored `@OptionGroup var swiftTUIOptions`.
  public var swiftTUIOptions: SwiftTUIOptions {
    SwiftTUIOptions()
  }

  /// Default entry point for batteries-included apps.
  public static func main() async {
    do {
      if usesStoredSwiftTUIOptions {
        try await runParsedCommand()
      } else {
        try await WebHostCLIRunner.run(Self.self)
      }
    } catch {
      Self.exit(withError: error)
    }
  }

  /// Diagnostic shim for the synchronous-`main()` launch trap.
  ///
  /// `App` refines `SwiftTUICommand` → `AsyncParsableCommand`, whose entry
  /// point is `static func main() async` — bound correctly by `@main`. A bare
  /// top-level `MyApp.main()` (the muscle-memory from synchronous
  /// `SwiftUI.App.main()`), or `await MyApp.main()`, instead resolves to
  /// swift-argument-parser's *synchronous* `ParsableCommand.main()` overload,
  /// which never starts the runtime: in DEBUG it aborts with a misleading
  /// "asynchronous root command needs availability annotation" message, and in
  /// release the guard is compiled out, so it silently parses-as-root and
  /// prints the usage screen.
  ///
  /// This overload, co-located with the async `main()` above, shadows that
  /// path. It is the most-derived *synchronous* `main()`, so a bare call
  /// selects it and gets a single loud, accurate failure in DEBUG and release
  /// alike, while its `-> Never` return keeps it invisible to `@main` synthesis
  /// (`() -> Never` is not a valid `@main` entry-point signature). `@main` apps
  /// still bind the async entry point with no ambiguity.
  public static func main() -> Never {
    failSynchronousLaunch(commandType: self)
  }

  private nonisolated static var usesStoredSwiftTUIOptions: Bool {
    Mirror(reflecting: Self.init()).children.contains { child in
      child.label == "_swiftTUIOptions" || child.label == "swiftTUIOptions"
    }
  }

  @MainActor
  private static func runParsedCommand() async throws {
    var command = try parseSwiftTUIRootCommand()
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
    try command.run()
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
