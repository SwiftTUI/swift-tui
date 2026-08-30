# Contributing

> [!Note]
> SwiftTUI is currently a single-maintainer project, but new contributors are strongly desired and encouraged!
>
> All PRs and issues are welcome and will be replied to and triaged.
> 
> Please join the Discord server <https://discord.gg/8j35kYDFxn>  
> The maintainer will be available to talk through tooling and requirements.

## Development Setup

- Use the repository-pinned Swift toolchain through `swiftly run swift ...`, not bare `swift` or `xcrun swift`.
- Use the pre-commit hooks with [https://github.com/j178/prek](prek).
- Enforced code-styles are set in `.swift-format.json`.
- Please open issues to report tooling friction. Some tooling is not yet public and reports will help us prioritize this work.

## Pull Request Expectations

- Changes scoped to one behavior, subsystem, or documentation correction are most likely to land.
- If a public contract changes, update the documentation.
- If a product boundary or architectural behavior changes, update the same
  documentation.
- Include tests for each behavior change. A documentation-only change does not
  require tests. An existing gate can supply the required coverage.

