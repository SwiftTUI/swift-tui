# Documentation

Last updated: April 5, 2026

This directory holds the project-internal reference set: architecture notes,
runtime rules, source ownership, API governance, and retained design records.
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
- `Sources/TerminalUICharts/TerminalUICharts.docc`: public module overview for `TerminalUICharts`
- `Sources/Core/Core.docc`: target-level reference for the shared pipeline types re-exported through `TerminalUI`

Peer platform integration packages live at:

- `Runners/TerminalUICLI`
- `Runners/TerminalUIWASI`
- `GUI/SwiftUITUIGUI`
- `GUI/WebTUIGUI`

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
- [STATE_KEYING.md](STATE_KEYING.md): retained-graph state-keying rules and their interaction with authored view identity

## Platform Integration Docs

- [../TUIGUI.md](../TUIGUI.md): host-package architecture and current status for `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI`
- [ANDROID.md](ANDROID.md): Android cross-compilation notes for the Swift package targets

## Product Direction And Scope

- [VISION.md](VISION.md): philosophy, scope, intentional deviations, and deferred items
- [STATUS.md](STATUS.md): what is implemented today versus still intentionally missing
- [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md): terminal-native design principles and public-surface framing
- [TERMINAL_NATIVE_ROADMAP.md](TERMINAL_NATIVE_ROADMAP.md): roadmap record for the terminal-native reset and what remains open

## Reference Material

- [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md): the SwiftUI layout model this package aims to match
- [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md): external reference mapping for TUI concepts versus SwiftUI concepts
- [TERMINAL_NATIVE_UI_RESEARCH.md](TERMINAL_NATIVE_UI_RESEARCH.md): ecosystem research that informed the terminal-native direction
- [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md): workflow and shell-pattern research for terminal-native UX

## Active Design Work

- [ASYNC_PRESENTATION.md](ASYNC_PRESENTATION.md): proposal for moving terminal writes off the main actor
- [COLOR_ANIMATION_IMPLEMENTATION_PLAN.md](COLOR_ANIMATION_IMPLEMENTATION_PLAN.md): proposed animation subset for terminal-safe color transitions
- [TYPE_ERASURE_DEFERRAL_PLAN.md](TYPE_ERASURE_DEFERRAL_PLAN.md): remaining `AnyView` reduction work and long-term genericization options

## Historical Records

- [ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md): March 2026 architecture audit after the source split
- [REFACTOR_PLAN.md](REFACTOR_PLAN.md): follow-up ledger from that architecture audit
- [GRAPH_MIGRATION.md](GRAPH_MIGRATION.md): completed persistent-graph migration record
- [THEME_MIGRATION_PLAN.md](THEME_MIGRATION_PLAN.md): landed theme-only styling architecture record across runtime and wrappers
- [TOOLBAR_IMPLEMENTATION_PLAN.md](TOOLBAR_IMPLEMENTATION_PLAN.md): landed toolbar implementation record covering keyboard-help API removal
- [`plans/`](plans): dated implementation plans retained for larger refactors such as the runner-package split

## API Governance

- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): guardrails for future API additions and documentation drift
