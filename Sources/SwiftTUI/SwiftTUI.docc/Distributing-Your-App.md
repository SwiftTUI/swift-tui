# Distributing Your App

Build a release binary of your SwiftTUI app, and know what that one
executable carries when you hand it to users.

## Overview

SwiftTUI is a source dependency: each build compiles the framework together
with your app, and the build configuration applies to both. This is
different from SwiftUI, which ships as a prebuilt system framework. The
trade-off:

- A **release** build optimizes the framework, so it is slow to compile.
- A **debug** build compiles fast, but the unoptimized framework is slow at
  run time.

Use debug builds (the `swift build` and `swift run` default) while you
iterate. Build with `-c release` for anything you judge performance on, and
for every binary you distribute.

Distribution itself needs no special tooling: normal SwiftPM dependency
wiring is all a shipped app builds from. Your app does not need SwiftTUI's
maintainer toolchain, and it does not need to copy SwiftTUI's package
configuration (see <doc:Choosing-Modules-And-Platforms>).

## Build the Release Binary

```bash
swift build -c release
.build/release/myapp    # the built executable, named after your product
```

`swift build -c release` places each executable product under
`.build/release/`. That file is the deliverable: Swift compiles your
interface into a single executable with checked concurrency.

## What One Binary Ships

Terminal capability is negotiated at run time, not at build time. Truecolor,
Kitty and Sixel images, OSC 8 hyperlinks, and mouse reporting are probed per
session and degrade gracefully, so the same binary is correct in kitty, a
bare SSH session, or CI.

An app built on the `SwiftTUI` product conforms to `SwiftTUICommand`, so the
binary also ships the standard `SwiftTUIOptions` flag surface, listed in a
separate SWIFTTUI OPTIONS section of `--help`:

- Appearance: `--no-color`, `--force-color`, `--ascii`
- Accessibility: `--accessible`, `--reduce-motion`,
  `--cursor-follows-focus`, `--stable-output`
- Output and diagnostics: `--json`, `--debug`
- Web hosting: `--web`, with `--port`, `--bind`, `--open`, and `--scene`

Each flag names its environment-variable equivalent in its help text
(`NO_COLOR`, `SWIFTTUI_ACCESSIBLE`, and so on). `--web` works because the
default `SwiftTUI` product links the embedded WebHost server and browser
bundle into the binary; the narrower `SwiftTUICLI` runner is a terminal-only
graph that rejects it.

## Ship Shell Completions

`CompletionsCommand`, from the `SwiftTUIArguments` module, gives the binary
a `completions` subcommand. `SwiftTUICommand` installs it by default. If
your app overrides `CommandConfiguration`, keep it in the `subcommands`
list:

```swift
nonisolated static let configuration = CommandConfiguration(
  commandName: "myapp",
  subcommands: [CompletionsCommand.self, InfoCommand.self]
)
```

Users generate or install the scripts from the shipped binary itself:

```bash
myapp completions print zsh > ~/.zsh/completions/_myapp
myapp completions install bash
myapp completions install fish --output ~/.config/fish/completions/myapp.fish
```

`print` writes the script for `zsh`, `bash`, or `fish` to stdout; `install`
writes it to the shell's user-writable completion location, or to `--output`.
The generated script includes your app's own options as well as the standard
SwiftTUI flags. The framework resolves the `completions` verb before any
subcommand-routing hook runs, so an app can neither shadow nor forget it.
swift-argument-parser's `--generate-completion-script <shell>` also remains
available on every command as the lower-level spelling.

## Platform Checklist

- **macOS** is the primary supported Apple-host path (macOS 15+).
- **Linux** terminal builds and tests are supported through `swiftly`.
- **Windows** binaries must be linked with a larger stack reserve — release
  builds included — or the runtime degrades to the stack-lean engine
  profile: a default-linked Windows executable reserves only a 1 MiB
  main-thread stack, below the 8 MiB full-engine floor.

  ```bash
  swift build -c release -Xlinker /STACK:16777216
  ```

  A debug build that degrades emits a `windows.stack-floor-lean-profile`
  runtime issue naming the remedy. On Windows the `SwiftTUI` umbrella serves
  the terminal launch surface only: the WebHost products do not build there,
  and `--web` fails with the web-runner-not-linked diagnostic.

The full host and distribution matrix lives in
[Hosts and Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms).

## Distributing to the Browser

The same authored `App` can ship to a web page instead of a terminal: serve
it from the native binary with `--web`, or compile a static WebAssembly
bundle that any web host can serve. See
[Deploying to the Browser](https://swifttui.sh/docs/documentation/swifttuiwasi/deploying-to-the-browser).
