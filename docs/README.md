# Documentation

Last updated: March 26, 2026

This directory holds the project-internal reference set: architecture notes, runtime rules, source ownership, and API governance. Public-facing module documentation now also lives in per-target `*.docc` catalogs under `Sources/`.

## Read This First

- [STATUS.md](STATUS.md): the current shipped surface, known constraints, and short-term gaps
- [ARCHITECTURE.md](ARCHITECTURE.md): package boundaries and the end-to-end frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime, lifecycle, state, observation, and incremental-present behavior

## Public Documentation Surfaces

- [../README.md](../README.md): public landing page for the repository
- `Sources/Core/Core.docc`: public module overview for `Core`
- `Sources/View/View.docc`: public module overview for `View`
- `Sources/TerminalUI/TerminalUI.docc`: public module overview for `TerminalUI`
- `Sources/TerminalUIScenes/TerminalUIScenes.docc`: public module overview for `TerminalUIScenes`
- `Sources/TerminalUICharts/TerminalUICharts.docc`: public module overview for `TerminalUICharts`

Generate DocC archives with the Xcode-selected toolchain:

```bash
xcrun swift package generate-documentation --target TerminalUI
```

When multiple Swift toolchains are installed, prefer `xcrun swift` over a bare `swift` invocation so parsing and symbol-graph generation stay aligned with the Xcode-selected compiler.

## Runtime And Implementation References

- [RUNTIME.md](RUNTIME.md): lifecycle or task semantics, state rules, environment rules, and incremental rendering behavior
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): ownership map across targets, key files, and support directories
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture, determinism, and regression-policy rules
- [FOCUS.md](FOCUS.md): focus traversal, focused values, and default-focus behavior

## Product Direction And Scope

- [VISION.md](VISION.md): philosophy, scope, intentional deviations, and deferred items
- [STATUS.md](STATUS.md): what is implemented today versus still intentionally missing

## API Governance

- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): guardrails for future API additions and documentation drift

## Reference Material

- [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md): the SwiftUI layout model this package aims to match
- [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md): external reference mapping for TUI concepts versus SwiftUI concepts
