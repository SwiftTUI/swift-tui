# Toolchains

Last updated: March 30, 2026

This repository uses more than one build tool, but the default Swift workflow
for package development and verification is `swiftly` with Swift `6.3.0`.

## Swift

The repo pins Swift `6.3.0` in [`.swift-version`](../.swift-version).

Use `swiftly` by default for all repo-local SwiftPM work:

```bash
swiftly run swift build
swiftly run swift test
swiftly run swift package generate-documentation --target TerminalUI
```

If you prefer the shorter `swift ...` form, only use it from a shell where
`swift` already resolves to the `swiftly`-managed Swift 6.3.0 toolchain.

That means:

- `swift` resolves to the `swiftly`-managed Swift 6.3.0 toolchain
- `swift --version` reports `Apple Swift version 6.3 (swift-6.3-RELEASE)`

Verify that first:

```bash
swift --version
```

If your shell does not already resolve `swift` through `swiftly`, either fix
your PATH or use `swiftly run swift ...` explicitly.

Equivalent shorthand once `swift` is routed through `swiftly`:

```bash
swift build
swift test
swift package generate-documentation --target TerminalUI
```

Do not use `xcrun swift` for the repo's package builds, tests, DocC generation,
or wasm packaging. `xcrun` may resolve to an Xcode-selected toolchain that does
not match the repo's pinned Swift 6.3.0 environment.

## WASM

The wasm-facing package work also uses the same `swiftly`-managed Swift 6.3.0
toolchain, but with the wasm SDK selected through `--swift-sdk`.
Wasm builds of TerminalUI apps will often require a stack size larger than the default.
Their starting and max memory can also be bumped - although no yet-known failures have been attributed to this.

Examples:

```bash
swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm --target Core
swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm --package-path Runners/TerminalUIWASI --target TerminalUIWASI
swiftly run swift build --swift-sdk swift-6.3-RELEASE_wasm -c release -Xlinker --initial-memory=536870912 -Xlinker --max-memory=4294967296 -Xlinker -z -Xlinker "stack-size=1048576"
```

`GUI/WebTUIGUI` build scripts use `swiftly` directly, so require a 
swiftly-managed Swift 6.3.0 toolchain.
Install Swiftly before invoking `bun` if required.

```
curl -L https://download.swift.org/swiftly/darwin/swiftly.pkg > swiftly.pkg
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
~/.swiftly/bin/swiftly init
swiftly install --use 6.3
```

## Bun

`GUI/WebTUIGUI` uses Bun for all package management, test, and bundling work.

Examples:

```bash
cd GUI/WebTUIGUI
bun test
bun run build -- --app <AppProduct>
```

## Xcode

Xcode remains a valid native build path.

In particular, the outer macOS or iOS app build still works fine in Xcode when
a consumer embeds `GUI/SwiftUITUIGUI` in an application target.

That does not change the package-development rule for this repository:

- use the `swiftly`-managed Swift 6.3.0 toolchain for package builds, tests,
  DocC generation, and wrapper verification
- Xcode is also acceptable for native-only build and run work, but it is not
  the default documented path for repo-wide package development

## Android

Android cross-compilation also uses Swift 6.3.0 from `swiftly`, plus the Swift
Android SDK and Android NDK described in [ANDROID.md](ANDROID.md).
