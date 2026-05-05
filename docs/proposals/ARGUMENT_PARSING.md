# Argument Parsing

**Status:** Phases 1–5 implemented per
[`docs/plans/2026-05-04-002-argument-parsing-plan.md`](../plans/2026-05-04-002-argument-parsing-plan.md).
The `SwiftTUIArguments` peer package ships `SwiftTUIOptions` (power mode),
the `SwiftTUIApp` protocol (easy mode), and `CompletionsCommand` for
zsh/bash/fish completion script printing and installation. `RuntimeConfiguration`
lives in `SwiftTUI` core. Bare-mode apps honor framework env vars via the
default `App.main()` extension. Phase 6 (runner-internal-flag migration to
subcommands), Phase 7 (web subcommand wiring, blocked on `EMBEDDED_WEB_HOST.md`),
and the broader runtime-configuration → rendering wiring are tracked as
follow-up plans.

The remainder of this document captures the design space for how SwiftTUI
consumers declare their command line, which flags the framework reserves
for itself, and how flags interact with environment variables, runners,
and downstream proposals (accessibility, embedded web host). Long by
intent — argument parsing sits at the seam between consumer entry points
(decision 0008: runners own `App.main()`) and several cross-cutting
features (color, accessibility, motion, web-serve) that all want to ride
on the same flag surface.

**Owner:** unassigned. Tracking branch: `accessibility-investigation`.

---

## Table of contents

1. [Context](#context)
2. [Strategic shape](#strategic-shape)
3. [Principles](#principles)
4. [Landscape](#landscape)
   1. [swift-argument-parser today](#swift-argument-parser-today)
   2. [Cross-language peers](#cross-language-peers)
   3. [Plugin/extension flag namespaces](#pluginextension-flag-namespaces)
   4. [Help-output conventions](#help-output-conventions)
5. [API options considered](#api-options-considered)
   1. [Option A: bare swift-argument-parser, framework documents conventions](#option-a-bare-swift-argument-parser-framework-documents-conventions)
   2. [Option B: framework provides an `OptionGroup` of standard flags](#option-b-framework-provides-an-optiongroup-of-standard-flags)
   3. [Option C: framework provides a `SwiftTUIApp` protocol that wraps `AsyncParsableCommand`](#option-c-framework-provides-a-swifttuiapp-protocol-that-wraps-asyncparsablecommand)
   4. [Option D: hand-rolled framework parser, no swift-argument-parser dependency](#option-d-hand-rolled-framework-parser-no-swift-argument-parser-dependency)
   5. [Option E: macro-based `@SwiftTUIMain` derivation](#option-e-macro-based-swifttuimain-derivation)
6. [Proposed design](#proposed-design)
   1. [Where argument parsing lives](#where-argument-parsing-lives)
   2. [The consumer-facing API](#the-consumer-facing-api)
   3. [`SwiftTUIOptions`: the framework option group](#swifttuioptions-the-framework-option-group)
   4. [Subcommand model](#subcommand-model)
   5. [Help formatting and discoverability](#help-formatting-and-discoverability)
   6. [Validation timing](#validation-timing)
7. [Standard flags (table)](#standard-flags-table)
8. [Env-var ↔ flag mapping (table)](#env-var--flag-mapping-table)
9. [Precedence rules](#precedence-rules)
10. [Reserved namespace and collision policy](#reserved-namespace-and-collision-policy)
11. [Completions, `--help`, `--version`](#completions---help---version)
12. [Logging, verbosity, quiet, debug](#logging-verbosity-quiet-debug)
13. [Pass-through args and `--`](#pass-through-args-and---)
14. [Interaction with decision 0008 (runners own main)](#interaction-with-decision-0008-runners-own-main)
15. [Interaction with decision 0003 (action scopes)](#interaction-with-decision-0003-action-scopes)
16. [Interaction with the embedded web host](#interaction-with-the-embedded-web-host)
17. [Open questions](#open-questions)
18. [Out of scope](#out-of-scope)
19. [Suggested phasing](#suggested-phasing)
20. [Sources](#sources)
21. [Changelog](#changelog)

---

## Context

Per [ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md),
SwiftTUI is **library-only**. Executable launch is owned by peer runner
packages (`SwiftTUICLI`, `SwiftTUIWASI`, `GUI/SwiftUIHost`, `GUI/WebHost`).
Consumers writing terminal-native apps `import SwiftTUI` plus `import
SwiftTUICLI`, declare an `@main struct MyApp: App`, and the runner walks
their scene body and runs the result.

That settled the *launch* question. It did not settle the *argument parsing*
question. Today, `Platforms/CLI/Sources/SwiftTUICLI/CLIMode.swift` parses a
small fixed set of runner-internal flags (`--instances`, `--scenes`,
`--attach`, `--pid`, `--instance`) by hand-rolled `while index < args.count`
state machine. Anything else gets dropped silently. Consumers who want their
own flags either:

- depend on `swift-argument-parser` separately and write a parallel `@main`
  that does its own parsing before handing off to `TerminalRunner.run(...)`;
- or write nothing and hope users pass no flags at all (the
  `Examples/gallery` and `Examples/minimal` story today — `GalleryDemoApp`
  literally just declares `@main struct GalleryDemoApp: App` with no parser
  in sight, and the `Examples/minimal` target just calls `print(output)`
  with no scene runtime at all).

Two problems compound from this:

1. **No standard flags.** Every SwiftTUI app makes its own decisions about
   `--accessible`, `--ascii`, `--no-color`, `--reduce-motion`, `--web`,
   `--json`, `--quiet`, `--debug`, `-v`, `--port`. The accessibility
   proposal at [`ACCESSIBILITY.md`](./ACCESSIBILITY.md#environment-contract)
   already specifies an env-var contract (`NO_COLOR`, `FORCE_COLOR`,
   `CLICOLOR`, `COLORTERM`, `TERM=dumb`, `LANG=C`, `CI`,
   `SWIFTTUI_ACCESSIBLE`, `SWIFTTUI_ASCII`, `SWIFTTUI_REDUCE_MOTION`) and
   suggests the matching CLI flags `--accessible`, `--ascii`, `--no-color`,
   `--no-progress`, `--plain`, `--linear`, `--json`. The forthcoming
   embedded-web-host proposal will add `--web`, `--port`, `--bind`,
   `--no-open`, etc. None of those show up consistently across consumers
   today because nothing arranges for them.

2. **No standard parser.** Consumers reach for `swift-argument-parser` on
   their own, get inconsistent UX (different help formatting, different
   subcommand layouts, no shell completion in some, completion in others),
   and miss the framework's flags entirely. Help output reads "this is a
   SwiftTUI app" in one app and "this is a generic Swift CLI" in the next.

The bet of this proposal: a thin framework-supplied layer over
`swift-argument-parser` gives every SwiftTUI app the same standard flags
for free, lets consumers add their own without conflict, validates before
any TUI escape sequence touches the terminal, and stays out of the way of
consumers who want full ParsableCommand control.

This document does not try to ship code. It tries to fix the shape so that
when implementation lands, accessibility, web-serve, theming, and runner
diagnostics all pull from the same surface.

> **Cross-references.**
>
> - [ACCESSIBILITY.md](./ACCESSIBILITY.md) — env-var contract; this
>   proposal must stay consistent with it.
> - `EMBEDDED_WEB_HOST.md` — TODO: cross-reference once it lands. Today the
>   parallel investigation has not produced a doc; this proposal reasons
>   from first principles for the web-related flags and notes where the
>   embedded-host proposal can override.
> - [ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md)
>   — runners own `main()`. Argument parsing must live where `main()` lives.
> - [ADR-0003](../decisions/0003-action-scopes-not-global-hotkeys.md) —
>   action scopes; some flags (`--start-in <scope-id>`) want to seed scopes.

## Strategic shape

The argument parsing story is **three layers**, each owned by a different
seam:

| Layer | Owner | Responsibility |
|---|---|---|
| **Foundational parser** | `swift-argument-parser` (Apple) | `@Option`, `@Flag`, `@Argument`, `@OptionGroup`, `ParsableCommand`, `AsyncParsableCommand`, completion script generation, help text. We do not re-implement these. |
| **Framework standard flags** | A new optional library `SwiftTUIArguments` (peer to `SwiftTUICLI`) | Defines `SwiftTUIOptions: ParsableArguments`, the env-var bridge, the `--accessible` / `--ascii` / `--no-color` etc. flags, and the resulting `RuntimeConfiguration` value the runner consumes. |
| **Per-runner integration** | `SwiftTUICLI` / `SwiftTUIWASI` / future runners | Runners construct the parser, parse `CommandLine.arguments`, fail before any TTY escape sequence, and feed the parsed `RuntimeConfiguration` into their existing launch flow (`TerminalRunner.run(_:)`). |

The framework standard flags layer is **opt-in but first-party**. Consumers
who don't want it can keep their hand-rolled `static func main()` and call
`TerminalRunner.run(MyApp.self)` directly with no parsing. Consumers who
do want it write `@main struct MyApp: SwiftTUIApp { ... }`, and a default
`main()` parses the arguments, applies the runtime configuration, and then
runs the app. That `SwiftTUIApp` protocol is what this proposal calls the
"recommended-but-optional helper" — recommended because it gives you the
standard flags, optional because library-only / runners-own-main means we
*can't* take it from you.

This proposal focuses on the framework standard flags layer and the API
shape for consumer integration. Per-runner specifics (where the parser
runs, what runner-internal flags exist) are sketched but mostly inherit
from the existing CLIMode shape.

## Principles

1. **Library-only stays library-only.** No argument parsing code in
   `SwiftTUI`, `SwiftTUIViews`, or `SwiftTUICore`. The parser library is a peer of the
   runner libraries, optionally consumed alongside them. Decision 0008
   is not relaxed.
2. **Reuse `swift-argument-parser`.** It's Apple's, it's stable, it ships
   with completion-script generation and async support, it's already in
   the Swift CLI ecosystem. Don't reinvent the parser; reinvent only the
   *defaults* and *standard flags* layered on top.
3. **Fail before the TTY enters raw mode.** Argument parsing happens
   *before* alternate-screen acquisition, raw-mode setup, or signal
   handler installation. Bad flags print to stderr in cooked mode, with
   no escape sequences, no alt-screen entry, no terminal corruption.
4. **CLI > env > defaults.** Flags override env vars override built-in
   defaults. There is one precedence chain and it's documented in one
   place. (See [Precedence rules](#precedence-rules).)
5. **Framework flags are namespaced and discoverable.** The
   accessibility / web / logging / version flags ride under a
   framework-owned subset. They appear in `--help` under their own
   section so consumers who add their own flags don't have to wonder
   what's theirs and what's ours.
6. **Consumer flags own a separate namespace.** Apps add flags via their
   own `@Option`/`@Flag` declarations. Conflicts on names with framework
   flags are a build-time or parse-time error, never silent override.
7. **Env vars and CLI flags are equally first-class.** Every framework
   flag has an env var. Every env var has a flag. The accessibility
   proposal's contract is the source of truth for which env vars exist;
   this proposal mirrors them as flags.
8. **Reasonable defaults that don't surprise.** Auto-detect TTY for
   color and motion (the GitHub CLI lesson). Default to interactive
   mode. Default to ANSI 4-bit color. Default to `--accessible=auto`
   (which means: derived from env vars, falling back to interactive).
9. **One declarative shape, one help screen.** A single `--help`
   surfaces every flag a user could pass. There is no "hidden help".
   `--help-all` exists for verbose help with extended descriptions and
   examples; `--help` is the canonical entry.
10. **Validation is decoupled from execution.** Parsing produces a
    typed `RuntimeConfiguration` value. The runner consumes it. The
    accessibility configuration, web-serve configuration, and logging
    configuration are independent fields on it; they do not couple.

---

## Landscape

This section captures what the major argument parsing libraries and
ecosystems do, with concrete API where it informs the proposal. The goal
is not exhaustiveness — it's to surface the patterns we want to adopt and
the patterns we want to avoid.

### swift-argument-parser today

Apple's `swift-argument-parser` is the de-facto standard for Swift CLIs.
It's used by `swiftc`, `swift-format`, `swift-build`, every Swift Package
Manager subcommand, and the entire `swift` toolchain itself. Highlights
relevant to this proposal, drawn from the
[CHANGELOG](https://github.com/apple/swift-argument-parser/blob/main/CHANGELOG.md)
and [docs](https://apple.github.io/swift-argument-parser/documentation/argumentparser/):

- **`ParsableCommand` / `AsyncParsableCommand`.** The base protocols.
  `AsyncParsableCommand` (added in 1.1.0) supports `async` `run()`
  methods. SwiftTUI is async-by-construction (the run loop, the
  per-scene tasks); we'd default to async.
- **`@Option`, `@Flag`, `@Argument`.** Property wrappers that declare
  parsed values. Conditionally `Sendable` since 1.3.0 — important for
  Swift 6 strict concurrency (which SwiftTUI runs under).
- **`@OptionGroup`.** Declares a reusable bundle of options. The
  consuming command flattens the group's properties into its own
  surface. **This is the mechanism that makes "framework-owned
  standard flags" tractable.** Titled option groups (1.2.0) get their
  own help-screen heading.
- **`@ParentCommand`** (1.7.0). Lets a subcommand reach into its
  ancestor's parsed state. Useful if we expose persistent flags via
  subcommand structures.
- **Subcommand grouping** (1.5.0). Subcommands can be grouped into
  named sections in `--help` output. Useful for "framework subcommands"
  like `myapp scenes list`, `myapp web`, `myapp completions install`.
- **`CommandConfiguration`.** Configures help text, subcommands,
  visibility (e.g., `--help-all`-only), command name, abstract,
  discussion. Has the result-builder initializer (1.5.0+) that mixes
  subcommands and groups.
- **Completion script generation.** Built-in zsh, bash, fish via
  `myapp --generate-completion-script <shell>`. Customizable per-arg
  via `.completion(...)` modifiers; default kind for
  `ExpressibleByArgument` types via `defaultCompletionKind`.
- **Async / Sendable / Swift 6 readiness.** Recent releases have
  hardened Sendable conformance, fixed completion script generation
  bugs, improved error messaging on single-dash options.
- **No native env-var support.** This is the surface gap that hurts
  most for our use case. swift-argument-parser does not have a
  `@Option(envVar: "SWIFTTUI_PORT")` shorthand the way Click has
  `auto_envvar_prefix`. There is a long-standing community pattern
  (read env vars in `init()` or `validate()` and stuff them into
  defaults) but it's not first-class. **We will need to build the
  env-var bridge ourselves**, layered onto whatever the user
  declares.

### Cross-language peers

Patterns worth stealing or rejecting from outside the Swift world.

**Python `click`** ([docs](https://click.palletsprojects.com/)).
- `auto_envvar_prefix` on the group lets every option auto-derive an env
  var name. `@click.group(context_settings={"auto_envvar_prefix": "SWIFTTUI"})`
  means `--port` becomes readable as `SWIFTTUI_PORT`. **This is exactly
  the ergonomic we want; swift-argument-parser doesn't have it.** We can
  reproduce the behavior with an `OptionGroup` plus an env-var binding
  table.
- **Precedence is documented and unambiguous:** prompt > command line >
  env > default-map > default. We adopt the same precedence with
  prompts removed (TUI doesn't use stdin prompts during parsing) and
  with the framework's own defaults at the bottom.

**Go `cobra`** ([docs](https://cobra.dev/)).
- **Persistent flags** vs **local flags.** A persistent flag declared
  on a parent command is automatically inherited by every subcommand.
  This is exactly the "framework-owned global flags" pattern: declare
  `--accessible` once on the root, every subcommand sees it.
- **Plugin model.** Cobra's plugin story is loose (kubectl-style
  external binaries). The lesson for us: **flag-ordering matters when
  the parser doesn't know which arg is the subcommand.** kubectl
  fails on `kubectl -n ns my-plugin` because `-n` is consumed before
  the plugin name is recognized. We avoid this by doing all parsing
  in-process (no external plugin model) and following GNU-getopt-long
  defaults (flags can appear anywhere except after `--`).

**Rust `clap`** (derive API,
[docs](https://docs.rs/clap/latest/clap/_derive/index.html)).
- **`#[command(flatten)]`** is the equivalent of swift-argument-parser's
  `@OptionGroup`. Same idea: declare a reusable Args struct, flatten
  it into multiple top-level commands.
- **`#[arg(global = true)]`** marks a flag as available on every
  subcommand. Same role as cobra's persistent flags.
- **`#[arg(env = "MYAPP_PORT")]`** is the env-var binding clap
  inherits from the underlying parser. First-class, works with
  derive. **The pattern we want.**
- The "long help by default" vs "short help by default" debate has
  been settled in clap by `--help` (short) and `-h` (also short, with
  `--long-help` removed in favor of richer `--help` rendering).

**Node `commander`**.
- Default behavior: program options recognized **before and after**
  subcommands. `enablePositionalOptions()` restricts to before-only.
  We want the GNU default: anywhere is fine, `--` terminates.
- `--` to terminate option parsing is universally supported.

**AWS CLI v2.**
- Help output is sectioned: SYNOPSIS, DESCRIPTION, OPTIONS, GLOBAL
  OPTIONS, EXAMPLES. **The "GLOBAL OPTIONS" section is what we want
  for framework-owned flags.** swift-argument-parser titled option
  groups give us this for free if we name the group well.
- `aws help topics` lists framework topics separately. We don't need
  this depth, but it's useful to know it exists if a `--help-all`
  flag is later expanded into a `myapp help <topic>` mechanism.

### Plugin/extension flag namespaces

The "how do framework flags coexist with consumer flags?" question has
been faced by every plugin-supporting CLI tool. Patterns we considered:

- **Reserved prefix** (kubernetes uses `kube-` for system namespaces;
  conventional, weakly enforced). We could reserve `--swifttui-*` for
  framework flags, but the result is verbose and unfamiliar
  (`--swifttui-no-color` reads worse than `--no-color`). Rejected.
- **Separator namespace** (cargo's `+toolchain` syntax,
  `cargo +nightly build`). Argument-position-based. Doesn't fit our
  case — we don't have toolchains, just flags.
- **Implicit reservation by ownership** (Cobra persistent flags). The
  framework declares its flags first, on the root command; the
  consumer's subcommands inherit them. Conflict on names is detected
  at registration time. **This is what we adopt.**
- **Hard collision = compile-time error.** Because our framework flags
  live in a Swift `OptionGroup`, redeclaring a flag with the same
  long name in the consumer's `ParsableCommand` is a runtime
  registration error from swift-argument-parser. We surface this as
  a clear error message early in startup.

### Help-output conventions

POSIX (12. Utility Conventions) and the GNU Coding Standards specify:

- `--help` and `--version` are **mandatory** for every well-behaved
  program. They print to stdout and exit successfully.
- Options are listed alphabetically unless that hurts readability.
- `--` terminates option parsing.
- GNU getopt-long permits options anywhere among the arguments, not
  just before positional args. **POSIX-strict mode forbids this.** We
  want GNU.

For sectioned help output (AWS CLI, kubectl, gh):

- Group `GLOBAL OPTIONS` separately from per-subcommand options.
- Group framework subcommands separately from app subcommands.
- Use `--help-all` / `-h` for verbose help; reserve `--help` for the
  one-page summary if the verbose form gets long.

---

## API options considered

This section walks through five candidate API shapes for how a consumer
declares their CLI surface. The proposed design (next section) picks
**Option B + Option C combined** — `OptionGroup` for the framework
flags, optional protocol wrapper for the entry point, with macro derivation
(Option E) deferred.

### Option A: bare swift-argument-parser, framework documents conventions

**Shape.** SwiftTUI ships no parser. Consumers write their own
`AsyncParsableCommand` and call `TerminalRunner.run(...)`. A doc page
lists the recommended flag names and env vars, but the framework doesn't
enforce them.

```swift
@main
struct MyApp: AsyncParsableCommand, App {
  @Flag(name: .long, help: "Run in accessible mode")
  var accessible: Bool = false

  @Flag(name: .long, help: "Use ASCII glyphs only")
  var ascii: Bool = false

  // ... 10 more standard flags hand-written ...

  @Option(help: "Port for embedded web host")
  var port: Int = 8080

  func run() async throws {
    // Apply env vars manually
    let accessible = self.accessible || ProcessInfo.processInfo.environment["SWIFTTUI_ACCESSIBLE"] != nil
    // ... apply each flag manually ...
    try await TerminalRunner.run(self)
  }

  var body: some Scene { /* ... */ }
}
```

**Pros.**
- Zero new framework code.
- Consumers retain full control.
- Doesn't add a dependency to root SwiftTUI.

**Cons.**
- The whole point of the proposal — standard flags everywhere — is
  abandoned. Every consumer reinvents `--accessible`, mostly wrong.
- Env-var precedence rules become per-app, not framework-wide.
- The accessibility proposal's env-var contract has no enforcement
  hook. Authors will skip it.
- Discoverability for accessibility flags (called out as a
  requirement in `ACCESSIBILITY.md`) requires manual `--help`
  curation.

**Verdict.** This is the status quo and it's why the proposal exists.
Rejected.

### Option B: framework provides an `OptionGroup` of standard flags

**Shape.** SwiftTUIArguments ships a `SwiftTUIOptions: ParsableArguments`
struct that bundles every framework-reserved flag. Consumers `@OptionGroup`
it into their command.

```swift
@main
struct MyApp: AsyncParsableCommand, App {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Option(help: "How many widgets to show")
  var widgets: Int = 10

  func run() async throws {
    let configuration = swiftTUIOptions.runtimeConfiguration()
    try await TerminalRunner.run(self, configuration: configuration)
  }

  var body: some Scene { /* ... */ }
}
```

**Pros.**
- Single import gives every consumer the standard flags.
- Help screen automatically gets a "SwiftTUI Options" section
  (titled OptionGroup feature, 1.2.0+).
- Consumer's flags live alongside; no risk of stepping on each
  other beyond name collisions (which surface as parser errors).
- The `runtimeConfiguration()` method provides a typed handoff: env
  vars are merged in at that point, with documented precedence.
- Works equally well with `ParsableCommand` and
  `AsyncParsableCommand`.
- Consumer keeps `@main` ownership: matches the spirit of decision
  0008 (we don't take main from them).

**Cons.**
- The consumer still has to remember to add `@OptionGroup
  SwiftTUIOptions` and to call `.runtimeConfiguration()`. Forgetting
  silently disables every framework flag.
- Doesn't help consumers who have no parser today; they still have to
  write the boilerplate.

**Verdict.** This is the right primitive and is part of the proposed
design. The "consumer might forget" objection is mitigated by Option C
(below), which wraps this into a protocol the consumer can opt into.

### Option C: framework provides a `SwiftTUIApp` protocol that wraps `AsyncParsableCommand`

**Shape.** A protocol with a default `static main()` that does the
right thing. Consumers conform their `App` to it.

```swift
@main
struct MyApp: SwiftTUIApp {
  // Your own flags:
  @Option(help: "How many widgets to show")
  var widgets: Int = 10

  var body: some Scene {
    WindowGroup {
      ContentView(widgets: widgets)
    }
  }
}
```

`SwiftTUIApp` (in `SwiftTUIArguments`):

```swift
public protocol SwiftTUIApp: App, AsyncParsableCommand {
  /// Inherited from ParsableArguments — implementations declare their own
  /// flags as @Option / @Flag / @Argument here.

  /// Default-provided. Override to customize the runtime configuration
  /// (e.g. force accessibility on regardless of flags).
  func runtimeConfiguration() -> RuntimeConfiguration
}

extension SwiftTUIApp {
  public func runtimeConfiguration() -> RuntimeConfiguration {
    swiftTUIOptions.runtimeConfiguration(environment: ProcessInfo.processInfo.environment)
  }

  public func run() async throws {
    let configuration = runtimeConfiguration()
    try await TerminalRunner.run(self, configuration: configuration)
  }

  public static func main() async {
    // Standard ParsableCommand main() flow with our own pre-validation,
    // help-rendering, and exit-on-error handling.
    await self._main(arguments: nil)
  }
}
```

The protocol synthesizes the `@OptionGroup SwiftTUIOptions` via its
own embedded property, which Swift-argument-parser flattens correctly
when the conforming type is itself a `ParsableArguments`/`ParsableCommand`.

(Implementation detail: because we can't add stored properties through a
protocol extension, the actual bundling is via a base struct or via a
macro. The exact mechanism is an implementation choice; the proposal is
a declaration that `SwiftTUIApp` exists and behaves this way.)

**Pros.**
- One-line opt-in. The consumer writes nothing about argument parsing
  at all unless they have their own flags.
- Default `runtimeConfiguration()` does the right thing; override
  available for advanced cases.
- Default `main()` ensures parse-then-validate-then-launch order is
  always honored.
- Discoverable: `--help` is automatic; standard flags appear; if the
  consumer adds an `@Option`, it joins the same parser.

**Cons.**
- Protocol composition (`App` × `AsyncParsableCommand`) is fiddly
  given `App` already has a default `main()`. We have to make sure
  `SwiftTUIApp.main()` wins the dispatch; this is a known Swift
  ambiguity. Solution: `App` itself does **not** define `main()`
  today (per decision 0008, runners do); `SwiftTUIApp` then provides
  it cleanly.
- The mechanism for getting `SwiftTUIOptions` flags into the parser
  without the consumer typing `@OptionGroup` requires either a base
  struct or a macro. Either is doable but adds complexity.

**Verdict.** This is the right ergonomic for new apps. Combined with
Option B (which remains available for consumers who need finer control)
this gives the proposal both an "easy mode" and a "power mode."

### Option D: hand-rolled framework parser, no swift-argument-parser dependency

**Shape.** Extend the existing `CLIMode.parse(_:)` state machine into a
full parser. No swift-argument-parser dependency.

**Pros.**
- Zero new external dependency. SwiftTUICLI today depends only on
  `SwiftTUI` and `UnixSignals`; this stays small.
- Foundation-free in principle (the existing parser is already
  Foundation-free per the no-foundation-in-library-products hook).
- Total control over help formatting, completion scripts.

**Cons.**
- Reinventing the wheel. swift-argument-parser is mature, async-aware,
  Sendable-aware, has shipped completion scripts for years.
- We'd have to build help formatting, validation, completion
  generation, env-var binding, type coercion, error messages — every
  one of which has been done well in swift-argument-parser.
- Consumers who already know swift-argument-parser would have to
  learn our DSL.
- Not a credible engineering plan.

**Verdict.** Rejected. The dependency cost of swift-argument-parser is
acceptable for a runner library (which is already a peer package, not
the foundation-free `SwiftTUICore` / `SwiftTUIViews` / `SwiftTUI` layer). The Foundation
constraint applies to library products, not to runner products.

### Option E: macro-based `@SwiftTUIMain` derivation

**Shape.** A Swift macro generates the parser and the entry point from
a tagged App.

```swift
@SwiftTUIMain
struct MyApp: App {
  @Argument var widgets: Int = 10
  @Flag var verbose: Bool = false

  var body: some Scene { /* ... */ }
}
```

The macro expansion injects:

- `@OptionGroup var _swiftTUIOptions: SwiftTUIOptions`
- conformance to `AsyncParsableCommand`
- `static func main() async` that parses arguments, builds the runtime
  configuration, and runs.
- `@main` attribute application.

**Pros.**
- Tightest possible syntax: the consumer's App declaration looks like
  plain SwiftUI, with parser-decorated properties.
- Zero protocol-composition fiddliness; the macro just emits the
  protocol conformance.
- Could auto-link `@Option` env-var prefixes from `App` type name
  (e.g., `MyApp` → `MY_APP_PORT` for `--port`), the way Click's
  `auto_envvar_prefix` works.

**Cons.**
- Macros are an additional learning curve. Build-time macro
  expansion means slower clean builds and worse debugging.
- The macro has to coexist with swift-argument-parser's existing
  property wrappers; they're not declarative macros, so the macro
  has to be careful not to clobber them.
- Adds an `swift-syntax` dependency to anyone using the macro
  (large transitive cost).
- Consumer can't easily customize the generated `main()` — the
  escape hatch is "drop the macro, write the protocol conformance
  by hand."

**Verdict.** **Deferred, not rejected.** The protocol approach
(Option C) gets us 90% of the ergonomic benefit with none of the
macro tax. If after a few months of real consumer use, the
boilerplate of "import SwiftTUIArguments, conform to SwiftTUIApp"
turns out to chafe, a macro can be added on top without breaking the
protocol. Macro-now is premature.

---

## Proposed design

The recommended path: **Option B (the OptionGroup) is always available;
Option C (the SwiftTUIApp protocol) is the recommended path for new
apps.** Both live in a new optional library `SwiftTUIArguments`, peer
to `SwiftTUICLI`. Consumers who want full control over parsing skip
the protocol and use the OptionGroup directly. Consumers who want
zero ceremony conform to the protocol.

### Where argument parsing lives

```
swift-tui/
├── Sources/
│   ├── Core/                       # foundation-free, no parser
│   ├── View/                       # foundation-free, no parser
│   └── SwiftTUI/                   # foundation-free, no parser
├── Platforms/
│   ├── CLI/
│   │   └── Sources/
│   │       └── SwiftTUICLI/        # existing terminal runner
│   ├── WASI/
│   │   └── Sources/
│   │       └── SwiftTUIWASI/       # existing WASI runner
│   └── Arguments/                  # NEW
│       └── Sources/
│           └── SwiftTUIArguments/  # NEW: parser wrapper
└── ...
```

`SwiftTUIArguments` depends on `SwiftTUI` and on
`https://github.com/apple/swift-argument-parser` (`>= 1.5.0` for titled
option groups + subcommand grouping; `>= 1.6.0` for completion shell
detection; `>= 1.7.0` for `@ParentCommand` if needed).

`SwiftTUIArguments` does **not** depend on `SwiftTUICLI`. The runtime
configuration handoff is via a typed value (`RuntimeConfiguration`)
defined in `SwiftTUI` itself (or in a shared support target). This
keeps `SwiftTUIArguments` usable from `SwiftTUIWASI`, future runners,
and embedded hosts that want to honor the same flag surface.

The runner libraries gain a single new entry point:

```swift
// In SwiftTUICLI:
public extension TerminalRunner {
  @MainActor
  static func run<A: App>(
    _ app: A,
    configuration: RuntimeConfiguration
  ) async throws { /* ... */ }
}
```

The existing `TerminalRunner.run(_:)` calls into this with
`RuntimeConfiguration.default` for backward compatibility.

### The consumer-facing API

#### Easy mode (recommended for new apps)

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
struct MyApp: SwiftTUIApp {
  @Option(help: "How many widgets to show")
  var widgets: Int = 10

  @Flag(help: "Show widget IDs alongside their labels")
  var showIds: Bool = false

  var body: some Scene {
    WindowGroup {
      ContentView(widgets: widgets, showIds: showIds)
    }
  }
}
```

What happens at startup:

1. `SwiftTUIApp.main()` runs (default-provided by the protocol).
2. `CommandLine.arguments` is parsed against `MyApp`'s declared
   flags **plus the `SwiftTUIOptions` group flattened in by the
   protocol**.
3. Bad flags / unknown flags / `--help` / `--version` exit with a
   stderr error or stdout help text *before any TUI escape sequence
   is written*.
4. Env vars are merged into the parsed config per the precedence
   rules.
5. The resulting `RuntimeConfiguration` is handed to
   `TerminalRunner.run(self, configuration:)`.
6. The runner sets up the terminal, alternate screen, raw mode, signal
   handlers, and the run loop.

#### Power mode (full control)

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments
import ArgumentParser

@main
struct MyApp: AsyncParsableCommand, App {
  static let configuration = CommandConfiguration(
    commandName: "myapp",
    abstract: "Does the thing.",
    subcommands: [Run.self, Doctor.self],
    defaultSubcommand: Run.self
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  // ... per-subcommand parsing ...

  func run() async throws {
    let configuration = swiftTUIOptions.runtimeConfiguration()
    try await TerminalRunner.run(MyApp.self, configuration: configuration)
  }

  var body: some Scene {
    WindowGroup { /* ... */ }
  }
}
```

This shape is equivalent in behavior; it just doesn't use the
protocol convenience.

#### Bare mode (no SwiftTUIArguments)

```swift
import SwiftTUI
import SwiftTUICLI

@main
struct MyApp: App {
  var body: some Scene { /* ... */ }
}
```

This still works exactly as it does today. `SwiftTUICLI` ships an
internal default `App.main()` that calls `TerminalRunner.run` with a
default-derived `RuntimeConfiguration` (env-var-only, no CLI flag
parsing). Bare mode loses the framework flags but pays no
swift-argument-parser tax. This is what existing examples like
`Examples/gallery/GalleryDemoApp` would do until they migrate.

### `SwiftTUIOptions`: the framework option group

```swift
public struct SwiftTUIOptions: ParsableArguments, Sendable {
  // ─── Color and appearance ─────────────────────────────────────

  @Flag(
    name: .customLong("no-color"),
    help: "Disable color output. Equivalent to NO_COLOR=1."
  )
  public var noColor: Bool = false

  @Flag(
    name: .customLong("force-color"),
    help: "Force color output even when stdout is not a TTY."
  )
  public var forceColor: Bool = false

  // ─── Accessibility ────────────────────────────────────────────

  @Flag(
    name: .customLong("accessible"),
    help: "Accessible mode: drop the TUI for a linear, append-only render."
  )
  public var accessible: Bool = false

  @Flag(
    name: .customLong("ascii"),
    help: "ASCII-only mode: no Unicode glyphs, box drawing, or emoji."
  )
  public var ascii: Bool = false

  @Flag(
    name: .customLong("reduce-motion"),
    help: "Suppress animations and spinners."
  )
  public var reduceMotion: Bool = false

  @Flag(
    name: .customLong("no-progress"),
    help: "Replace progress bars with static status messages."
  )
  public var noProgress: Bool = false

  @Flag(
    name: .customLong("plain"),
    help: "Plain text only: implies --no-color, --ascii, --reduce-motion."
  )
  public var plain: Bool = false

  @Flag(
    name: .customLong("linear"),
    help: "Linearize HStack-side-by-side layouts top-to-bottom."
  )
  public var linear: Bool = false

  // ─── Output mode ──────────────────────────────────────────────

  @Flag(
    name: .customLong("json"),
    help: "Output JSON instead of rendering a TUI (where supported)."
  )
  public var json: Bool = false

  // ─── Web-host (sketched; refine once EMBEDDED_WEB_HOST.md lands) ─

  @Flag(
    name: .customLong("web"),
    help: "Serve the app over HTTP instead of a local terminal."
  )
  public var web: Bool = false

  @Option(
    name: .customLong("port"),
    help: "Port for --web. Default: 0 (auto-assign)."
  )
  public var port: Int = 0

  @Option(
    name: .customLong("bind"),
    help: "Address for --web. Default: 127.0.0.1."
  )
  public var bind: String = "127.0.0.1"

  @Flag(
    name: .customLong("no-open"),
    help: "Don't auto-open the browser when serving with --web."
  )
  public var noOpen: Bool = false

  // ─── Logging / diagnostics ────────────────────────────────────

  @Flag(
    name: .shortAndLong,
    help: "Verbose logging. Use -vv for debug-level output."
  )
  public var verbose: Int = 0   // -v, -vv, -vvv

  @Flag(
    name: .customLong("quiet"),
    help: "Suppress non-error log output."
  )
  public var quiet: Bool = false

  @Flag(
    name: .customLong("debug"),
    help: "Enable framework-internal debug instrumentation."
  )
  public var debug: Bool = false

  // ─── Action scopes (decision 0003) ────────────────────────────

  @Option(
    name: .customLong("start-in"),
    help: "Open with the action scope <id> already active."
  )
  public var startIn: String?

  // ─── Resolution ───────────────────────────────────────────────

  public init() {}

  public func runtimeConfiguration(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isStdoutTTY: Bool = isatty(STDOUT_FILENO) != 0
  ) -> RuntimeConfiguration {
    // Apply precedence: CLI flags > env vars > defaults.
    // See "Env-var ↔ flag mapping" and "Precedence rules" sections.
  }
}
```

Notes:

- The titled `@OptionGroup(title: "SwiftTUI Options")` produces a
  separate "SWIFTTUI OPTIONS" heading in `--help`, à la AWS CLI's
  GLOBAL OPTIONS section.
- `--plain` is an "implies" flag: it sets `noColor = true`, `ascii =
  true`, `reduceMotion = true`. The implication is resolved during
  `runtimeConfiguration()`, not via property mutation; this keeps
  `SwiftTUIOptions` decoded values pure.
- `verbose` uses swift-argument-parser's `@Flag(name: .shortAndLong)`
  with repeat-counting (the standard `-v -v -v` → 3 idiom).
- `--debug` is intentionally separate from `--verbose -vvv`: debug
  enables framework-internal instrumentation (timing, frame stats,
  state-machine traces) regardless of log verbosity.

### Subcommand model

The framework exposes runner-internal behaviors as **flags, not
subcommands**, with one exception. The exception is `myapp web`,
which we lean toward exposing as a subcommand because it switches
the entire runtime mode.

The decision is laid out per-feature:

| Feature | Subcommand or flag? | Rationale |
|---|---|---|
| `--accessible` | Flag | Same app, render strategy switch. |
| `--ascii` | Flag | Same app, glyph table switch. |
| `--no-color` | Flag | Standard convention. |
| `--web` / `myapp web` | **Either, leaning subcommand** | Mode switch with its own options (`--port`, `--bind`, `--no-open`). Subcommand groups them; flag flattens them into the same `--help`. See open question. |
| `myapp scenes list` | Subcommand | Runner-internal; sibling of `--instances` from the existing CLIMode. |
| `myapp completions install` | Subcommand | Per swift-argument-parser convention. |
| `myapp doctor` | Subcommand | Diagnostic dump; sibling of `--debug`. |

The existing `--instances`, `--scenes`, `--attach`, `--pid`,
`--instance` flags from `CLIMode.parse(_:)` are **runner-private**
and continue to work unchanged. They predate this proposal and serve
attach/list flows that consumers never invoke directly. Migrating
them to subcommands (`myapp instances`, `myapp scenes`, `myapp
attach <id>`) is a follow-up cleanup; not load-bearing here.

For the web mode specifically:

```text
# Flag form (also valid):
myapp --web --port 8080 --bind 0.0.0.0

# Subcommand form (recommended):
myapp web --port 8080 --bind 0.0.0.0
```

Both shapes resolve to the same `RuntimeConfiguration`. The lean is
**recommend the subcommand form, accept both**. This matches
`textual serve` (Textual) and `python -m http.server` conventions.
See [Open questions](#open-questions) for the discussion.

### Help formatting and discoverability

The help output reads like:

```text
USAGE: myapp [<options>] [<widgets>]

ARGUMENTS:
  <widgets>               How many widgets to show. (default: 10)

OPTIONS:
  --show-ids              Show widget IDs alongside their labels.
  --version               Show version information.
  -h, --help              Show help information.

SWIFTTUI OPTIONS:
  --accessible            Accessible mode: drop the TUI for a linear,
                          append-only render. [env: SWIFTTUI_ACCESSIBLE]
  --ascii                 ASCII-only mode. [env: SWIFTTUI_ASCII]
  --reduce-motion         Suppress animations and spinners.
                          [env: SWIFTTUI_REDUCE_MOTION]
  --no-color              Disable color output. [env: NO_COLOR]
  --force-color           Force color output. [env: FORCE_COLOR]
  --plain                 Plain text only: --no-color --ascii --reduce-motion.
  --linear                Linearize side-by-side layouts.
  --json                  Output JSON instead of a TUI.
  --web                   Serve over HTTP instead of a local terminal.
  -v, --verbose           Verbose logging (-v, -vv, -vvv).
  --quiet                 Suppress non-error output.
  --debug                 Framework-internal debug instrumentation.
  --start-in <id>         Open with action scope <id> active.

SUBCOMMANDS:
  web                     Serve the app over HTTP.
  scenes                  Manage scene attachments.
  completions             Generate or install shell completion scripts.
  doctor                  Diagnostic dump.
```

Highlights:

- **`SWIFTTUI OPTIONS` section** is rendered automatically by
  swift-argument-parser when the `OptionGroup` has a `title`.
- **`[env: ...]` annotations** next to each flag's help text. We have
  to render these ourselves; swift-argument-parser doesn't know about
  the env-var binding, so the help string includes it. Click does the
  same with `show_envvar=True`.
- **`-h` and `--help`** identical; **`--help-all`** is reserved for
  future use (showing hidden / advanced flags).
- **`--version`** is auto-provided by the runner. The default version
  string is `<binary-name> <semver>` followed by `swift-tui <version>`
  on a second line, so users debugging issues immediately see which
  framework version they're on. Mirrors Cargo's `cargo --version`
  + `cargo-rustc --version` doubling.
- **Runner-internal subcommands** (`scenes`, `completions`, `doctor`)
  are framework-provided; they appear under SUBCOMMANDS regardless of
  consumer subcommands. If the consumer adds their own subcommands,
  swift-argument-parser's subcommand grouping (1.5.0+) gives both
  groups distinct headings.

### Validation timing

Argument parsing happens in `SwiftTUIApp.main()`, which is called
**before** any of the following:

1. `TerminalRunner.run(...)` is invoked.
2. The terminal is put into raw mode.
3. The alternate screen buffer is acquired (`smcup`).
4. Signal handlers are installed.
5. Any stdout escape sequence is written.

If parsing fails:

- swift-argument-parser writes the error message to stderr in
  cooked mode, no escape sequences.
- Exit code is 64 (`EX_USAGE`) per BSD `sysexits.h` convention. (We
  align with what swift-argument-parser does by default; it's already
  EX_USAGE for parse errors.)
- The terminal is never touched.

If parsing succeeds but env-var overrides are inconsistent (e.g.,
`NO_COLOR=1 FORCE_COLOR=1` set together):

- The framework follows the documented precedence (`NO_COLOR` wins;
  see [Precedence rules](#precedence-rules)).
- A diagnostic message is written to stderr **only** if `--debug` is
  on. Otherwise, the framework silently picks the documented winner.

If `--help` or `--version` is parsed:

- swift-argument-parser writes to stdout and exits 0. No terminal
  setup occurs.

If a runner-internal flag fails post-parse (e.g., the requested
attach target doesn't exist):

- The runner writes its own error message to stderr in cooked mode,
  exits with a runner-defined non-zero code (the existing CLIMode
  behavior). Same constraint: no escape sequences before failure.

This is the strict ordering. Everything user-visible-on-failure must
work in a vt100-only / cooked-mode environment, because we don't know
yet whether stdout is a TTY at all.

---

## Standard flags (table)

The complete set of flags reserved for the framework. Consumer apps
must not redeclare these names (long or short). Redeclaring is a
swift-argument-parser registration error at parse time.

| Long flag | Short | Type | Default | Notes |
|---|---|---|---|---|
| `--accessible` | — | Bool | `false` | Accessible mode. See [ACCESSIBILITY.md](./ACCESSIBILITY.md). |
| `--ascii` | — | Bool | `false` | ASCII-only glyphs. |
| `--reduce-motion` | — | Bool | `false` | Suppress animations and spinners. |
| `--no-color` | — | Bool | `false` | Disable color. Wins over `--force-color`. |
| `--force-color` | — | Bool | `false` | Force color even when stdout is not a TTY. |
| `--no-progress` | — | Bool | `false` | Static status instead of progress bars. |
| `--plain` | — | Bool | `false` | Implies `--no-color --ascii --reduce-motion`. |
| `--linear` | — | Bool | `false` | Linearize HStack layouts. |
| `--json` | — | Bool | `false` | JSON output (where the app supports it). |
| `--web` | — | Bool | `false` | Web-host mode. (Or use `myapp web` subcommand.) |
| `--port <n>` | — | Int | `0` | Port for `--web`. `0` = auto-assign. |
| `--bind <addr>` | — | String | `"127.0.0.1"` | Bind address for `--web`. |
| `--no-open` | — | Bool | `false` | Don't auto-open browser with `--web`. |
| `--verbose` | `-v` | Int | `0` | Repeat-count verbosity (`-v`, `-vv`, `-vvv`). |
| `--quiet` | — | Bool | `false` | Suppress non-error logs. |
| `--debug` | — | Bool | `false` | Framework-internal debug instrumentation. |
| `--start-in <id>` | — | String? | `nil` | Open with action scope `<id>` active. |
| `--help` | `-h` | Bool | — | Standard. Auto. |
| `--help-all` | — | Bool | — | Standard. Auto. Verbose help. |
| `--version` | — | Bool | — | Standard. Auto. |
| `--generate-completion-script <shell>` | — | String | — | swift-argument-parser standard. |

Reserved-but-not-yet-implemented (do not redeclare):

| Long flag | Reason for reservation |
|---|---|
| `--theme <name>` | Decision 0009 (theme/host-owned semantic tokens). |
| `--config <path>` | Future: config file loading. |
| `--cwd <path>` | Future: change working directory. |
| `--dry-run` | Future: render without executing side-effects. |
| `--profile` | Future: emit frame timing profile to stderr. |

These are reserved so that when they land, they don't collide with
any consumer's flags. Consumers who *want* to use them today must
pick a different name and migrate when the framework adopts the
reserved name.

Runner-internal flags (already exist; runner-private; not part of
the framework reserved namespace from a consumer's perspective —
they're consumed by `CLIMode.parse(_:)` before the framework parser
sees them):

| Flag | Where | Notes |
|---|---|---|
| `--instances` | SwiftTUICLI | List running app instances. |
| `--scenes` | SwiftTUICLI | List scenes for the selected instance. |
| `--attach <id>` | SwiftTUICLI | Attach to a scene. |
| `--pid <n>` | SwiftTUICLI | Select instance by PID. |
| `--instance <name>` | SwiftTUICLI | Select instance by name. |

A follow-up may migrate these into proper subcommands (`myapp scenes
list`, `myapp scenes attach <id>`, `myapp instances list`) to align
with the rest of the proposal. That migration is its own change and
is discussed in [Open questions](#open-questions).

---

## Env-var ↔ flag mapping (table)

> **Audit correction (2026-05-04):** the
> `TerminalCapabilityProfile.detect(environment:isTTY:)` function in
> [`Sources/SwiftTUI/Terminal/TerminalPresentation.swift`](../../Sources/SwiftTUI/Terminal/TerminalPresentation.swift)
> already reads `NO_COLOR`, `TERM` (incl. `dumb` and `*256color`),
> `COLORTERM` (incl. `truecolor`/`24bit`), and `LC_ALL`/`LC_CTYPE`/
> `LANG` (drives ASCII glyph fallback). What's missing today:
> `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`, and the
> `SWIFTTUI_*` family. Implication for this proposal:
> `SwiftTUIOptions.runtimeConfiguration()` should **delegate** to
> the existing detection where the env var is already understood,
> and only own the **new** ones. Don't duplicate the existing reads.
> See [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md) Finding 4 for the
> full list and call sites.

Every framework flag has a corresponding env var; every framework env
var has a flag. The accessibility proposal's contract is the source of
truth for which env vars exist. This table extends it.

| Env var | Flag | Source | Behavior |
|---|---|---|---|
| `NO_COLOR` (any non-empty) | `--no-color` | [no-color.org](https://no-color.org/) | Disable color. Wins over `FORCE_COLOR`. Set-but-empty is "unset". |
| `FORCE_COLOR` (non-empty, non-`0`) | `--force-color` | npm convention | Force color even when stdout is non-TTY. |
| `CLICOLOR=0` | `--no-color` | [bixense.com](http://bixense.com/clicolors/) | Legacy BSD. Disable color. |
| `CLICOLOR_FORCE` (non-empty, non-`0`) | `--force-color` | bixense.com | Legacy BSD. Force color. |
| `COLORTERM=truecolor` / `24bit` | (no flag; capability) | xterm convention | Allow 24-bit ANSI. Hint, not an override. |
| `TERM=dumb` | (no flag; capability) | terminfo | No ANSI sequences at all. |
| `LANG=C` / `LC_ALL=C` | `--ascii` (auto-implied) | POSIX locale | Auto-enables ASCII glyph fallback. |
| `CI=true` | (no flag; auto-detected) | CI convention | Treat as non-interactive: implies `--reduce-motion`, `--no-progress`. |
| `SWIFTTUI_ACCESSIBLE=1` | `--accessible` | Framework | Accessible mode. |
| `SWIFTTUI_ASCII=1` | `--ascii` | Framework | ASCII glyphs. |
| `SWIFTTUI_REDUCE_MOTION=1` | `--reduce-motion` | Framework | Suppress animations. |
| `SWIFTTUI_NO_PROGRESS=1` | `--no-progress` | Framework | No progress bars. |
| `SWIFTTUI_PLAIN=1` | `--plain` | Framework | Combined plain mode. |
| `SWIFTTUI_LINEAR=1` | `--linear` | Framework | Linearize layouts. |
| `SWIFTTUI_JSON=1` | `--json` | Framework | JSON output. |
| `SWIFTTUI_WEB=1` | `--web` | Framework | Web-host mode. |
| `SWIFTTUI_PORT=<n>` | `--port` | Framework | Port for `--web`. |
| `SWIFTTUI_BIND=<addr>` | `--bind` | Framework | Bind address for `--web`. |
| `SWIFTTUI_NO_OPEN=1` | `--no-open` | Framework | Don't open browser. |
| `SWIFTTUI_VERBOSE=<n>` | `-v` × n | Framework | Verbosity level (0–3). |
| `SWIFTTUI_QUIET=1` | `--quiet` | Framework | Suppress non-error logs. |
| `SWIFTTUI_DEBUG=1` | `--debug` | Framework | Framework debug instrumentation. |
| `SWIFTTUI_START_IN=<id>` | `--start-in` | Framework | Open with action scope `<id>`. |

**`SWIFTTUI_*` is the framework-reserved env-var prefix.** Consumers must
not use this prefix for their own variables. Consumers' own env vars
should use their own application prefix (e.g., `MYAPP_FOO`), or
`auto_envvar_prefix`-style derivation from the binary name. We do **not**
auto-prefix consumer flags from their binary name, because:

- it surprises (a flag called `--port` quietly reading `MYAPP_PORT`
  is confusing if the user expected `PORT`);
- swift-argument-parser doesn't have the mechanism, and synthesizing
  it via macros / runtime introspection is more cleverness than
  benefit.

If a consumer wants env-var binding for their own flags, they do it
inside their `validate()` or `init()`. We document the pattern but
don't generate it.

The accessibility env vars are documented in
[ACCESSIBILITY.md](./ACCESSIBILITY.md#environment-contract) with
slightly different wording; this table is the canonical superset.

---

## Precedence rules

There is one chain. It applies to every flag.

```
   highest precedence
  ┌───────────────────┐
  │ explicit CLI flag │   e.g., --no-color or --port 9000
  ├───────────────────┤
  │ env var           │   e.g., NO_COLOR=1 or SWIFTTUI_PORT=9000
  ├───────────────────┤
  │ TTY auto-detect   │   e.g., stdout is not a TTY → no color, reduce motion
  ├───────────────────┤
  │ framework default │   e.g., color enabled, motion enabled, port 0
  └───────────────────┘
   lowest precedence
```

Special cases:

1. **`NO_COLOR` always wins over `FORCE_COLOR`.** No-color is a
   stronger signal: it's user opt-out for accessibility; force-color
   is user override of TTY-auto-detection. The user who set both
   probably forgot one was set; no-color is the safe interpretation.
   ([no-color.org spec](https://no-color.org/),
   [Python.org discussion](https://discuss.python.org/t/no-color-and-force-color-precedence/107166).)
2. **`--no-color` always wins over `--force-color`** when both are
   passed on the command line. Same rationale.
3. **CI auto-detection (`CI=true`)** triggers `reduceMotion = true`
   and `noProgress = true` if no explicit user setting overrides. CLI
   flags override; env vars (`SWIFTTUI_REDUCE_MOTION=0`) override.
4. **TTY auto-detection.** When stdout is not a TTY, color is
   disabled and animations are suppressed by default. `--force-color`
   or `FORCE_COLOR` overrides the color suppression.
5. **`--plain` is resolved last.** If set, it implies `noColor=true`,
   `ascii=true`, `reduceMotion=true`. It does **not** override
   explicit per-flag settings: `--plain --force-color` ends up with
   `forceColor=true` and `noColor=true`, and the `noColor` wins per
   rule 2. (This matches the principle that `--plain` is a
   convenience aggregate, not a hard reset.)
6. **`--accessible` implies, but doesn't force, ASCII + reduce-motion.**
   Per the accessibility proposal's open question 1, the lean is
   "imply, but allow individual overrides." So `--accessible
   --reduce-motion=false` is honored.
   *(Open: swift-argument-parser doesn't natively express
   `--reduce-motion=false` for a Bool flag. We may need to switch the
   reduce-motion declaration to `@Option<Bool?>` to allow explicit
   off, or accept that `--accessible` is monolithic. See
   [Open questions](#open-questions).)*

---

## Reserved namespace and collision policy

**Reserved long flag names** — consumers must not declare these:

```
--accessible            --plain                 --port
--ascii                 --linear                --bind
--reduce-motion         --json                  --no-open
--no-color              --web                   --start-in
--force-color           --verbose               --debug
--no-progress           --quiet                 --help-all
--theme                 --config                --cwd
--dry-run               --profile               --version
--help                  --generate-completion-script
```

**Reserved short flag names** — consumers must not declare these:

```
-v   -h
```

Consumers may use any other short flag freely, including `-c`, `-p`,
`-q`, `-d`, etc. The framework deliberately does **not** reserve
`-q`, `-d` short forms despite using `--quiet` and `--debug` long
forms, because those long forms are common enough that consumers may
have good reason to use the shorts.

**Runner-internal namespace.** The current `--instances`, `--scenes`,
`--attach`, `--pid`, `--instance` flags are runner-private and
consumed by `SwiftTUICLI` before the framework parser sees them. They
are not part of the namespace consumers have to avoid (because they
never reach the consumer's parser); but they will collide if a
consumer happens to declare `--attach` or `--pid`, because the runner
strips them first. Convention: don't redeclare these either. The
follow-up that migrates them to subcommands eliminates this
sharp-edge.

**Collision detection.**

- swift-argument-parser registers all flags into one namespace at
  parse time. A duplicate long-name is a registration error, surfaced
  as `ArgumentParser.ValidationError` with a descriptive message.
- We catch this error in `SwiftTUIApp.main()` and rewrap it with a
  framework-flavored error message that names which framework flag
  the consumer collided with.
- We do not provide a runtime "consumer wins" or "framework wins"
  override. The collision is a bug in the consumer's app declaration.

**Future-reserved names.** New framework flags landing in future
versions go through a deprecation cycle: they're added with a
`-WARNING-` prefix in help text, and a stderr warning fires if a
consumer's flag with the same name is in scope. After two minor
versions, the framework flag activates and the consumer must
rename theirs.

---

## Completions, `--help`, `--version`

### `--help` and `-h`

Auto-provided by swift-argument-parser. Format described in
[Help formatting and discoverability](#help-formatting-and-discoverability)
above.

### `--help-all`

Auto-provided by swift-argument-parser. Shows everything `--help`
shows plus hidden flags, expanded discussions, and per-subcommand
deep dives.

We mark a few advanced flags as `.help(.hidden)` so they only appear
under `--help-all`:

- `--debug` (framework debug instrumentation; not for end users).
- `--profile` (when added).
- `--start-in` (intended for development; see
  [decision 0003 interaction](#interaction-with-decision-0003-action-scopes)).

### `--version`

Auto-provided by swift-argument-parser via
`CommandConfiguration.version`. The `SwiftTUIApp` protocol's default
synthesizes a two-line version string:

```
myapp 1.4.2
swift-tui 0.42.0 (from package: ...)
```

This way users who file accessibility / web / runner bugs include
the framework version. Apple's tools all do this; it's been pure
upside in every CLI ecosystem.

### Shell completions

swift-argument-parser ships completion-script generation for zsh,
bash, and fish out of the box. The `myapp completions` subcommand:

```
myapp completions install zsh                 # writes to a user completion dir
myapp completions print zsh                  # prints to stdout
myapp completions print bash > /etc/...      # for manual install
```

Cost: nearly free. swift-argument-parser does the work; we just
expose the existing
`myapp --generate-completion-script <shell>` machinery via a friendly
subcommand. `install` writes to user-writable shell-specific defaults and accepts
`--output <path>` for explicit installation targets.

Consumer opt-in: any consumer using `SwiftTUIApp` gets completions
automatically. Consumers using bare `AsyncParsableCommand` already
get them from swift-argument-parser. Consumers in bare mode (no
parser) don't get them, which is fine — they don't have flags to
complete anyway.

---

## Logging, verbosity, quiet, debug

The framework provides `--verbose`/`-v`, `--quiet`, `--debug`. The
question is whether the framework also provides a *logger*, or just
the flags.

**Lean: provide flags only.** Wire the parsed verbosity level into
the runner's existing diagnostic story (which is currently mostly
nonexistent in `SwiftTUI` proper). When a real logging substrate
lands, it consumes the `verbosity` field of `RuntimeConfiguration`.

```swift
public struct RuntimeConfiguration: Sendable {
  public var verbosity: Verbosity   // .quiet, .normal, .verbose(level: Int), .debug
  public var color: ColorMode       // .never, .always, .auto
  public var glyphs: GlyphMode      // .ascii, .unicode
  public var motion: MotionMode     // .reduced, .normal
  public var output: OutputMode     // .tui, .json, .accessible
  public var web: WebConfig?        // nil unless --web/--web subcommand
  public var startIn: String?       // action-scope ID
  public var debug: Bool
  // ...
}
```

This separates "how does the framework decide what to log?" from "how
does the framework actually log?" The answer to the first question
is "by reading `RuntimeConfiguration.verbosity`." The answer to the
second is "TBD; not in this proposal."

Consumer apps that need their own logger import `swift-log` or
similar, configure it from `RuntimeConfiguration.verbosity`, and
ignore the framework's internal logging entirely.

`--debug` is **not** equivalent to `-vvv`. Verbosity controls how
talkative the log messages are; debug controls *whether the framework
emits internal instrumentation at all* (frame timings, focus chain
traces, render-tree diagnostics). Conflating them was tempting but is
wrong: a consumer running with `-vvv` for their own deep logs
probably doesn't want our internal frame timings spammed at them.

---

## Pass-through args and `--`

swift-argument-parser respects `--` as the option-parsing terminator
per GNU getopt-long convention. Anything after `--` is passed to
`@Argument(parsing: .remaining)` arrays.

For SwiftTUI consumers, this matters in two cases:

1. **Pass-through to the embedded web host.** If a consumer wants to
   pass extra arguments to the web server (e.g., custom static
   assets), they're declared as `@Argument(parsing: .remaining)` on
   the `web` subcommand:

   ```text
   myapp web -- --custom-server-flag
   ```

2. **Consumer's own argv-after-`--`.** If a consumer has a "run" mode
   that itself accepts free-form args (rare, but conceivable), the
   convention is the same.

We do not need a special framework-side mechanism for this; the
default swift-argument-parser behavior is correct.

---

## Interaction with decision 0008 (runners own main)

[ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md)
says: SwiftTUI is library-only; executable launch is owned by peer
runner packages. This proposal layers cleanly on top:

- **`SwiftTUIArguments` is a peer of the runner packages.** It does
  not move into root SwiftTUI. The Foundation-free invariant on
  `SwiftTUICore`, `SwiftTUIViews`, and `SwiftTUI` is preserved.
- **The protocol `SwiftTUIApp` lives in `SwiftTUIArguments`.** It is
  *not* a re-export from `SwiftTUI`. Consumers who want it import it
  explicitly:

  ```swift
  import SwiftTUI
  import SwiftTUICLI
  import SwiftTUIArguments
  ```

  This matches the existing pattern of "import SwiftTUI + import
  SwiftTUICLI." The third import is opt-in; bare-mode consumers
  skip it.
- **The runner consumes a typed `RuntimeConfiguration`, not a parser
  object.** This means a future WASI-mode runner, browser-host, or
  SwiftUI-host can also accept the same configuration value, even
  though the *parser* doesn't make sense in those contexts (e.g.,
  there's no argv in a browser tab). Each runner reads what it needs
  from `RuntimeConfiguration`; no runner has to know about
  swift-argument-parser.
- **WASI runner integration.** `SwiftTUIWASI` could ship its own
  thin `SwiftTUIWASIApp` protocol that follows the same pattern but
  parses from manifest mode rather than argv. Sketched, deferred.
- **GUI/SwiftUIHost and GUI/WebHost integration.** These don't have
  argv, but they may take config from their hosting environment
  (URL params, app delegate launch options, browser query string).
  A "manual" `RuntimeConfiguration` builder exists for these cases:

  ```swift
  let configuration = RuntimeConfiguration.builder
    .accessible(true)
    .ascii(true)
    .build()

  try await SwiftUIHost.run(MyApp.self, configuration: configuration)
  ```

  This way, accessibility-related env-var/flag choices aren't
  *exclusive* to argv-driven runners; they ride on the typed
  configuration value, which any runner can construct.

The bet: argument parsing is a runner-layer concern, not a
framework-core concern. Decision 0008 already drew that line; this
proposal stays inside it.

---

## Interaction with decision 0003 (action scopes)

[ADR-0003](../decisions/0003-action-scopes-not-global-hotkeys.md)
established that command authority lives at authorial focus scopes,
not in a global hotkey registry. The relationship to argument
parsing is small but real:

- **`--start-in <scope-id>`** opens the app with a specific scope
  already focused. Useful for development (jump straight to the
  panel you're working on), for accessibility (skip navigation
  to the most relevant region for screen-reader users), and for
  scripting (deep-link into a specific panel from a shell alias).
- The scope ID is matched against the runtime's scope-identity
  table at startup. If the ID doesn't exist, the app starts at its
  default scope and emits a warning to stderr (visible only with
  `--debug` or `-v`).
- Scope IDs are author-declared strings; the framework doesn't
  enumerate them. Consumers who want `--start-in` to be helpful
  document their scope IDs in their app's `--help` discussion text.

This flag is intentionally minimal. We do not propose:

- A flag-driven way to *trigger* arbitrary commands (`--invoke
  some-command`). That's scripting territory; do it via stdin or
  an IPC mechanism.
- A flag-driven way to *register* commands (`--register-command ...`).
  Action scopes are tree-authored per ADR-0003.

---

## Interaction with the embedded web host

> **TODO: cross-reference EMBEDDED_WEB_HOST.md once it lands.** The
> parallel investigation for the embedded web host is in progress.
> The flags this proposal defines (`--web`, `--port`, `--bind`,
> `--no-open`, env vars `SWIFTTUI_WEB`, `SWIFTTUI_PORT`,
> `SWIFTTUI_BIND`, `SWIFTTUI_NO_OPEN`) anticipate that proposal's
> needs. If the embedded-host proposal converges on different
> defaults (e.g., `--bind 0.0.0.0` instead of `127.0.0.1`, or
> additional flags like `--tls-cert`, `--basic-auth`), this
> proposal updates to match.

Sketched expectations:

- `myapp web` (subcommand) or `myapp --web` (flag) starts an HTTP
  server that surfaces the SwiftTUI app to a browser via the
  WASI-WebHost path.
- Port `0` means auto-assign; the chosen port is printed to stderr
  ("Listening on http://127.0.0.1:54321") so the user can connect.
- `--no-open` suppresses the auto-open-browser convenience.
- `--bind` defaults to `127.0.0.1` (loopback only) for safety. Users
  who want LAN access pass `--bind 0.0.0.0` explicitly. This matches
  Textual's `textual serve` and Jupyter's `jupyter notebook`.
- Web mode implies different accessibility defaults: real ARIA
  rather than terminal accessible-mode. The `RuntimeConfiguration`
  carries enough to decide, but the embedded-web-host proposal will
  refine. (See [ACCESSIBILITY.md → What the Web and SwiftUI targets
  unlock](./ACCESSIBILITY.md#what-the-web-and-swiftui-targets-unlock).)

---

## Open questions

(Things we should decide before implementation starts. Each has a
Lean; lean is meant to be argued with, not committed.)

1. **Should `--web` be a flag or a subcommand (or both)?**
   Flag-only: simpler, one entry point. Subcommand-only: groups
   web-specific options (`--port`, `--bind`, `--no-open`) under one
   verb. Both: most flexible, slightly redundant. **Lean: both,
   document subcommand as primary.** Consumers and shell scripts
   often prefer flags; subcommands help discoverability and group
   the options clearly in `--help`.

2. **Should `SwiftTUIApp` be a protocol or a base struct?** Protocol
   composition with `App` and `AsyncParsableCommand` is fiddly
   (Swift-level dispatch ambiguities possible). A base struct is
   cleaner but locks consumers into single inheritance. **Lean:
   protocol.** The fiddliness is well-trodden in Swift now (Apple's
   own `App` is a protocol composing with multiple things). We pay
   the protocol-ergonomics price once.

3. **Should env-var binding be declarative on individual flags, or
   purely a `runtimeConfiguration()`-time merge?** Click does
   declarative (`@Option(envvar="MYAPP_PORT")`); we'd need to
   layer this on top of swift-argument-parser. A merge-time bridge
   table is simpler. **Lean: merge-time bridge for the framework
   flags; consumers do their own env-var bridging if they want it
   for their flags.** Consider revisiting if the bridge table grows
   unwieldy.

4. **Should `--accessible` be `.flag` (Bool) or `.option` (enum:
   off / on / auto)?** A Bool can't express "default to env-var
   detection." We could parse `--accessible=auto` as the default
   value, but swift-argument-parser doesn't natively support
   `--flag=value` syntax for Bool `@Flag`. **Lean: `@Option<Mode>`
   with default `.auto`**, where `.auto` means "use env vars or
   accessibility-feature detection." More verbose but expressive.
   Trade-off: more boilerplate per flag if every accessibility
   flag becomes a tri-state.

5. **`-v` vs `--verbose <n>`.** swift-argument-parser supports
   repeat-counting (`-v`, `-vv`, `-vvv`) via `@Flag` with
   `.shortAndLong` and an `Int` storage. It does **not** combine
   that with `--verbose 3` syntax cleanly. **Lean: support `-v` /
   `-vv` / `-vvv` only; no `--verbose 3`.** Matches how most
   tools document verbosity.

6. **`--quiet` semantics.** Click and many tools interpret `--quiet`
   as "log level error+ only, no info". We'd do the same. But what
   if the consumer's app has its own non-log output (e.g., the
   final TUI render)? **Lean: `--quiet` applies only to log streams,
   never to the TUI render itself or to stdout.** The TUI is the
   product, not noise.

7. **Migration of runner-internal flags to subcommands.** Should
   `--instances` / `--scenes` / `--attach` / `--pid` / `--instance`
   become `myapp scenes list` / `myapp instances list` / `myapp
   scenes attach <id>`? **Lean: yes, in a follow-up.** The current
   shape is a hand-rolled state machine that doesn't compose with
   the rest of the parser surface. Migration is mechanical; old
   flags can stay deprecated for a release.

8. **Should the `RuntimeConfiguration` value type live in `SwiftTUI`
   itself or in a shared support target?** It's needed by every
   runner (CLI, WASI, SwiftUI host, web host) and by
   `SwiftTUIArguments`. **Lean: `SwiftTUI` itself.** It's a value
   type with no Foundation dependencies; it carries no parser
   knowledge. The Foundation-free invariant is preserved.

9. **Should we auto-derive an env-var prefix from the consumer's
   binary name, à la Click's `auto_envvar_prefix`?**
   `myapp --port 9000` reading `MYAPP_PORT` automatically. **Lean:
   no.** Surprising, hard to opt out of, hard to namespace correctly.
   If a consumer wants this, they can do it explicitly in their
   `init()`.

10. **Should `SwiftTUIArguments` be a separate package or a target
    in the root `swift-tui` package?** Separate package keeps
    swift-argument-parser dependency out of the root package
    `Package.resolved`. Same-package target is more discoverable.
    **Lean: same package, separate library product (like
    SwiftTUICharts is today).** Consumers add the dependency only
    when they import the product; SPM handles the transitive
    dependency.

11. **Flag visibility for runner-internal vs. framework-public.**
    Today, the runner-internal CLIMode flags (`--instances` etc.)
    are not exposed in any `--help` because there's no parser. After
    this proposal lands, do they appear under `SUBCOMMANDS` (if
    migrated), under their own `RUNNER OPTIONS` section, or stay
    invisible? **Lean: migrate to subcommands; runners that haven't
    migrated keep flags hidden behind `--help-all` until they do.**

12. **`--start-in <scope-id>` validation.** Should we error on an
    unknown scope ID at parse time, at startup, or at first use? We
    can't know at parse time (scopes are tree-authored, not declared
    statically). **Lean: warn at startup if the ID doesn't resolve
    by first commit; don't fail the run.** The user typed the wrong
    name; bring up the app at default scope and tell them.

13. **Error exit codes.** Use BSD `sysexits.h` constants (`EX_USAGE
    = 64`, `EX_CONFIG = 78`, `EX_NOINPUT = 66`)? Or just `1` for
    everything? **Lean: BSD sysexits for parser errors (matches
    swift-argument-parser default), `1` for runtime errors, `130`
    for SIGINT (the convention).** This is what every well-behaved
    CLI does.

14. **What happens to `--debug` after a runtime crash?** If the
    framework crashes mid-run (per ADR-0010, the CLI runner has a
    crash guard), should `--debug` log the crash details to stderr?
    **Lean: yes. The crash guard reads `RuntimeConfiguration.debug`
    and writes a richer post-mortem when set.**

15. **Conditional compilation for non-CLI runners.** The current
    `CLIMode` is wrapped in `#if !canImport(WASILibc)` because PIDs
    don't make sense on WASI. Will `SwiftTUIArguments` need similar
    guards? **Lean: yes, for the `--web` / `--port` set, which
    only makes sense in runtime contexts that can host an HTTP
    server.** A WASI-runtime context that's already running inside
    the browser doesn't need `--web`; it's already there. Some
    flags compile out. The flag table stays the same; the wiring
    changes per-runner.

---

## Out of scope

This proposal does **not** cover:

- A framework-supplied logging substrate. We provide the verbosity
  flags; the logger itself is a separate concern (and might be
  swift-log, or might be framework-internal). Tracked separately.
- Localization of help text and error messages. swift-argument-parser
  has limited i18n support today. We adopt whatever it does.
- Configuration-file loading (`--config /path/to/conf`). Reserved
  flag name; not implemented in v1.
- Plugin loading from an external binary (kubectl-style). The
  ecosystem isn't there; not relevant to a TUI framework.
- Interactive `--prompt`-style fallback parsing (Click's prompt-on-
  missing feature). We don't take stdin during arg parsing; if a
  required flag is missing, we error out.
- Auto-generation of man pages. swift-argument-parser has a manuals
  generator (`swift-argument-parser-manuals`); consumers can opt
  into it. The framework doesn't ship the binary.
- Schema-validated config (TOML/YAML/JSON file → `RuntimeConfiguration`).
  Belongs to a future config-file proposal.
- Negotiated flag aliases (`--colour` for British speakers). One
  spelling per flag.
- Auto-derivation of env-var prefix from binary name (open question 9,
  leaning no).

---

## Suggested phasing

(Sketch only — order is argued for, not committed to.)

1. **Phase 1 — `RuntimeConfiguration` type.** Land the typed value in
   `SwiftTUI`. Wire it into the existing runner entry points as an
   optional parameter with a default. No behavior change to existing
   apps; just a new seam.

2. **Phase 2 — Env-var resolution.** Implement `RuntimeConfiguration`
   construction from `[String: String]` env. This is purely additive;
   apps using bare mode start honoring `NO_COLOR`, `LANG=C`, etc., as
   soon as the runner reads the env at startup.

3. **Phase 3 — `SwiftTUIArguments` package, `SwiftTUIOptions`
   OptionGroup.** Power-mode usage (Option B). Consumers who want it
   add a dependency. Framework flags appear in their `--help`.

4. **Phase 4 — `SwiftTUIApp` protocol.** Easy-mode usage (Option C).
   Default `main()`, default `runtimeConfiguration()`. Examples
   migrated from bare mode to protocol mode.

5. **Phase 5 — `myapp completions` subcommand.** Surface
   swift-argument-parser's completion-script generation through a
   friendly subcommand.

6. **Phase 6 — Migrate runner-internal flags to subcommands.**
   `myapp scenes list`, `myapp instances list`, `myapp scenes attach
   <id>`. The hand-rolled `CLIMode.parse` is replaced; old flags stay
   for a release with deprecation warnings.

7. **Phase 7 — Web subcommand wiring.** When EMBEDDED_WEB_HOST.md
   lands, wire `myapp web` to the embedded web runner. The flag /
   subcommand surface in this proposal is already correct; phase 7
   is the runtime side.

8. **Phase 8 — Documentation, examples, and the migration story.**
   Update `Examples/gallery` and `Examples/minimal` to use
   `SwiftTUIApp`. Document the bare → easy-mode migration.

Each phase is independently shippable; each gives consumers more
ergonomics than the previous one. Phases 1–3 are the foundation;
phases 4–8 are user-facing surface.

---

## Sources

The full research is summarized inline above. Primary sources, grouped
by theme:

### swift-argument-parser

- Apple — [`swift-argument-parser` README](https://github.com/apple/swift-argument-parser/blob/main/README.md)
- Apple — [CHANGELOG.md](https://github.com/apple/swift-argument-parser/blob/main/CHANGELOG.md)
- Apple — [ArgumentParser DocC](https://apple.github.io/swift-argument-parser/documentation/argumentparser/)
- Apple — [Declaring Arguments, Options, and Flags](https://apple.github.io/swift-argument-parser/documentation/argumentparser/declaringarguments/)
- Apple — [AsyncParsableCommand](https://apple.github.io/swift-argument-parser/documentation/argumentparser/asyncparsablecommand/)
- Apple — [OptionGroup (swiftinit)](https://swiftinit.org/docs/swift-argument-parser/argumentparser/optiongroup)
- Apple — [Customizing Completions](https://swiftinit.org/docs/swift-argument-parser/argumentparser/customizingcompletions)
- Apple — [PR #644: subcommand grouping](https://github.com/apple/swift-argument-parser/pull/644)
- Swift.org — [Announcing ArgumentParser blog post](https://www.swift.org/blog/argument-parser/)
- SwiftToolkit.dev — [Interactive Swift Argument Parser Guide, Part I](https://www.swifttoolkit.dev/posts/argument-parser-guide)
- SwiftToolkit.dev — [Part III: Options, Validation & Exiting](https://www.swifttoolkit.dev/posts/argument-parser-guide-3)
- DeepWiki — [swift-argument-parser overview](https://deepwiki.com/apple/swift-argument-parser/1-swift-argument-parser-overview)

### Cross-language argument parsers

- Pallets — [Click commands and groups](https://click.palletsprojects.com/en/stable/commands-and-groups/)
- Pallets — [Click discussion #2684: auto_envvar_prefix](https://github.com/pallets/click/discussions/2684)
- Pallets — [Click issue #873: variable precedence](https://github.com/pallets/click/issues/873)
- Pallets — [Click issue #2313: show_envvar global setting](https://github.com/pallets/click/issues/2313)
- Cobra — [Working with Flags](https://cobra.dev/docs/how-to-guides/working-with-flags/)
- Cobra — [User Guide](https://github.com/spf13/cobra/blob/main/site/content/user_guide.md)
- Cobra — [pkg.go.dev reference](https://pkg.go.dev/github.com/spf13/cobra)
- Cobra — [Issue #1982: exclude persistent flag in subcommand](https://github.com/spf13/cobra/issues/1982)
- clap — [`clap::_derive` Rust docs](https://docs.rs/clap/latest/clap/_derive/index.html)
- clap — [Issue #3269: clap_derive Arg methods with flattened](https://github.com/clap-rs/clap/issues/3269)
- clap — [Issue #5525: from_global with flatten](https://github.com/clap-rs/clap/issues/5525)
- Commander — [npm package](https://www.npmjs.com/package/commander)
- Rust CLI Recommendations — [Handling arguments and subcommands](https://rust-cli-recommendations.sunshowers.io/handling-arguments.html)

### POSIX / GNU / standards

- The Open Group — [POSIX Utility Conventions, chapter 12](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
- GNU — [Command-Line Interfaces (GNU Coding Standards)](https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html)
- GNU — [Argument Syntax (libc manual)](https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html)
- nullprogram — [Conventions for Command Line Options](https://nullprogram.com/blog/2020/08/01/)
- BSD — [`sysexits.h` exit codes](https://man.freebsd.org/cgi/man.cgi?sysexits)

### Plugin / extension / namespace patterns

- Kubernetes — [Extend kubectl with plugins](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/)
- Kubernetes — [kubectl issue #1324: flag placement before plugin name](https://github.com/kubernetes/kubectl/issues/1324)
- gianarb — [kubectl flags in your plugin](https://gianarb.it/blog/kubectl-flags-in-your-plugin)
- Cargo — [The Cargo Book: configuration](https://doc.rust-lang.org/cargo/reference/config.html)
- Cargo — [`cargo rustc` reference](https://doc.rust-lang.org/cargo/commands/cargo-rustc.html)
- Rustup — [Overrides](https://rust-lang.github.io/rustup/overrides.html)
- AWS — [AWS CLI v2 reference](https://docs.aws.amazon.com/cli/latest/reference/)
- AWS — [Accessing help and resources for the AWS CLI](https://docs.aws.amazon.com/cli/v1/userguide/cli-usage-help.html)

### Env-var conventions (consistent with ACCESSIBILITY.md)

- [no-color.org — NO_COLOR specification](https://no-color.org/)
- [bixense.com — CLICOLOR / CLICOLOR_FORCE](http://bixense.com/clicolors/)
- Python.org — [NO_COLOR / FORCE_COLOR precedence discussion](https://discuss.python.org/t/no-color-and-force-color-precedence/107166)

### Internal references

- [docs/decisions/0008-swifttui-library-only-runners-own-main.md](../decisions/0008-swifttui-library-only-runners-own-main.md)
- [docs/decisions/0003-action-scopes-not-global-hotkeys.md](../decisions/0003-action-scopes-not-global-hotkeys.md)
- [docs/decisions/0010-crash-guard-in-cli-runner-not-swifttui.md](../decisions/0010-crash-guard-in-cli-runner-not-swifttui.md)
- [docs/proposals/ACCESSIBILITY.md](./ACCESSIBILITY.md)
- `Platforms/CLI/Sources/SwiftTUICLI/CLIMode.swift` — current hand-rolled flags
- `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift` — current entry point

---

## Changelog

- 2026-05-04: Draft created. Captures the design space for SwiftTUI
  argument parsing, including the API options considered (bare,
  OptionGroup, protocol, hand-rolled, macro), the standard-flags
  table, the env-var ↔ flag mapping consistent with ACCESSIBILITY.md,
  precedence rules, and the integration with decisions 0008 and
  0003. The recommended path is the `SwiftTUIArguments` peer package
  shipping `SwiftTUIOptions: ParsableArguments` (power mode) and
  `SwiftTUIApp: AsyncParsableCommand & App` (easy mode), layered on
  top of swift-argument-parser. Web-host flag specifics
  (`--web` / `--port` / `--bind` / `--no-open`) are sketched and will
  be reconciled with EMBEDDED_WEB_HOST.md once it lands.
- 2026-05-04: Substrate-audit correction applied. See
  [`SUBSTRATE_AUDIT.md`](./SUBSTRATE_AUDIT.md). The existing
  `TerminalCapabilityProfile.detect` already reads `NO_COLOR`,
  `TERM`, `COLORTERM`, and the `LANG`/`LC_*` family;
  `runtimeConfiguration()` should delegate to it for those vars
  rather than reimplement parsing. The `SWIFTTUI_*` family,
  `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, and `CI` are new and
  remain owned by `SwiftTUIOptions`.
- 2026-05-05: Phase 6 landed. `CLIMode.parse` is now fully backed by an
  ArgumentParser command tree (`RunnerCLI` with `Run` / `Instances` /
  `Scenes` / `Attach` subcommands). `Run` is the default subcommand, so
  bare `myapp` and `myapp --instance NAME` invocations route to it
  naturally. Surface in bare-mode `App.main()`:
    - `myapp` / `myapp --instance NAME` — `.app(instanceName: ...)`
    - `myapp instances` — `.listInstances`
    - `myapp scenes [--pid N | --instance NAME]` — `.listScenes(...)`
    - `myapp attach <scene-id> [--pid N | --instance NAME]` — `.attach(...)`
  The pre-production cleanup pass removed the legacy hand-rolled flag
  parser, the `CLIModeError` enum, and the one-shot deprecation warning
  (the framework has no consumers yet, so a deprecation cycle would be
  pure overhead). `CLIMode.parse(_:)` is no longer throwing.
  Discoverability via `myapp --help` for `SwiftTUIApp` consumers is NOT
  in scope here — their parser owns argv first; surfacing the runner
  subcommands through their `--help` requires deeper integration that
  remains a follow-up.
- 2026-05-05: Color/glyphs flag-to-rendering wiring landed.
  `TerminalCapabilityProfile.applying(_ configuration:)` overlays the
  user's `RuntimeConfiguration.color` and `RuntimeConfiguration.glyphs`
  on top of the env-detected profile; `SceneRuntime` and
  `TerminalRunner.launchApp` thread the configuration through to
  `TerminalHost(capabilityProfile:)`. So `--no-color`, `--force-color`,
  `--ascii`, and `--plain` (which expands to `--no-color --ascii
  --reduce-motion`) now affect the actual render. Other fields
  (`motion`, `output`, `web`, `linear`, `noProgress`, `debug`, `startIn`)
  remain parsed-but-unwired and are tracked as follow-up plans.
- 2026-05-05: Phases 1–5 landed via plan
  [`docs/plans/2026-05-04-002-argument-parsing-plan.md`](../plans/2026-05-04-002-argument-parsing-plan.md).
  `RuntimeConfiguration` value type + `Builder` + `detect(...)` factory in
  `SwiftTUI` core; `TerminalRunner.run(_:configuration:)` overload and
  env-var-aware default `App.main()` in `SwiftTUICLI`; new
  `Platforms/Arguments/` peer package shipping `SwiftTUIOptions:
  ParsableArguments`, `SwiftTUIOptions.runtimeConfiguration(...)`,
  `SwiftTUIApp` protocol with default `static func main()` (disambiguating
  `App.main` vs `AsyncParsableCommand.main`), and `CompletionsCommand`
  subcommand surface. `Examples/gallery` migrated; `Examples/argparse`
  added as the canonical consumer-flag + framework-flag demo;
  `Examples/minimal` documented as the bare-mode rendering reference.
  Two implementation refinements emerged during the plan: (1) the
  `--plain` precedence had a code-vs-doc mismatch that was resolved by
  treating `--plain` as a flag-expander rather than a direct mutator
  (so `--plain --force-color` yields `noColor` per proposal §Precedence
  rules item 5); and (2) consumers must annotate `@MainActor` and use
  `@preconcurrency SwiftTUIApp` because `App.init()` is `@MainActor` and
  `ParsableArguments.init()` is nonisolated — a future macro could
  absorb both modifiers.
