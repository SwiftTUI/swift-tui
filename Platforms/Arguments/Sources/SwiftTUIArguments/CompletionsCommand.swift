public import ArgumentParser

/// Subcommand for managing shell completion scripts.
///
/// **Status:** Surface defined; runtime wiring is deferred. Invoking
/// `myapp completions print <shell>` currently errors with a redirect to
/// `myapp --generate-completion-script <shell>` (which IS available — every
/// `ParsableCommand` gets it from swift-argument-parser by default).
///
/// Wiring this subcommand to actually emit the script requires
/// `SwiftTUIApp.main()` to detect `CompletionsCommand.Print` after parse and
/// call `Self._generateCompletionScript(...)`. That's a few lines but lives
/// in a follow-up plan.
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
      // Note: SwiftTUIApp.main() does not yet intercept this subcommand to emit
      // a completion script. Until that wiring lands, fall back to swift-argument-
      // parser's standard --generate-completion-script flag, which is auto-provided
      // on every command:
      //
      //   myapp --generate-completion-script \(shell)
      //
      // The friendlier "completions print <shell>" surface is reserved for a
      // follow-up plan; see docs/plans/2026-05-04-002-argument-parsing-plan.md
      // § Follow-up plans.
      throw CleanExit.message(
        "completions subcommand wiring is deferred. For now, use:\n"
        + "  \(CommandLine.arguments[0]) --generate-completion-script \(shell)"
      )
    }
  }
}
