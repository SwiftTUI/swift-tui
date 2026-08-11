# ``SwiftTUIArguments``

Parse SwiftTUI's standard runtime flags alongside an app's own command-line
surface.

## Overview

Use `SwiftTUIArguments` when a terminal app needs custom flags. The module also
provides the standard SwiftTUI runtime options for color, accessibility,
rendering mode, scene selection, and WebHost launch configuration.

Most apps get this module through `SwiftTUI` or `SwiftTUIWebHostCLI`. Import it
directly when composing a custom runner around `SwiftTUIRuntime` and
`SwiftTUICLI`.

## Subcommands under a positional root

A root command that declares an `@Argument` shadows its own subcommands.
swift-argument-parser parses the *current* command's arguments first. Then it
looks for a verb. Thus, a leading bare value binds to the root's positional
argument, and the parser does not descend. `myapp info x.gif` means "open the
file named `info`". The remaining `x.gif` value causes a parse failure.

Implement ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)`` to claim
the verb from the raw arguments first. One line covers the common case:

```swift
@main
struct MyApp: App, SwiftTUICommand {
  nonisolated static let configuration = CommandConfiguration(
    commandName: "myapp",
    subcommands: [CompletionsCommand.self, InfoCommand.self]
  )

  @OptionGroup(title: "SwiftTUI Options") var swiftTUIOptions: SwiftTUIOptions
  @Argument var path: String?

  var body: some Scene { WindowGroup { ContentView(path: path) } }

  nonisolated static func swiftTUIRootSubcommand(
    forRawArguments arguments: [String]
  ) throws -> (any ParsableCommand)? {
    try registeredSubcommand(forRawArguments: arguments)
  }
}
```

The default implementation returns `nil`, so an app that does not implement it
behaves exactly as before.

### It routes but does not register

``SwiftTUICommand/registeredSubcommand(forRawArguments:)`` reads the table you
already declared. `--help` and the generated completion scripts use
`configuration`. Keep each verb in its `subcommands` list. A dispatched but
unregistered verb works, but neither help surface shows it.

### A verb always beats a file of the same name

`myapp info` runs the `info` verb even when a file named `info` exists in the
working directory. The parser does not examine the file system. Thus, the
command has reproducible and testable behavior. `git`, `docker`, and `swift`
resolve the conflict in the same way. To specify this file, use one of these
forms:

- `myapp ./info`: a value containing a path separator can never equal a verb
  name.
- `myapp -- info`: a leading `-` disqualifies a match, so the value reaches the
  root command's positional past the argument terminator.

### What is not claimed

- **Anything but the first argument.** `myapp --json info x` is *not*
  intercepted. Interception is narrower than the parser's own descent. The
  parser binds root options across the complete argument list before it
  descends. A wider rule can rebind a shared option name.
- **`completions`.** The framework resolves it before the hook runs, so an
  implementation can neither shadow nor forget it.
- **`help`.** swift-argument-parser adds `help` to the command tree rather than
  to `configuration.subcommands`, so `myapp help info` still parses as "open the
  file named `help`". Use `myapp info --help` to print the verb's own help.

### Version reporting

A dispatched verb owns the whole parse, so its command stack has one element and
the root's version is neither reported nor inherited:

- `myapp ver --version` reports `ver`'s own `configuration.version`.
- `myapp info --version`, where `info` declares no version, fails with an
  unknown-flag error rather than falling back to the root's version.

Declare a `version` on each verb that supports `--version`. Raw-verb
interception causes this behavior. The hook does not cause it. `myapp
completions --version` has the same behavior.

## Topics

### App Commands

- ``SwiftTUICommand``
- ``SwiftTUIApp``
- ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)``
- ``SwiftTUICommand/registeredSubcommand(forRawArguments:)``

### Runtime Options

- ``SwiftTUIOptions``
- ``CompletionsCommand``
