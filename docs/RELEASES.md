# Release Policy

SwiftTUI is currently in the `0.x` alpha line. Tags are intended to be usable by
external SwiftPM consumers, but pre-1.0 minor releases may include source
breaks when the public surface is still being proven.

## Versioning

- Release tags use plain semver names such as `0.1.0`.
- Consumers should depend on the latest real release tag or a SwiftPM range,
  not `branch: "main"`.
- For the current alpha line, prefer:

```swift
.package(
  url: "https://github.com/GoodHatsLLC/SwiftTUI",
  .upToNextMinor(from: "0.1.0")
)
```

## Release Gate

A release tag should point at a clean commit that has passed:

- `bun run test`
- `Scripts/generate_public_api_inventory.sh --check`
- current README and website install snippets
- a concise `docs/CHANGELOG.md` entry
- license, security, and contribution files present at the repo root

Use `bun run test:all` for releases that materially affect example packages
beyond `Examples/gallery`, browser/WASI packaging, or cross-platform host
behavior.

## Branch Protection And Beta Hardening

`main` is protected by a repository ruleset. The rule should require the repo's
CI checks, block branch deletion and non-fast-forward updates, require signed
commits and linear history, and require pull request review before merges.

Organization-admin bypass is intentionally left enabled during the alpha line.
The project will revisit that bypass at `0.9.0`, which is planned as the first
public beta release. The goal for the beta line is to add more contributors and
stabilize any remaining API surface needed to provide a SemVer-compatible
`1.0.0` release as soon as safely possible.

## Platform Support

The root package declares macOS 15+ and iOS 18+ package platforms. Local
development is primarily macOS with Swift 6.3.1 managed by `swiftly`; Linux and
WASI paths are supported through the documented package and script entrypoints.

`SwiftTUITerminal` and `SwiftTUIPTYPrimitives` are macOS/Linux products and are
not available for iOS or WASI. Browser runtime packages live in
`Platforms/Web` and `Platforms/WebBuild`.

## Publishing Notes

The historical `0.0.1` tag predates this release policy and should not be used
as consumer guidance. The first release that follows this policy is `0.1.0`.
