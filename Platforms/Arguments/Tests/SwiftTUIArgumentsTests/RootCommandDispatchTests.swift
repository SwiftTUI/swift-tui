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

  // MARK: - T-05…T-13 — the opt-in hook
  //
  // Everything above this line is the frozen oracle: `PositionalRootFixture`
  // declares no hook, and its rows must keep passing unedited. Everything below
  // uses `DispatchingRootFixture`, which is the same fixture plus the one-line
  // adoption body.

  @Test("T-05 a registered verb wins over the root positional")
  func registeredVerbWinsOverRootPositional() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: [
      "info", "x.gif",
    ])
    let info = try #require(command as? FixtureInfoCommand)
    #expect(info.file == "x.gif")
    #expect(info.json == false)
  }

  @Test("T-06 a leading -- terminator falls through to the root")
  func terminatorFallsThroughToRoot() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["--", "info"])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "info")
  }

  @Test("T-07 a path-qualified value can never match a verb")
  func pathQualifiedValueNeverMatchesVerb() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["./info"])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "./info")
  }

  @Test("T-08 a non-verb value still binds the root positional")
  func nonVerbValueStillBindsRootPositional() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["x.gif"])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "x.gif")
  }

  @Test("T-09 completions beats a consumer hook that would claim it")
  func completionsBeatsConsumerHook() throws {
    // `ShadowingCompletionsFixture`'s hook claims every verb it is asked about,
    // `completions` included. The framework resolves `completions` before the
    // hook runs, so a consumer cannot shadow, disable, or forget it.
    let command = try ShadowingCompletionsFixture.parseSwiftTUIRootCommand(arguments: [
      "completions", "print", "zsh",
    ])
    let printCommand = try #require(command as? CompletionsCommand.Print)
    #expect(printCommand.shell.rawValue == "zsh")
  }

  @Test("T-09b registeredSubcommand never claims completions itself")
  func registeredSubcommandNeverClaimsCompletions() throws {
    // The helper excludes `CompletionsCommand` from the table it derives, so
    // the verb cannot be handled twice even if the hook were reached first.
    let claimed = try DispatchingRootFixture.registeredSubcommand(forRawArguments: [
      "completions", "print", "zsh",
    ])
    #expect(claimed == nil)
  }

  @Test("T-10 --help with a hook installed still resolves the root's help")
  func helpWithHookResolvesRootHelp() throws {
    var command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["--help"])
    #expect(!(command is DispatchingRootFixture))

    let error = try #require(captureError { try command.run() })
    #expect(DispatchingRootFixture.exitCode(for: error) == ExitCode.success)
    let text = DispatchingRootFixture.fullMessage(for: error, columns: 120)
    #expect(text.contains("USAGE: dispatchroot"))
  }

  @Test("T-11 a dispatched verb's --help is attributed to the verb")
  func dispatchedVerbHelpIsAttributedToVerb() throws {
    var command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: [
      "info", "--help",
    ])
    let error = try #require(captureError { try command.run() })

    // Rendered through the *root* type, exactly as a launch site's
    // `exit(withError:)` does. `MessageInfo` takes the command stack from the
    // error rather than from the type it is handed, so the text is `info`'s.
    #expect(DispatchingRootFixture.exitCode(for: error) == ExitCode.success)
    let text = DispatchingRootFixture.fullMessage(for: error, columns: 120)
    #expect(text.contains("USAGE: info"))
    #expect(!text.contains("USAGE: dispatchroot"))
  }

  @Test("T-11b a dispatched verb's parse error carries the verb's attribution")
  func dispatchedVerbParseErrorCarriesAttribution() throws {
    // `info` requires <file>; omitting it fails inside the dispatched parse
    // with *no further arguments*, which is the one case the error's own
    // command stack cannot rescue: `CommandParser.parse` rewraps an empty-
    // argument failure as `ParserError.noArguments`, and `MessageInfo`
    // special-cases that by rendering help for the type it was handed rather
    // than for the stack on the error. Rendering through the root would print
    // the root's usage under `info`'s error message.
    let error = try #require(
      captureError {
        _ = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["info"])
      }
    )
    let dispatchError = try #require(error as? DispatchedSubcommandError)
    #expect(
      ObjectIdentifier(dispatchError.subcommandType) == ObjectIdentifier(FixtureInfoCommand.self)
    )

    // The launch layers render through the carried type, which is correct...
    let attributed = dispatchError.subcommandType.fullMessage(
      for: dispatchError.underlying,
      columns: 120
    )
    #expect(attributed.contains("Missing expected argument '<file>'"))
    #expect(attributed.contains("USAGE: info"))
    #expect(!attributed.contains("USAGE: dispatchroot"))

    // ...where rendering the same underlying error through the root is not.
    // This is the trap the carried type exists to avoid; asserting it here
    // keeps the reason for `DispatchedSubcommandError` from being optimized
    // away by someone who cannot reproduce the failure.
    let misattributed = DispatchingRootFixture.fullMessage(
      for: dispatchError.underlying,
      columns: 120
    )
    #expect(misattributed.contains("USAGE: dispatchroot"))
  }

  @Test("T-11c a dispatched verb's flag error is attributed without a wrapper")
  func dispatchedVerbFlagErrorIsAttributedWithoutWrapper() throws {
    // With at least one further argument the failure keeps its own command
    // stack, so it renders correctly through *any* type. Pinning this proves
    // the wrapper is needed only for the `noArguments` case and is not doing
    // work swift-argument-parser already does.
    let error = try #require(
      captureError {
        _ = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["info", "--bogus"])
      }
    )
    let dispatchError = try #require(error as? DispatchedSubcommandError)
    let text = DispatchingRootFixture.fullMessage(for: dispatchError.underlying, columns: 120)
    // A recoverable parse error renders the compact `Usage:` line rather than
    // the full `USAGE:` help screen the `noArguments` path produces.
    #expect(text.contains("Usage: info"))
    #expect(!text.contains("dispatchroot"))
  }

  @Test("T-11d the dispatch wrapper renders attributed text when unwrapped")
  func dispatchWrapperRendersAttributedText() throws {
    // A consumer who hand-rolls a launch sequence passes the wrapper straight
    // to `exit(withError:)`. That path renders `description`, so it must be the
    // correctly attributed message rather than a struct dump.
    let error = try #require(
      captureError {
        _ = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["info"])
      }
    )
    let described = String(describing: error)
    #expect(described.contains("USAGE: info"))
    #expect(!described.contains("DispatchedSubcommandError"))
  }

  @Test("T-12 interception looks at the first argument only")
  func interceptionLooksAtFirstArgumentOnly() throws {
    // A verb behind a root flag is NOT claimed. This keeps interception
    // strictly narrower than swift-argument-parser's own descent, which is what
    // bounds the set of apps whose option binding can change. It fails loudly
    // if the matcher is ever "improved" to scan the whole argument list.
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: [
      "--verbose", "info",
    ])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "info")
    #expect(root.swiftTUIOptions.verbose == 1)
  }

  @Test("T-13 a declared alias resolves to the verb")
  func declaredAliasResolvesToVerb() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["nfo", "x.gif"])
    let info = try #require(command as? FixtureInfoCommand)
    #expect(info.file == "x.gif")
  }

  @Test("T-13b an unregistered verb is not claimed")
  func unregisteredVerbIsNotClaimed() throws {
    // swift-argument-parser adds `help` to the command *tree*, not to
    // `configuration.subcommands`, so it stays outside the derived table and
    // keeps its pre-existing shadowed behavior.
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: ["help"])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "help")
  }

  @Test("T-13c an empty first argument is not claimed")
  func emptyFirstArgumentIsNotClaimed() throws {
    let command = try DispatchingRootFixture.parseSwiftTUIRootCommand(arguments: [""])
    let root = try #require(command as? DispatchingRootFixture)
    #expect(root.path == "")
  }

  @Test("T-14 the default hook claims nothing")
  func defaultHookClaimsNothing() throws {
    // The no-op proof at the seam itself: the fixture that declares no hook
    // gets the default implementation, and that default returns nil for the
    // very argument vector its own registered table would otherwise match.
    let claimed = try PositionalRootFixture.swiftTUIRootSubcommand(forRawArguments: [
      "info", "x.gif",
    ])
    #expect(claimed == nil)
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

/// `PositionalRootFixture` plus the one-line hook — the shape a consumer adopts.
struct DispatchingRootFixture: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "dispatchroot",
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

  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    try registeredSubcommand(forRawArguments: arguments)
  }
}

/// A conformer whose hook claims every verb it is asked about, `completions`
/// included. Proves the framework resolves `completions` first regardless.
struct ShadowingCompletionsFixture: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "shadowroot",
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

  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    guard !arguments.isEmpty else { return nil }
    return try FixtureInfoCommand.parseAsRoot(Array(arguments.dropFirst()))
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
