public import ArgumentParser
import Foundation

/// Subcommand for managing shell completion scripts.
///
/// `SwiftTUICommand` installs this by default. If an app overrides
/// `CommandConfiguration`, include `CompletionsCommand.self` in its
/// `subcommands` list to keep this surface available.
///
/// `swift-argument-parser` already exposes `--generate-completion-script <shell>`
/// on every command. This subcommand provides a friendlier surface:
///
/// ```text
/// myapp completions print zsh > ~/.zsh/completions/_myapp
/// myapp completions install bash
/// myapp completions install fish --output ~/.config/fish/completions/myapp.fish
/// ```
public struct CompletionsCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "completions",
    abstract: "Generate or print shell completion scripts.",
    subcommands: [Print.self, Install.self]
  )

  public init() {}

  enum Shell: String, CaseIterable, ExpressibleByArgument, Sendable {
    case zsh
    case bash
    case fish

    var completionShell: CompletionShell {
      switch self {
      case .zsh:
        .zsh
      case .bash:
        .bash
      case .fish:
        .fish
      }
    }
  }

  public struct Print: ParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "print",
      abstract: "Print the completion script for <shell> to stdout."
    )

    @Argument(help: "Shell name: zsh | bash | fish.")
    var shell: Shell

    public init() {}

    public mutating func run() throws {
      throw CleanExit.message(
        "completions print must run from a SwiftTUICommand root command so the generated script "
          + "includes the app's options."
      )
    }
  }

  public struct Install: ParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "install",
      abstract: "Install the completion script for <shell> in a user-writable location."
    )

    @Argument(help: "Shell name: zsh | bash | fish.")
    var shell: Shell

    @Option(
      name: .customLong("output"),
      help: "Write to PATH instead of the default shell completion location."
    )
    var outputPath: String?

    public init() {}

    public mutating func run() throws {
      throw CleanExit.message(
        "completions install must run from a SwiftTUICommand root command so the generated script "
          + "includes the app's options."
      )
    }

    func install(
      script: String,
      commandName: String,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
      let destination = try destinationURL(commandName: commandName, environment: environment)
      let directory = destination.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try script.write(to: destination, atomically: true, encoding: .utf8)
      return destination
    }

    func destinationURL(
      commandName: String,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
      if let outputPath {
        return URL(
          fileURLWithPath: Self.expandTilde(
            in: outputPath,
            homeDirectory: environment["HOME"]
          )
        )
      }
      return try Self.defaultInstallURL(
        for: shell,
        commandName: commandName,
        environment: environment
      )
    }

    static func defaultInstallURL(
      for shell: Shell,
      commandName: String,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
      guard let homeDirectory = environment["HOME"], !homeDirectory.isEmpty else {
        throw ValidationError(
          "Cannot determine the home directory for completion installation; pass --output."
        )
      }

      let home = URL(fileURLWithPath: homeDirectory, isDirectory: true)
      switch shell {
      case .zsh:
        return
          home
          .appendingPathComponent(".zsh/completions", isDirectory: true)
          .appendingPathComponent("_\(commandName)")
      case .bash:
        return
          home
          .appendingPathComponent(".local/share/bash-completion/completions", isDirectory: true)
          .appendingPathComponent(commandName)
      case .fish:
        return
          home
          .appendingPathComponent(".config/fish/completions", isDirectory: true)
          .appendingPathComponent("\(commandName).fish")
      }
    }

    static func expandTilde(in path: String, homeDirectory: String?) -> String {
      guard let homeDirectory, !homeDirectory.isEmpty else {
        return path
      }
      if path == "~" {
        return homeDirectory
      }
      if path.hasPrefix("~/") {
        return homeDirectory + String(path.dropFirst())
      }
      return path
    }
  }
}
