import ArgumentParser
import SwiftTUIRuntime
import Testing

@testable import SwiftTUIArguments

/// Characterization coverage for a root command that declares both a positional
/// argument and its own subcommands.
///
/// swift-argument-parser's `descendingParse` parses the *current* command's
/// arguments before it looks for a subcommand, so a leading bare value binds to
/// the root's positional and the parser never descends: `myapp info x.gif`
/// means "open the file named `info`". `SwiftTUICommand` already intercepts one
/// verb — `completions` — from raw arguments for exactly this reason.
///
/// These rows describe that behavior **as it stands today**. They are the
/// oracle for "a conformer that does nothing keeps behaving exactly as it did":
/// a later change that adds an opt-in verb-dispatch hook must leave every one of
/// them passing unedited. If one ever needs editing to stay green, that change
/// is not additive and is wrong.
///
/// Assertions go through `fullMessage(for:)` / `exitCode(for:)` rather than
/// matching an error type, because `CommandError` is internal to
/// swift-argument-parser. That is the better oracle anyway: those two entry
/// points are the exact rendering path `exit(withError:)` takes in a real
/// process, so the tests pin user-visible text instead of a private struct.
@MainActor
struct RootCommandDispatchTests {

  @Test("T-00 a bare value binds the root positional")
  func bareValueBindsRootPositional() throws {
    let command = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: ["x.gif"])
    let root = try #require(command as? PositionalRootFixture)
    #expect(root.path == "x.gif")
  }

  @Test("T-01 a registered verb is shadowed by the root positional")
  func registeredVerbIsShadowedByRootPositional() throws {
    // The verb name binds to `<path>`; the subcommand is never reached.
    let command = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: ["info"])
    let root = try #require(command as? PositionalRootFixture)
    #expect(root.path == "info")

    // The full symptom: the verb's own argument becomes an extra value the root
    // cannot absorb, so the parse fails with an unexpected-argument error rather
    // than running `info`.
    #expect(throws: (any Error).self) {
      _ = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: ["info", "x.gif"])
    }
  }

  @Test("T-02 completions is intercepted ahead of root positional parsing")
  func completionsIsInterceptedAheadOfRootParsing() throws {
    let command = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: [
      "completions", "print", "zsh",
    ])
    let printCommand = try #require(command as? CompletionsCommand.Print)
    #expect(printCommand.shell.rawValue == "zsh")
  }

  @Test("T-03 --help resolves to a help command attributed to the root")
  func helpResolvesToRootHelp() throws {
    // `parseAsRoot` does not *throw* on `--help`: it returns
    // swift-argument-parser's internal `HelpCommand`, which the launch layers
    // reach through their trailing `try command.run()`. Running it is what
    // throws, and the thrown error carries the command stack the parser built.
    var command = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: ["--help"])
    #expect(!(command is PositionalRootFixture))

    let error = try #require(captureError { try command.run() })
    #expect(PositionalRootFixture.exitCode(for: error) == ExitCode.success)
    let text = PositionalRootFixture.fullMessage(for: error, columns: 120)
    #expect(text.contains("USAGE: posroot"))
  }

  @Test("T-04 no arguments leaves the root positional nil")
  func noArgumentsLeavesPositionalNil() throws {
    let command = try PositionalRootFixture.parseSwiftTUIRootCommand(arguments: [])
    let root = try #require(command as? PositionalRootFixture)
    #expect(root.path == nil)
  }

  // MARK: - Helpers

  /// Runs `body` and returns the error it threw, or `nil`.
  ///
  /// `#expect(throws:)` cannot hand the error back for rendering, and the
  /// rendering *is* the assertion for the attribution rows.
  fileprivate func captureError(_ body: () throws -> Void) -> (any Error)? {
    do {
      try body()
      return nil
    } catch {
      return error
    }
  }
}

// MARK: - Fixtures
//
// Declared inside the test target so they do not leak into the SwiftTUIArguments
// product, matching the convention in `SwiftTUICommandTests.swift`.

/// A root command with both a positional argument and a registered subcommand.
struct PositionalRootFixture: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "posroot",
    subcommands: [CompletionsCommand.self, FixtureInfoCommand.self]
  )

  @OptionGroup(title: "SwiftTUI Options") var swiftTUIOptions: SwiftTUIOptions
  @Argument var path: String?

  init() {}
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
  }
}

/// A headless verb, shaped like the ones a real consumer registers.
struct FixtureInfoCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Print information about a file.",
    aliases: ["nfo"]
  )

  @Argument var file: String
  @Flag(name: .long) var json = false
  /// Selects the error `run()` throws, so the launch-layer attribution of a
  /// `ValidationError` (which carries no command stack of its own) can be
  /// exercised alongside the `ExitCode` case that already carries one.
  @Flag(name: .long) var failValidation = false

  func run() throws {
    if failValidation {
      throw ValidationError("fixture validation failure")
    }
    throw ExitCode(3)
  }
}
