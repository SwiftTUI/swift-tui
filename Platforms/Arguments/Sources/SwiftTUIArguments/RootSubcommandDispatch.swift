public import ArgumentParser

// Verb dispatch for a root command that also declares a positional argument.
//
// swift-argument-parser's `descendingParse` parses the *current* command's
// arguments first. It then looks for a subcommand. Thus, a leading bare value
// binds to the root's positional, and the parser never descends. In
// `myapp info x.gif`, `info` names the file to open.
//
// `SwiftTUICommand` already handles the `completions` verb this way.
// `parseSwiftTUIRootCommand` matches that verb against the raw arguments. This
// file extends the approach to a conformer's own verbs. It also carries the
// attribution needed to preserve usage text through the launch site's
// `exit(withError:)` call.
//
// The protocol requirement itself lives with the protocol, in
// `SwiftTUICommand.swift`; everything that implements or supports it lives here.

extension SwiftTUICommand {
  /// Default: claim nothing, so the root command parses `arguments` itself.
  ///
  /// Kept deliberately inert rather than defaulting to
  /// ``registeredSubcommand(forRawArguments:)``.
  /// Raw-verb interception is different from the descent of swift-argument-parser.
  /// The parser binds the root options across the full argument list before it descends.
  /// An app can declare the same option name for its root and subcommand.
  /// In that case, interception at `arguments[0]` binds the option to the subcommand.
  /// The parser binds the option to the root.
  /// Thus, a default-on table changes the behavior of existing apps.
  /// Each app must explicitly select interception.
  public nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    nil
  }

  /// The registered subcommand named by `arguments.first`, parsed against the
  /// remaining arguments: the body most apps want for
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
  /// Matches the `subcommands` in ``configuration``.
  /// It compares the command name and declared aliases of each candidate.
  /// `CompletionsCommand` is
  /// excluded, because the framework resolves that verb before the hook runs.
  ///
  /// Returns `nil` when `arguments` is empty.
  /// It also returns `nil` when the first element is empty or begins with `-`.
  /// It returns `nil` when no registered subcommand matches.
  /// In these cases, the root command receives the arguments.
  /// The leading-`-` rule
  /// makes `--help`, `--version`, and the `--` terminator fall through by
  /// construction rather than by luck.
  ///
  /// The function examines only `arguments.first`.
  /// It does *not* claim a verb behind a root flag (`myapp --json info x`).
  /// This narrow interception limits the apps whose option binding can change.
  ///
  /// A verb always takes precedence over a file of the same name.
  /// `myapp info` runs the `info` verb when the working directory contains a file named `info`.
  /// The function does not examine the file system.
  /// Thus, directory contents cannot change the meaning of the command line.
  /// The `git`, `docker`, and `swift` tools resolve this case in the same way.
  /// To name the file, qualify it as `myapp ./info`.
  /// You can also put it after the argument terminator as `myapp -- info`.
  ///
  /// - Throws: The dispatched command's own parse error, wrapped so that a
  ///   launch site can attribute usage text to the verb. See the internal
  ///   `DispatchedSubcommandError`.
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
/// ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)``.
/// It carries the verb's type. Thus, a launch site can render usage for the verb
/// instead of the root command.
///
/// This exists because one attribution case cannot be recovered downstream.
/// The swift-argument-parser library normally attaches the command stack to its error.
/// `MessageInfo` prefers that stack over the type it receives.
/// Thus, `myapp info --help` and `myapp info --bogus` print the help for `info`
/// without help from us. A different path applies when the dispatched verb has
/// no further arguments. `CommandParser.parse` rewraps that failure as
/// `ParserError.noArguments`. The renderer ignores the stack for this error and
/// generates help for `type.asCommand`. Thus, `myapp info` with a missing
/// `<file>` would print the root usage under the verb error.
///
/// A launch site must not re-derive the verb from raw arguments. Raw arguments
/// cannot distinguish a claimed verb from a similar positional argument. The
/// claim therefore carries its attribution back out.
///
/// Deliberately not public: launch sites resolve it through
/// ``exitAttributingDispatchedSubcommand(_:dispatchedCommandType:root:)``, and
/// consumers neither construct nor catch it. `description` renders the fully
/// attributed message. A consumer can create a custom launch sequence and pass
/// this error directly to `exit(withError:)`. The result is readable, correctly
/// attributed output instead of a struct dump.
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
///   1. A `DispatchedSubcommandError` names its own verb — the verb's parse
///      failed, so no instance of it exists to inspect.
///   2. Otherwise, if a dispatched command was reached and ran, the failure is
///      the verb's and is rendered through the verb's dynamic type. This is
///      what attributes a `ValidationError` thrown from a dispatched `run()`,
///      which carries no command stack of its own.
///   3. Otherwise the failure is the root command's.
///
/// Some errors already carry a command stack. These include parse errors,
/// `--help`, and `--version`. The rendered type does not affect them because
/// `MessageInfo` prefers the stack on the error. `ExitCode` is also unchanged.
/// It maps to an exact status and has no usage text.
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
