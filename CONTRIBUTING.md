# Contributing

> [!Important]
> SwiftTUI is a single-maintainer pre-release project. New contributors are
> welcome. Some project tools are incomplete.
>
> For a large contribution, join the Discord server first:
> <https://discord.gg/8j35kYDFxn>

## Development Setup

- Read [AGENTS.md](AGENTS.md) for repository-specific build, test, and style
  rules.
- Use the repository-pinned Swift toolchain through `swiftly run swift ...`.
- Do not use bare `swift` or `xcrun swift` for repository builds.
- Use Bun from the root workspace for the standard test entrypoints.

```bash
bun run test
swiftly run swift test
```

Before you propose a shared runtime, platform product, or tooling change, run
`bun run test`. If the change affects broad primary-package behavior, run
`bun run test:all`. The sibling `SwiftTUI/swift-tui-examples` checkout contains
the tests for runnable examples.

## Pull Request Expectations

- Keep changes scoped to one behavior, subsystem, or documentation correction.
- If a public contract changes, update the documentation in
  [`docs/`](docs/README.md).
- If a product boundary or architectural behavior changes, update the same
  documentation.
- Include tests for each behavior change. A documentation-only change does not
  require tests. An existing gate can supply the required coverage.

## Code Style

Swift code uses 2-space indentation and `.swift-format.json`. Repository policy
scripts are part of the gate. Do not weaken these scripts for a local patch.
