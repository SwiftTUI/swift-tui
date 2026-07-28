public import ArgumentParser

// Verb dispatch for a root command that also declares a positional argument.
//
// swift-argument-parser's `descendingParse` parses the *current* command's
// arguments and only then looks for a subcommand, so a leading bare value binds
// to the root's positional and the parser never descends: `myapp info x.gif`
// means "open the file named `info`". `SwiftTUICommand` has always worked around
// this for one verb, by matching `completions` against the raw arguments inside
// `parseSwiftTUIRootCommand`. This file generalizes that move to a conformer's
// own verbs, and carries the attribution a dispatched verb needs so its usage
// text survives the trip back to a launch site's `exit(withError:)`.
//
// The protocol requirement itself lives with the protocol, in
// `SwiftTUICommand.swift`; everything that implements or supports it lives here.

extension SwiftTUICommand {
  /// Default: claim nothing, so the root command parses `arguments` itself.
  ///
  /// Kept deliberately inert rather than defaulting to
  /// ``registeredSubcommand(forRawArguments:)``. Raw-verb interception is not
  /// equivalent to swift-argument-parser's descent: the parser binds the root's
  /// options greedily across the whole argument list *before* it descends, so
  /// for an app whose root and subcommand declare the same option name,
  /// intercepting at `arguments[0]` binds that option to the subcommand where
  /// the parser bound it to the root. A default-on table would therefore change
  /// behavior for existing apps; opting in stays a per-app decision.
  public nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    nil
  }

  /// The registered subcommand named by `arguments.first`, parsed against the
  /// remaining arguments — the body most apps want for
  /// ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)``.
  ///
  /// ```swift
  /// nonisolated static func swiftTUIRootSubcommand(
  ///   forRawArguments arguments: [String]
  /// ) throws -> (any ParsableCommand)? {
  ///   try registeredSubcommand(forRawArguments: arguments)
  /// }
  /// ```
  ///
  /// Matches against ``configuration``'s `subcommands`, comparing each
  /// candidate's command name and its declared aliases. `CompletionsCommand` is
  /// excluded, because the framework resolves that verb before the hook runs.
  ///
  /// Returns `nil` — leaving the arguments to the root command — when
  /// `arguments` is empty, when its first element is empty or begins with `-`,
  /// or when no registered subcommand matches. The leading-`-` rule is what
  /// makes `--help`, `--version`, and the `--` terminator fall through by
  /// construction rather than by luck.
  ///
  /// Only `arguments.first` is examined: a verb behind a root flag
  /// (`myapp --json info x`) is *not* claimed. Keeping interception strictly
  /// narrower than the parser's own descent is what bounds the set of apps
  /// whose option binding could change.
  ///
  /// A verb always beats a file of the same name. `myapp info` runs the `info`
  /// verb even when a file named `info` exists in the working directory, and no
  /// filesystem probe is performed — a command line whose meaning depends on
  /// the contents of the current directory is neither reproducible nor
  /// testable, and `git`, `docker`, and `swift` all resolve it this way. To
  /// name such a file, qualify it (`myapp ./info`) or push it past the argument
  /// terminator (`myapp -- info`).
  ///
  /// - Throws: The dispatched command's own parse error, wrapped so that a
  ///   launch site can attribute usage text to the verb. See
  ///   ``DispatchedSubcommandError``.
  public nonisolated static func registeredSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    guard let verb = arguments.first, !verb.isEmpty, !verb.hasPrefix("-") else {
      return nil
    }
    let match = configuration.subcommands.first { subcommand in
      guard ObjectIdentifier(subcommand) != ObjectIdentifier(CompletionsCommand.self) else {
        return false
      }
      return subcommand._commandName == verb || subcommand.configuration.aliases.contains(verb)
    }
    guard let match else {
      return nil
    }
    do {
      return try match.parseAsRoot(Array(arguments.dropFirst()))
    } catch {
      throw DispatchedSubcommandError(subcommandType: match, underlying: error)
    }
  }
}

/// Runs a dispatched (non-root) command, honoring an async conformance the
/// same way swift-argument-parser's `AsyncParsableCommand.main()` does.
///
/// Shared by every launch layer so the execution tail cannot drift apart.
package func runDispatchedRootSubcommand(
  _ command: sending any ParsableCommand
) async throws {
  if var asyncCommand = command as? any AsyncParsableCommand {
    try await asyncCommand.run()
  } else {
    var command = command
    try command.run()
  }
}

/// A failure while parsing a verb claimed by
/// ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)``, carrying the
/// verb's type so a launch site can render usage for the verb rather than for
/// the root command.
///
/// This exists because one attribution case cannot be recovered downstream.
/// swift-argument-parser normally attaches the command stack to the error it
/// throws, and `MessageInfo` prefers that stack over the type it is handed — so
/// `myapp info --help` and `myapp info --bogus` print `info`'s help without any
/// help from us. But when the dispatched verb receives *no* further arguments,
/// `CommandParser.parse` rewraps the failure as `ParserError.noArguments`, and
/// the renderer special-cases that by ignoring the stack and generating help
/// for `type.asCommand` instead. `myapp info` (with `<file>` missing) would
/// therefore print the root's usage under the verb's error message.
///
/// Rather than have every launch site re-derive the verb from raw arguments —
/// which cannot tell a claimed verb from a positional that merely looks like
/// one — the claim carries its own attribution back out.
///
/// Deliberately not public: launch sites resolve it through
/// ``exitAttributingDispatchedSubcommand(_:dispatchedCommandType:root:)``, and
/// consumers neither construct nor catch it. `description` renders the fully
/// attributed message so that a consumer who hand-rolls a launch sequence and
/// passes this straight to `exit(withError:)` still gets readable, correctly
/// attributed output rather than a struct dump.
package struct DispatchedSubcommandError: Error, CustomStringConvertible {
  package let subcommandType: any ParsableCommand.Type
  package let underlying: any Error

  package var description: String {
    subcommandType.fullMessage(for: underlying)
  }
}

/// Terminates the process for `error`, rendering usage for whichever command
/// the failure belongs to.
///
/// Shared by the three launch layers (`SwiftTUI`, `SwiftTUICLI`, and
/// `SwiftTUIWebHostCLI`) so they cannot drift apart on attribution. The rules,
/// in order:
///
///   1. A ``DispatchedSubcommandError`` names its own verb — the verb's parse
///      failed, so no instance of it exists to inspect.
///   2. Otherwise, if a dispatched command was reached and ran, the failure is
///      the verb's and is rendered through the verb's dynamic type. This is
///      what attributes a `ValidationError` thrown from a dispatched `run()`,
///      which carries no command stack of its own.
///   3. Otherwise the failure is the root command's.
///
/// Errors that already carry a command stack — parse errors, `--help`,
/// `--version` — are unaffected by which type they are rendered through, since
/// `MessageInfo` prefers the stack on the error. `ExitCode` is likewise
/// untouched: it maps to an exact status with no usage text at all.
package func exitAttributingDispatchedSubcommand(
  _ error: any Error,
  dispatchedCommandType: (any ParsableCommand.Type)?,
  root rootType: any ParsableArguments.Type
) -> Never {
  if let dispatchError = error as? DispatchedSubcommandError {
    dispatchError.subcommandType.exit(withError: dispatchError.underlying)
  }
  if let dispatchedCommandType {
    dispatchedCommandType.exit(withError: error)
  }
  rootType.exit(withError: error)
}
