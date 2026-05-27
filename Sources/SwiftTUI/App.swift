import Foundation
public import SwiftTUIArguments
public import SwiftTUIRuntime
import SwiftTUIWebHostCLI

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

  private nonisolated static var usesStoredSwiftTUIOptions: Bool {
    Mirror(reflecting: Self.init()).children.contains { child in
      child.label == "_swiftTUIOptions" || child.label == "swiftTUIOptions"
    }
  }

  @MainActor
  private static func runParsedCommand() async throws {
    var command = try parseSwiftTUIRootCommand()
    if let script = completionScript(forParsedCommand: command) {
      FileHandle.standardOutput.write(Data(script.utf8))
      return
    }
    if let installedURL = try installCompletionScript(forParsedCommand: command) {
      let message = "Installed completion script at \(installedURL.path)\n"
      FileHandle.standardOutput.write(Data(message.utf8))
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
