# Contributing

> [!Important]
> SwiftTUI is currently a single-maintainer pre-release project. I would be excited to get more people involved.  
> Expect some friction as the project's tooling currently lags its ambitions.
>
> Please join the discord if trying to land something non-trivial. https://discord.gg/8j35kYDFxn



## Development Setup

- Read [AGENTS.md](AGENTS.md) for repository-specific build, test, and style
  rules.
- Use the repo-pinned Swift toolchain through `swiftly run swift ...`; do not
  use bare `swift` or `xcrun swift` for repo-local builds.
- Use Bun from the root workspace for the standard test entrypoints.

```bash
bun run test
swiftly run swift test
```

Run `bun run test` before proposing shared runtime, platform product, or tooling
changes in this repo. Use `bun run test:all` when the change affects broad
primary-package behavior. Runnable examples are validated from the sibling
`SwiftTUI/swift-tui-examples` checkout.

## Pull Request Expectations

- Keep changes scoped to one behavior, subsystem, or documentation correction.
- Update the documentation in [`docs/`](docs/README.md) when a public contract,
  product boundary, or architectural behavior changes.
- Include tests for behavior changes unless the change is documentation-only or
  the validation path is already covered by an existing gate.

## Code Style

Swift code uses 2-space indentation and `.swift-format.json`. The repository
policy scripts are part of the gate; do not bypass them by weakening checks for
a local patch.
