# ``SwiftTUIArguments``

Parse SwiftTUI's standard runtime flags alongside an app's own command-line
surface.

## Overview

Use `SwiftTUIArguments` when a terminal app needs custom flags but still wants
the standard SwiftTUI runtime options for color, accessibility, rendering mode,
scene selection, and WebHost launch configuration.

Most apps get this module through `SwiftTUI` or `SwiftTUIWebHostCLI`. Import it
directly when composing a custom runner around `SwiftTUIRuntime` and
`SwiftTUICLI`.

## Subcommands under a positional root

A root command that declares an `@Argument` shadows its own subcommands.
swift-argument-parser parses the *current* command's arguments first and only
then looks for a verb, so a leading bare value binds to the root's positional
and the parser never descends — `myapp info x.gif` means "open the file named
`info`", and the leftover `x.gif` fails the parse.

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

### It routes; it does not register

``SwiftTUICommand/registeredSubcommand(forRawArguments:)`` reads the table you
already declared, and `--help` and the generated completion scripts are both
built from `configuration`. Keep the verbs listed in its `subcommands` — a verb
that is dispatched but not registered works, yet is invisible to both.

### A verb always beats a file of the same name

`myapp info` runs the `info` verb even when a file named `info` exists in the
working directory. No filesystem probe is performed: a command line whose
meaning depends on the contents of the current directory is neither
reproducible nor testable, and `git`, `docker`, and `swift` all resolve it the
same way. To name such a file, use either escape:

- `myapp ./info` — a value containing a path separator can never equal a verb
  name.
- `myapp -- info` — a leading `-` disqualifies a match, so the value reaches the
  root command's positional past the argument terminator.

### What is not claimed

- **Anything but the first argument.** `myapp --json info x` is *not*
  intercepted. Interception stays strictly narrower than the parser's own
  descent, which bounds the set of apps whose option binding could change — the
  parser binds the root's options greedily across the whole argument list before
  it descends, so a wider rule would rebind a shared option name.
- **`completions`.** The framework resolves it before the hook runs, so an
  implementation can neither shadow nor forget it.
- **`help`.** swift-argument-parser adds `help` to the command tree rather than
  to `configuration.subcommands`, so `myapp help info` still parses as "open the
  file named `help`". Use `myapp info --help`, which is fully supported and
  prints the verb's own help.

### Version reporting

A dispatched verb owns the whole parse, so its command stack has one element and
the root's version is neither reported nor inherited:

- `myapp ver --version` reports `ver`'s own `configuration.version`.
- `myapp info --version`, where `info` declares no version, fails with an
  unknown-flag error rather than falling back to the root's version.

Declare a `version` on any verb whose `--version` should work. This is a
property of raw-verb interception rather than of this hook — `myapp completions
--version` has always behaved the same way.

## Topics

### App Commands

- ``SwiftTUICommand``
- ``SwiftTUIApp``
- ``SwiftTUICommand/swiftTUIRootSubcommand(forRawArguments:)``
- ``SwiftTUICommand/registeredSubcommand(forRawArguments:)``

### Runtime Options

- ``SwiftTUIOptions``
- ``CompletionsCommand``
