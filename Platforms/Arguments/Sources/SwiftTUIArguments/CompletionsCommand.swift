public import ArgumentParser

/// Subcommand for managing shell completion scripts.
///
/// `SwiftTUIApp` installs this by default. If an app overrides
/// `CommandConfiguration`, include `CompletionsCommand.self` in its
/// `subcommands` list to keep this surface available.
///
/// `swift-argument-parser` already exposes `--generate-completion-script <shell>`
/// on every command. This subcommand provides a friendlier surface:
///
/// ```text
/// myapp completions print zsh > ~/.zsh/completions/_myapp
/// myapp completions print bash > /usr/local/etc/bash_completion.d/myapp
/// myapp completions print fish > ~/.config/fish/completions/myapp.fish
/// ```
public struct CompletionsCommand: ParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "completions",
    abstract: "Generate or print shell completion scripts.",
    subcommands: [Print.self]
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
        "completions print must run from a SwiftTUIApp root command so the generated script "
          + "includes the app's options."
      )
    }
  }
}
