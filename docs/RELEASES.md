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

## License

SwiftTUI first-party code is released under the GNU Affero General Public
License v3.0 only (`AGPL-3.0-only`). Third-party source under `Vendor/` keeps
the original upstream license terms recorded beside each vendored component.

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

Organization-admin bypass is intentionally left enabled as maintainer policy.
This keeps a single accountable maintainer able to repair stuck automation,
recover from misconfigured rulesets, and land urgent release or security fixes
without first weakening the repository rules for everyone. Admin bypasses should
remain exceptional and should still land as signed, linear commits that pass the
release gate before tagging.

The goal for the `0.9.0` public beta line is to add more contributors and
stabilize any remaining API surface needed to provide a SemVer-compatible
`1.0.0` release as soon as safely possible. That beta milestone does not by
itself require removing the admin bypass.

## Platform Support

The root package declares macOS 15+ and iOS 18+ package platforms, but the
public macOS development and CI support floor is macOS 26. GitHub Actions
`macos-26` is the supported macOS gate environment; older macOS hosts may work
when they provide compatible Swift and Xcode tooling, but failures there are not
release blockers. Local development is primarily macOS with Swift 6.3.1 managed
by `swiftly`; Linux and WASI paths are supported through the documented package
and script entrypoints.

`SwiftTUITerminal` and `SwiftTUIPTYPrimitives` are macOS/Linux products and are
not available for iOS or WASI. Browser runtime packages live in
`Platforms/Web` and `Platforms/WebBuild`.

## Publishing Notes

The historical `0.0.1` tag predates this release policy and should not be used
as consumer guidance. The first release that follows this policy is `0.1.0`.
