public import ArgumentParser

/// Subcommand for managing shell completion scripts.
///
/// Add this to a `SwiftTUIApp` (or any `AsyncParsableCommand`) by extending
/// its `CommandConfiguration.subcommands` to include `CompletionsCommand.self`.
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

  public struct Print: ParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "print",
      abstract: "Print the completion script for <shell> to stdout."
    )

    @Argument(help: "Shell name: zsh | bash | fish.")
    public var shell: String

    public init() {}

    public mutating func run() throws {
      // The actual generation is delegated to swift-argument-parser's
      // existing --generate-completion-script <shell> machinery on the root
      // command. Consumers wire this by handling the shell name and printing
      // the result; the framework documents the integration but does not
      // execute the codegen here (it requires access to the root command).
      // For now we error if invoked directly; SwiftTUIApp's main() intercepts.
      throw CleanExit.message(
        "Run with the parent command attached: e.g., `myapp completions print \(shell)`."
      )
    }
  }
}
