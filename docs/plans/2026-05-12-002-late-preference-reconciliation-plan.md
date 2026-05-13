---
title: "refactor: late preference reconciliation"
type: refactor
status: active
date: 2026-05-12
depends_on:
  - "2026-05-01-001-layout-dependent-content-realization-plan.md"
  - "2026-05-01-002-public-anchor-geometry-preferences-plan.md"
  - "../proposals/ACTION_SCOPES_AND_COMMANDS.md"
---

# refactor: late preference reconciliation

## Overview

Fix the platform-level phase-ordering gap where preference producers inside
layout-dependent content are realized after resolve-time preference consumers
have already run.

The immediate user-visible failure is the WebExample Demo Details scene:
`.toolbarItem(...)` is authored inside `GeometryReader`, while the enclosing
`.toolbar(style:)` reads `ToolbarItemsPreferenceKey` during resolve. Because
`GeometryReader` content is realized during placement, the toolbar host sees no
items and the bottom toolbar is never synthesized.

This should not become a WebExample workaround. SwiftTUI is still
pre-production, so the preferred fix is a coherent platform contract even if it
requires internal breaking changes.

## Current State

- `GeometryReader` and other layout-dependent boundaries realize authored
  content during placement from actual bounds, safe-area insets, coordinate
  spaces, and host metrics.
- Ordinary preferences reduce during resolve.
- `overlayPreferenceValue`, `backgroundPreferenceValue`, and
  `.toolbar(style:)` consume reduced preferences during resolve.
- `ToolbarModifier` composes toolbar chrome only when its initially resolved
  subtree already carries `ToolbarItemsPreferenceKey` values.
- The runtime applies layout-dependent realizations to the resolved tree after
  layout, then commits that realized tree.
- Runtime diagnostics for unhosted toolbar items currently inspect the
  pre-realization tree, so late toolbar items can fail silently.

## Problem Frame

The existing pipeline is correct for geometry, but incomplete for preference
consumers:

```text
resolve -> measure -> place -> apply layout-dependent realizations -> commit
```

Preference consumers that structurally modify the tree currently run only in
the first phase:

```text
resolve preferences -> consume preferences -> measure/place -> late producers appear
```

That leaves no platform point where the tree can say: layout has selected and
realized the content that truly participates in this frame; now reconcile any
preferences that only became visible through that realization.

The fix must preserve the layout-dependent content contract: measuring or
discarding unselected content must not publish lifecycle, semantic, command,
drop, focus, gesture, or toolbar side effects.

## Platform Contract

Preferences emitted by realized, committed layout-dependent content must be
visible to enclosing preference consumers as if that content had been available
during ordinary resolve.

Only realized content participates. Measurement-only candidates, unselected
`ViewThatFits` branches, and non-committed layout probes must not leak side
effects into the reconciled frame.

When a reconciled preference consumer changes structure or safe area, the frame
must re-run the affected layout tail so geometry-dependent content sees the
final available size, not the pre-toolbar/pre-overlay size.

## Requirements

- R1. Render toolbar items authored inside realized `GeometryReader` content
  under an enclosing `.toolbar(style:)`.
- R2. Keep toolbar absorption semantics: items land in the nearest ancestor
  `ActionScope` that declares a toolbar and are cleared there.
- R3. Preserve the retained-toolbar invariant: the real `ActionScope` node
  remains the scope/focus root, and synthesized toolbar content lives in a
  committed child subtree.
- R4. Add diagnostics for late unhosted toolbar items so missing hosts are
  observable after layout-dependent realization.
- R5. Avoid restoring resolve-time geometry shims or eager `GeometryReader`
  evaluation.
- R6. Avoid committing side effects from unselected or measurement-only
  layout-dependent content.
- R7. Keep async ordered commit and main-actor fallback diagnostics coherent
  when a second layout pass is required.
- R8. Leave an internal seam that can later support
  `overlayPreferenceValue`, `backgroundPreferenceValue`, and other structural
  preference consumers without another one-off pipeline branch.

## Non-goals

- Do not change the public `PreferenceKey` API in this tranche.
- Do not ship a public late-preference API.
- Do not special-case WebHost, WASI, browser sizing, or the Demo Details scene.
- Do not make `GeometryReader` content influence ancestor measurement.
- Do not attempt a full arbitrary fixpoint solver unless the toolbar tranche
  proves a single reconciliation pass cannot be made deterministic.

## Architecture

Add a post-realization preference reconciliation phase:

```text
resolve
measure/place
apply layout-dependent realizations
recompute preferences over the realized tree
run late preference consumers
if structure or safe area changed: measure/place the reconciled tree once
semantics/draw/raster/commit
```

The first consumer is toolbar hosting. The implementation can start with a
toolbar-specific internal descriptor, but it should live behind a general
internal reconciliation entry point so preference overlays and backgrounds have
a natural migration path.

The toolbar reconciler should reuse the existing toolbar composition behavior
rather than creating a parallel toolbar renderer. The output should be a
resolved tree whose committed shape is the same shape an ordinary resolve-time
toolbar host would have produced.

## Implementation Stages

### Stage 1: Characterize and diagnose

- Add a failing or red-first test proving a toolbar item inside realized
  `GeometryReader` content does not currently render under an enclosing
  toolbar host.
- Add or move runtime diagnostics so late unhosted toolbar items are detected
  after `applyingLayoutDependentRealizations(...)`.
- Cover both synchronous and async frame paths if diagnostics are collected in
  both.

### Stage 2: Introduce the reconciliation seam

- Add an internal post-realization reconciliation function that accepts a
  realized `ResolvedNode` tree plus the context needed to rebuild structural
  consumers.
- Recompute preferences after applying layout-dependent realizations.
- Return both the reconciled tree and a flag describing whether a second layout
  tail is required.
- Keep the entry point private or package-internal until more than one consumer
  needs it.

### Stage 3: Reconcile toolbar hosts

- Teach `.toolbar(style:)` to leave enough internal host metadata for the
  reconciler to run after layout-dependent realization.
- When late `ToolbarItemsPreferenceKey` values reach a toolbar host, synthesize
  the same committed toolbar subtree that resolve-time hosting creates.
- Clear absorbed toolbar preferences so items do not bubble past their nearest
  host.
- Preserve `ActionScope` identity, focus, and retained-frame behavior.

### Stage 4: Re-layout when chrome changes geometry

- If reconciliation adds toolbar chrome or changes safe-area ignoring, run the
  layout tail again before semantics/draw/raster/commit.
- Ensure geometry-dependent toolbar titles, overlays, and content sizes settle
  against the final available bounds.
- Bound the process to a deterministic one-reconciliation pass for this tranche,
  with diagnostics if another pass would be required.

### Stage 5: Update docs and examples

- Update architecture/runtime docs to state that realized layout-dependent
  preferences are reconciled before commit.
- Mark this plan shipped and update `docs/README.md`, `docs/TODO.md`, and
  `docs/CHANGELOG.md`.
- Leave the WebExample Demo Details scene authored naturally with
  `.toolbarItem(...)` inside `GeometryReader`.

## Acceptance Criteria

- Demo Details in the WebExample displays its bottom toolbar when selected.
- The toolbar title reflects the final browser/window-backed geometry after
  toolbar chrome is accounted for.
- A toolbar item inside a realized `GeometryReader` is absorbed by the nearest
  toolbar host.
- A toolbar item inside unselected layout-dependent content does not render or
  register side effects.
- Late unhosted toolbar items produce the same runtime issue as ordinary
  unhosted toolbar items.
- Existing toolbar, preference, geometry, presentation, and async frame-tail
  tests remain green.

## Verification

Focused checks:

```bash
swiftly run swift test --filter 'SwiftTUITests\.(ToolbarTests|PreferenceSurfaceTests|AnchorPreferenceSurfaceTests|GeometryReaderSurfaceTests|ViewThatFitsSurfaceTests|PresentationSurfaceTests|AsyncFrameTailRenderingTests)'
```

WebExample checks:

```bash
cd Examples/WebExample
bun test
bun run build:dev
bun run test:browser
```

Final gate:

```bash
bun run test
```

If the final gate fails for unrelated pre-existing baseline drift, record the
failing command and keep focused validation evidence for the changed surface.

## Risks

- A second layout pass can change geometry-dependent titles or content. That is
  required for correctness, but the implementation must avoid unbounded loops.
- Type-erased toolbar style metadata may need an internal wrapper. Prefer a
  local internal break over duplicating toolbar rendering code.
- Async frame-tail ownership must stay explicit: arbitrary layout-dependent
  authored content already forces main-actor layout, and reconciliation should
  not hide that fallback.
- Preference overlays/backgrounds are likely affected by the same architecture
  gap. This tranche should leave the seam ready for them, but not silently
  claim they are fixed until covered by tests.

## Open Follow-ups

- Decide whether `overlayPreferenceValue` and `backgroundPreferenceValue` move
  to the same reconciliation seam immediately after toolbar lands.
- Decide whether reconciliation counts should become public frame diagnostics
  or stay internal until more consumers use the phase.
