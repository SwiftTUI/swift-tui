# Toolchains

This repository uses more than one build tool, but the default Swift workflow
for package development and verification is `swiftly` with Swift `6.3.1`.

## Swift

The repo pins Swift `6.3.1` in [`.swift-version`](../.swift-version).

Use `swiftly` for all repo-local SwiftPM work:

```bash
swiftly run swift build
swiftly run swift test
swiftly run swift package generate-documentation --target SwiftTUI
```

Do not run repo-local development tests with bare `swift test`, `xcrun swift
test`, or whichever Xcode-selected Swift binary happens to be on `PATH`. Those
commands can reuse incompatible build artifacts or compiler/runtime versions
after branch merges. Use the explicit `swiftly run swift ...` form so every
developer and CI-style local gate uses the pinned Swift `6.3.1` toolchain.

Do not use `xcrun swift` for the repo's package builds, tests, DocC generation,
or wasm packaging. `xcrun` may resolve to an Xcode-selected toolchain that does
not match the repo's pinned Swift 6.3.1 environment.

## macOS CI Floor

The public macOS development and CI support floor is macOS 26. GitHub Actions
jobs that validate macOS behavior use the `macos-26` runner label intentionally;
it is not just a transient hosted-runner choice. Older macOS hosts may still
build compatible package products when their Swift and Xcode tooling is new
enough, but the release gate does not treat those hosts as supported blockers.

## WASM

The wasm-facing package work also uses the same `swiftly`-managed Swift 6.3.1
toolchain, but with the wasm SDK selected through `--swift-sdk`.
Wasm builds of SwiftTUI apps will often require a stack size larger than the default.
Their starting and max memory can also be bumped - although no yet-known failures have been attributed to this.

Install the matching Swift 6.3.1 release wasm SDK with:

```bash
swiftly run swift sdk install https://download.swift.org/swift-6.3.1-release/wasm-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz --checksum bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2
```

Examples:

```bash
swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm --target SwiftTUICore
swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm --target SwiftTUIWASI
swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm -c release -Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass -Xlinker --initial-memory=536870912 -Xlinker --max-memory=4294967296 -Xlinker -z -Xlinker "stack-size=1048576"
```

`Platforms/Web` build scripts use `swiftly` directly, so require a
swiftly-managed Swift 6.3.1 toolchain.
Install Swiftly before invoking `bun` if required.

The Linux dev image and `Scripts/linux.sh` follow the same rule: built-in
Linux package builds and tests invoke Swift through `swiftly run swift ...`.

```
curl -L https://download.swift.org/swiftly/darwin/swiftly.pkg > swiftly.pkg
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
~/.swiftly/bin/swiftly init
swiftly install --use 6.3.1
```

## Bun

`Platforms/Web`, `Platforms/WebBuild`, and `Examples/WebExample` use Bun for all
package management, test, and bundling work.

Examples:

```bash
cd Platforms/Web
bun test
bun run build -- --app <AppProduct>

cd Platforms/WebBuild
bun test

cd Examples/WebExample
bun test
bun run build
```

## Xcode

Xcode remains a valid native build path.

In particular, the outer macOS or iOS app build still works fine in Xcode when
a consumer embeds the root package's `SwiftUIHost` product in an application
target.

That does not change the package-development rule for this repository:

- use the `swiftly`-managed Swift 6.3.1 toolchain for package builds, tests,
  DocC generation, and wrapper verification
- Xcode is also acceptable for native-only build and run work, but it is not
  the default documented path for repo-wide package development

## Worktrees

Example packages in this repository depend on the repo root via local path
dependencies and refer to that package as `swift-tui`.

When adding new local path dependencies that point back at this repo, prefer
the explicit form:

```swift
.package(name: "swift-tui", path: "../..")
```

That pins the package name used by downstream `.product(..., package:
"swift-tui")` references and keeps example packages working even when a
worktree directory is renamed.

For new git worktrees, still keep the final path component as
`swift-tui` when practical, for example:

```text
.../worktrees/<task>/swift-tui
```

That keeps local package identity, DerivedData naming, and ad hoc shell
tooling predictable across the repo.

## Android

Android cross-compilation also uses Swift 6.3.1 from `swiftly`, plus the Swift
Android SDK and Android NDK described in [ANDROID.md](ANDROID.md).
