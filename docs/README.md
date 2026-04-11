# Documentation

Last updated: April 11, 2026

This directory is the current-state documentation set for the repository.
Landed work that no longer changes decisions has been folded into the
surviving source-of-truth docs instead of being kept around as historical
roadmaps or superseded plans.

Public-facing module documentation also lives in per-target `*.docc` catalogs
under `Sources/`.

## Start Here

- [STATUS.md](STATUS.md): the current shipped surface, known constraints, and short-term gaps
- [ARCHITECTURE.md](ARCHITECTURE.md): package boundaries and the end-to-end frame pipeline
- [RUNTIME.md](RUNTIME.md): runtime, lifecycle, state, observation, and incremental rendering behavior
- [TOOLCHAINS.md](TOOLCHAINS.md): the supported Swift, wasm, Bun, Xcode, and Android toolchain story
- [../Scripts/test_all.sh](../Scripts/test_all.sh): the single repo-level test entrypoint, including Swift/Bun environment checks; also exposed as `bun run test` from the repo root

## Core References

- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): ownership map across targets, key files, and support directories
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture, determinism, regression-policy, and test-topology rules
- [FOCUS.md](FOCUS.md): focus traversal, focused values, and default-focus behavior
- [STATE_KEYING.md](STATE_KEYING.md): retained-graph state-keying rules and authored-view identity rules
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): guardrails for future API additions and documentation drift

## Platform Packages And Examples

- [HOST_PACKAGES.md](HOST_PACKAGES.md): runner-package and embedded-host packaging model
- [ANDROID.md](ANDROID.md): Android cross-compilation notes for the Swift package targets
- [../Examples/README.md](../Examples/README.md): the maintained example packages and apps in this repo

## Product Direction

- [VISION.md](VISION.md): philosophy, scope, intentional deviations, and deferred items
- [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md): terminal-native design principles and public-surface framing

## Active Proposals

- [proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md): proposal for moving terminal writes off the main actor
- [proposals/TYPE_ERASURE_DEFERRAL_PLAN.md](proposals/TYPE_ERASURE_DEFERRAL_PLAN.md): remaining `AnyView` reduction work and long-term genericization options
- [proposals/ANIMATION_PLAN.md](proposals/ANIMATION_PLAN.md): landed animation implementation record plus remaining context
- [proposals/ARCHITECTURE_NOTES.md](proposals/ARCHITECTURE_NOTES.md): view-graph and diffing improvement notes retained for future profiling-driven work
- [proposals/SHAPE_AND_BORDER_APIS.md](proposals/SHAPE_AND_BORDER_APIS.md): shape and border API redesign proposal

## Background Material

- [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md): the SwiftUI layout model this package aims to match
- [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md): external reference mapping for TUI concepts versus SwiftUI concepts
- [TERMINAL_NATIVE_UI_RESEARCH.md](TERMINAL_NATIVE_UI_RESEARCH.md): ecosystem research that informed the terminal-native direction
- [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md): workflow and shell-pattern research for terminal-native UX

## Public Documentation Surfaces

- [../README.md](../README.md): public landing page for the repository
- `Sources/View/View.docc`: public module overview for `View`
- `Sources/TerminalUI/TerminalUI.docc`: public module overview for `TerminalUI`
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
