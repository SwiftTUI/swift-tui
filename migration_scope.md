# Production Code Humanization Scope

## Approved Goal

Make the repo's production implementation more approachable to human
contributors. The work should improve readability, decomposition,
reviewability, testability, and long-term maintenance without changing behavior.

## Initial Focus

Begin with the primary SwiftTUI infrastructure supporting terminal rendering:

- `Sources/SwiftTUIRuntime/Terminal/`
- `Sources/SwiftTUIRuntime/Rendering/`
- `Sources/SwiftTUIRuntime/RunLoop/`
- `Sources/SwiftTUICore/Commit/`
- Minimal platform entrypoint call sites under `Platforms/CLI/Sources/SwiftTUICLI/`
  when needed to keep the terminal rendering path coherent.

The initial slice should target production code on the terminal presentation
path before moving outward to less central production areas.

## Current Constrained Focus

As of packet 126, remaining migration work is constrained to the central runtime
and primary core:

- `Sources/SwiftTUICore/`
- `Sources/SwiftTUIRuntime/`
- repo policy, migration, and validation artifacts needed to support those
  production changes

Previously completed view, chart, platform, tooling, and example-adjacent work
remains part of the historical migration record, but new packets should not
expand into `SwiftTUIViews`, `SwiftTUICharts`, `SwiftTUIAnimatedImage`,
`Platforms`, `Tools`, or examples unless needed to preserve validation or policy
artifacts for a central runtime/core move.

## Repo-Wide Scope

The broader migration may touch production code under:

- `Sources/`
- `Platforms/*/Sources/`
- `Tools/` only when directly supporting production validation or diagnostics.

Each implementation slice must declare its owned files before editing.

## Explicit Non-Goals

- Do not change the SwiftUI-like public API exposed to consumers.
- Do not change example apps under `Examples/`.
- Do not change tests except where necessary to preserve or strengthen
  characterization of the touched production behavior.
- Do not make stylistic churn whose primary purpose is authorship masking.
- Do not remove provenance, review notes, or audit artifacts.
- Do not introduce new runtime risk, weaker validation, broader mutable state,
  or less explicit concurrency behavior.

## Stable Behavior and Interfaces

These must remain stable unless a later human checkpoint explicitly approves a
behavior or public-contract change:

- Public SwiftTUI, SwiftTUIRuntime, SwiftTUIViews, SwiftTUICharts, and
  SwiftTUIAnimatedImage APIs.
- Terminal byte output semantics for existing renderers and capability profiles.
- Rendering pipeline phase ordering and `FrameArtifacts` contracts.
- Run-loop frame acquisition, frame-drop, commit, lifecycle, focus, cursor, and
  accessibility behavior.
- Terminal raw-mode, alternate-screen, mouse-reporting, bracketed-paste, and
  process-exit cleanup behavior.
- Existing tests, fixtures, policy checks, and public API baselines.

## Validation Bar

Use the pinned toolchain only:

- `swiftly run swift ...`
- `bun run test` as the required repo gate after shared runtime, platform,
  production, or tooling changes.

For terminal rendering slices, run focused checks first, then the broader gate.
Clean derived build artifacts when incremental Swift build state appears stale
or crash-prone.

## Deployment Context

This is a Swift package with published library products, platform host products,
CLI entrypoints, and supporting web/host surfaces. The terminal rendering path
is shared infrastructure and should be treated as high-risk production code.

## Branch and Tickets

- Branch: `main`
- Ticket/issue: none provided

## Risk Register

| Risk | Severity | Approval Requirement |
| --- | --- | --- |
| Public API/source-compatibility drift | High | Human approval before change |
| Terminal output or capability-probe behavior drift | High | Human approval before intentional behavior change |
| Run-loop lifecycle or frame-drop behavior drift | High | Human approval before intentional behavior change |
| Concurrency/isolation weakening | High | Not allowed |
| Fixture churn without intentional rendering change | Medium | Human approval before updating fixtures |
| Broad test edits masking regressions | High | Not allowed |
| Example-app changes | Medium | Out of scope |

## Approval Checklist

- [x] Repo-wide production-code goal approved.
- [x] Public API changes excluded.
- [x] Example-app changes excluded.
- [x] Testing bar must remain high.
- [x] Initial focus set to terminal rendering infrastructure.
- [x] First implementation packet selected from evidence.
- [x] Baseline validation recorded.
