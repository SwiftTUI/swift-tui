# Documentation

Last updated: April 2, 2026

This directory holds the project-internal reference set: architecture notes,
runtime rules, planning status, source ownership, and API governance.
Public-facing module documentation also lives in per-target `*.docc` catalogs
under `Sources/`.

## Read This First

- [STATUS.md](STATUS.md): the current shipped surface, known constraints, and short-term gaps
- [ARCHITECTURE.md](ARCHITECTURE.md): package boundaries and the end-to-end frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime, lifecycle, state, observation, and incremental-present behavior
- [TOOLCHAINS.md](TOOLCHAINS.md): the supported Swift, wasm, Bun, Xcode, and Android toolchain story

## Public Documentation Surfaces

- [../README.md](../README.md): public landing page for the repository
- `Sources/View/View.docc`: public module overview for `View`
- `Sources/TerminalUI/TerminalUI.docc`: public module overview for `TerminalUI`
- `Sources/TerminalUIScenes/TerminalUIScenes.docc`: public module overview for `TerminalUIScenes`
- `Sources/TerminalUICharts/TerminalUICharts.docc`: public module overview for `TerminalUICharts`
- `Sources/Core/Core.docc`: target-level reference for the shared pipeline types re-exported through `TerminalUI`

Generate DocC archives with the repo-default `swiftly` toolchain:

```bash
swiftly run swift package generate-documentation --target TerminalUI
```

The shorter `swift package generate-documentation ...` form is also fine from a
shell where `swift` already resolves to the `swiftly`-managed Swift 6.3.0
toolchain. Xcode should still work for native-only workflows, but the repo's
default package-development documentation uses `swiftly`.

## Runtime And Implementation References

- [RUNTIME.md](RUNTIME.md): lifecycle and task semantics, state rules, environment rules, and incremental rendering behavior
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): ownership map across targets, key files, and support directories
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture, determinism, regression-policy, and test-topology rules
- [FOCUS.md](FOCUS.md): focus traversal, focused values, and default-focus behavior

## Planning And Audit Docs

- [ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md): refreshed architecture audit that distinguishes landed work from remaining debt
- [REFACTOR_PLAN.md](REFACTOR_PLAN.md): current follow-up plan after the March 2026 architecture audit
- [../TUIGUI.md](../TUIGUI.md): wrapper-package architecture and current status for `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI`
- [TERMINAL_NATIVE_ROADMAP.md](TERMINAL_NATIVE_ROADMAP.md): terminal-native product direction and the phases that already landed
- [TYPE_ERASURE_DEFERRAL_PLAN.md](TYPE_ERASURE_DEFERRAL_PLAN.md): status of deferred `AnyView` cleanup work
- [COLOR_ANIMATION_IMPLEMENTATION_PLAN.md](COLOR_ANIMATION_IMPLEMENTATION_PLAN.md): scoped visual-work plan that still stands apart from the core runtime roadmap
- [TOOLBAR_IMPLEMENTATION_PLAN.md](TOOLBAR_IMPLEMENTATION_PLAN.md): landed toolbar implementation record covering the new toolbar surface and keyboard-help API removal

## Product Direction And Scope

- [VISION.md](VISION.md): philosophy, scope, intentional deviations, and deferred items
- [STATUS.md](STATUS.md): what is implemented today versus still intentionally missing

## API Governance

- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): guardrails for future API additions and documentation drift

## Reference Material

- [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md): the SwiftUI layout model this package aims to match
- [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md): external reference mapping for TUI concepts versus SwiftUI concepts
