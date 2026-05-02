---
title: "audit: layout-dependent container geometry assumptions"
type: fix
status: shipped
date: 2026-05-01
depends_on:
  - "2026-05-01-001-layout-dependent-content-realization-plan.md"
  - "2026-05-01-002-public-anchor-geometry-preferences-plan.md"
---

# audit: layout-dependent container geometry assumptions

## Scope

This audit covers the remaining measurement-dependent containers called out
after public anchor geometry shipped:

- `safeAreaInset`
- `ScrollView`
- `ViewThatFits`
- `LazyVStack` / `LazyHStack`
- public and internal custom `Layout`

The question is whether any of these containers still depend on resolve-time
local-geometry guesses, especially the old pattern where content saw
`EnvironmentValues.terminalSize` as if it were local proposal geometry.

The audit intentionally separates three concerns:

- local size and coordinate-space geometry visible through `GeometryProxy`,
- safe-area and terminal-capability environment values that are still captured
  at resolve time,
- side-effect commitment from subtrees that layout later discards or keeps lazy.

## Current Finding

No audited container still rewrites or relies on `EnvironmentValues.terminalSize`
as its local geometry bridge. The active local-geometry path is:

```text
resolve:
  GeometryReader emits LayoutDependentContentBoundary

measure:
  boundary reports its sizing policy without realizing authored content

place:
  LayoutRealizationContext carries final bounds, safe-area data, cell metrics,
  pointer capabilities, and the current PlacedFrameTable

realize:
  GeometryProxy is built from LayoutRealizationContext, then authored content
  resolves under the finalized geometry
```

The remaining risks are not broad resolve-time size bugs. They are narrower
contract and coverage gaps:

- safe-area inset content currently receives placement geometry, but the exact
  safe-area environment semantics for base versus inset subtrees are not locked
  by a `GeometryReader`-inside-`safeAreaInset` test.
- `ScrollView` and lazy stacks route viewport placement through layout, but
  geometry coverage is heavier on rendering, semantics, and retained-anchor
  reuse than on direct `GeometryReader` probes inside scroll/lazy combinations.
- `ViewThatFits` correctly avoids realizing unselected layout-dependent
  candidates, but selected-candidate geometry and anchor/coordinate-space
  behavior are only indirectly covered.
- custom `Layout` handles proposal/placement through `LayoutSubview`, but
  public documentation should be explicit that non-`SendableLayout` custom
  layouts and any layout-dependent child realization keep layout on the main
  actor.

## Cross-Cutting Evidence

`GeometryReader` is now the only public view in this family that produces a
layout-dependent boundary. It does not resolve authored content immediately.
Instead, `GeometryReader.resolveElements(in:)` records a
`LayoutDependentContentBoundary` with a `10x10` unspecified-dimension ideal,
and `GeometryReaderLayoutDependentContent.realize(in:)` builds a
`GeometryProxy` from `LayoutRealizationContext.bounds`.

`LayoutRealizationContext` includes:

- `proposal`
- `bounds`
- `safeAreaInsets`
- `cellPixelMetrics`
- `pointerInputCapabilities`
- `placedFrameTable`

`LayoutEngine.place(...)` records every computed placement into the pass
context before placing children. When a retained placement is reused, it walks
that retained subtree and records those frames too. This is the important
anchor and coordinate-space hardening point: geometry resolution does not
depend on only the freshly computed placement path.

Frame diagnostics now expose both layout-dependent realization counts and
geometry-resolution diagnostics, so future container regressions can be found
from rendered frames instead of requiring debugger-only inspection.

## Container Audit

### `safeAreaInset`

Implementation path:

- `SafeAreaInsetModifier.resolve(...)` resolves base and inset subtrees as
  children of a `ResolvedNode` whose behavior is `.safeAreaInset(...)`.
- `LayoutEngine.measureChildren(...)` measures the inset first, derives
  consumed insets from measured inset size, spacing, and the current safe area,
  and measures base content with the reduced proposal.
- `LayoutEngine.childPlacements(...)` places base and inset into their computed
  bounds.

Geometry result:

- A `GeometryReader` inside either base or inset remains deferred until its
  child placement is known, so `proxy.size`, `proxy.frame(in:)`, and anchor
  resolution use the measured/placed bounds rather than resolve-time terminal
  size.

Current coverage:

- `SafeAreaSurfaceTests` covers root safe-area geometry, `safeAreaPadding`,
  `ignoresSafeArea`, and `safeAreaInset` placement.

Gap:

- There is no direct test that puts `GeometryReader` inside the base and inset
  branches of `safeAreaInset` and asserts the proxy size plus safe-area insets.
  This matters because `SafeAreaInsetModifier` currently records the original
  safe-area environment on both subtrees while layout separately computes base
  consumption. That may be the intended terminal-native contract, but it should
  be explicit.

Recommended next test:

- Add a `SafeAreaSurfaceTests` case with top and bottom inset variants:
  - inset branch `GeometryReader` should see its placed inset bounds,
  - base branch `GeometryReader` should see the reduced base bounds,
  - expected `proxy.safeAreaInsets` should be documented in the assertion name.

### `ScrollView`

Implementation path:

- `ScrollView.resolveElements(in:)` resolves content once under a stored
  authoring scope and installs a `ScrollViewLayout`.
- `ScrollViewLayout` measures content with an unspecified dimension on any
  scrolling axis and places content at `viewportBounds.origin - clampedOffset`.
- The placed child receives a `viewportContext`, which is later consumed by lazy
  stacks and semantic scroll-route extraction.

Geometry result:

- `GeometryReader` content inside a scroll view is still realized during
  placement, so local size and anchor resolution follow the scroll layout's
  actual content placement.
- Anchor resolution under scroll translation has explicit regression coverage:
  a retained scroll-position update changes the resolved anchor frame from
  `anchor=0,2` to `anchor=0,1` without recording a geometry miss.
- Named coordinate spaces under retained scroll translation have equivalent
  coverage: the named frame moves from `space=0,-2` to `space=0,-1` without a
  missing or duplicate coordinate-space diagnostic.

Current coverage:

- `SwiftUISurfaceTests` covers scroll viewport size, content bounds, pointer
  scrolling, lazy content clipping, and retained layout behavior.
- `AnchorPreferenceSurfaceTests` covers retained scroll translation for anchors
  and named coordinate spaces.

Gap:

- There is no narrow `GeometryReader`-only test that asserts proxy size and
  `frame(in: .global)` inside a scrolled `ScrollView` independent of anchors.
  The anchor tests exercise the same placed-frame table, but a direct proxy test
  would make scroll-local geometry easier to diagnose.

Recommended next test:

- Add a focused scroll geometry test where a vertical `ScrollView` contains a
  `GeometryReader` row, then render before and after scrolling. Assert:
  - proxy size matches the content proposal for the non-scrolling axis and the
    expected scroll-axis ideal,
  - `frame(in: .global).origin.y` shifts by the scroll offset,
  - no geometry-resolution diagnostics are recorded.

### `ViewThatFits`

Implementation path:

- `ViewThatFits.resolveElements(in:)` resolves candidates as ordinary children
  and records `.viewThatFits(axes)`.
- Measurement evaluates candidates under the parent proposal to choose a
  selected child index.
- Placement commits only the selected child.

Geometry result:

- Unselected `GeometryReader` candidates are measured through boundary sizing
  only; their authored content is not realized and does not commit lifecycle,
  task, gesture, semantic, command, drop, or geometry side effects.
- The selected candidate is placed normally, so any layout-dependent content
  inside the selected subtree realizes from the selected child's final bounds.

Current coverage:

- `ViewThatFitsSurfaceTests` asserts unselected `GeometryReader` content is not
  realized and diagnostics record zero layout-dependent realizations.
- `SwiftUISurfaceTests` covers candidate selection by width and verifies only
  the chosen placed child remains in the placed tree.

Gap:

- There is no direct test where the selected candidate contains a
  `GeometryReader` or anchor preference and the unselected candidates also
  contain geometry-dependent content. This would lock both sides of the
  contract in one place.

Recommended next test:

- Add a `ViewThatFitsSurfaceTests` case with:
  - an unselected wide candidate whose `GeometryReader` increments a counter,
  - a selected narrow candidate whose `GeometryReader` renders its placed size,
  - assertions that the counter only includes the selected realization and that
    the raster contains the selected geometry.

### Lazy Stacks

Implementation path:

- `LazyVStack` and `LazyHStack` either resolve eager children or install an
  `IndexedChildSource` for a single data-backed child source such as `ForEach`.
- Lazy stack measurement computes child allocation snapshots and content
  lengths.
- Lazy stack placement uses `viewportContext` to place only the visible range
  for scroll-hosted stacks.

Geometry result:

- Eager lazy-stack children behave like ordinary stack children and
  `GeometryReader` content realizes at placement.
- Indexed lazy-stack children are resolved when `source.child(at:)` is called.
  In scroll-hosted placement, only visible children are materialized for
  placement, which prevents off-screen side effects from leaking through the
  placed tree.
- The frame-tail worker path snapshots indexed children before worker layout
  when safe, and blocks worker layout when an indexed child contains a
  main-actor-only custom layout.

Current coverage:

- `ViewResolutionTests` covers eager versus single-`ForEach` indexed resolution.
- `SwiftUISurfaceTests` covers eager/lazy raster parity, viewport clipping,
  lifecycle stability while scrolling, and focus/interaction scoping.
- `AsyncFrameTailRenderingTests` covers worker snapshotting for indexed lazy
  content and main-actor fallback when an indexed child contains
  main-actor-only custom layout.

Gap:

- There is no direct lazy-stack test with a visible `GeometryReader` row and an
  off-screen `GeometryReader` row that asserts only the visible row realizes.
  The existing lifecycle and focus tests cover side-effect scoping, but not
  layout-dependent realization counts for geometry rows.

Recommended next test:

- Add a lazy-stack geometry realization test under `SwiftUISurfaceTests` or a
  new focused surface suite:
  - a scroll-hosted `LazyVStack` with two `GeometryReader` rows,
  - viewport height that shows only one row,
  - assertion that the raster contains only the visible geometry row and
    `layoutDependentRealizations == 1`.

### Custom `Layout`

Implementation path:

- Public `Layout` subviews measure through `LayoutSubview.sizeThatFits(...)`
  and place through `LayoutSubview.place(at:anchor:proposal:)`.
- `LayoutProxyBox` and `SendableLayoutWorkerProxy` pass the active
  `LayoutPassContext` into child measurement and placement, so
  layout-dependent boundaries under custom layouts still realize from the
  placement proposal and bounds chosen by the layout.
- Non-`SendableLayout` custom layouts remain main-actor-only. `SendableLayout`
  can run on the frame-tail worker when its subtree is worker-compatible.

Geometry result:

- A child `GeometryReader` inside custom `Layout` sees the placement proposal,
  not a measurement probe. This is covered by a custom layout that measures
  under `4x1` and places under `9x3`; the rendered geometry is `9x3`.
- Repeated child measurement does not repeatedly realize `GeometryReader`
  content; realization is placement-bound and cached by
  `LayoutDependentContentSignature`.

Current coverage:

- `GeometryReaderSurfaceTests` covers custom layout placement proposal and
  repeated measurement.
- `AsyncFrameTailRenderingTests` covers ordinary custom layout fallback,
  `SendableLayout` worker execution, dimensions/alignment-guide reads on the
  worker, retained layout reuse across draw-only async frames, and focus-sync
  convergence.
- `LayoutEngineTests` covers retained-layout eligibility for custom layouts:
  reuse is disabled unless measurement and placement reuse signatures are both
  present.

Gap:

- The public docs describe custom layout broadly, but they do not spell out the
  geometry contract clearly enough for authors:
  - `LayoutSubview.place(... proposal:)` is the geometry that a child
    `GeometryReader` sees.
  - Measuring a child `GeometryReader` is a sizing probe, not content
    realization.
  - `SendableLayout` eligibility can be lost if the subtree contains arbitrary
    layout-dependent content requiring main-actor realization.

Recommended doc update:

- Add a custom-layout subsection to `Sources/View/View.docc/Geometry-And-Preferences.md`
  or `docs/SWIFTUI_LAYOUT.md` explaining the measure/place split and
  frame-tail worker implication.

## Pipeline-Split Consequences

The container audit supports keeping the next pipeline split conservative:

- Keep layout-dependent realization inside `place`, not `measure`.
- Keep async frame-tail layout worker eligibility blocked by unresolved
  layout-dependent boundaries unless a future snapshot contract can prove the
  content is worker-safe.
- Keep `ViewThatFits` non-retained for placement reuse because selected-child
  identity depends on the current proposal and measurement result.
- Keep indexed lazy stacks as a special lazy placement path; do not generalize
  them into eager child arrays merely to simplify geometry tests.

## API-Usability Consequences

The public API should continue to steer authors away from local geometry via
environment values:

- `EnvironmentValues.terminalSize` is root/host metadata only.
- `GeometryProxy.size`, `GeometryProxy.frame(in:)`, and
  `GeometryProxy[anchor]` are the local geometry APIs.
- For custom layouts, `LayoutSubview.place(... proposal:)` is the child-local
  geometry contract.
- Missing named coordinate spaces and unresolved anchors are deterministic
  fallbacks with diagnostics, not silent layout guesses.

## Follow-Up Checklist

Recommended next tests, in priority order:

1. `safeAreaInset` base/inset `GeometryReader` proxy-size and safe-area
   semantics.
2. `ViewThatFits` selected-versus-unselected layout-dependent realization in
   one focused test.
3. Scroll-local `GeometryReader.frame(in: .global)` before and after scroll.
4. Lazy indexed `GeometryReader` visible-row-only realization count.
5. Custom `Layout` documentation for measure probes, placement proposals, and
   frame-tail worker eligibility.

None of these require reopening the old resolve-time `terminalSize` bridge.
They are hardening and documentation tasks around the already-shipped
placement-time seam.

## Verification Surface

Focused commands that exercise this audit family:

```bash
swiftly run swift test --filter SwiftTUITests.SafeAreaSurfaceTests
swiftly run swift test --filter SwiftTUITests.ViewThatFitsSurfaceTests
swiftly run swift test --filter SwiftTUITests.GeometryReaderSurfaceTests
swiftly run swift test --filter SwiftTUITests.AnchorPreferenceSurfaceTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests
swiftly run swift test --filter CoreTests.LayoutEngineTests
```

Use `bun run test` after implementing any shared Core/View/SwiftTUI change.
For documentation-only edits, `git diff --check` is sufficient.

## Audit Verification

Commands run for this audit on 2026-05-01:

```bash
git diff --check
swiftly run swift test --filter 'SwiftTUITests\.(SafeAreaSurfaceTests|ViewThatFitsSurfaceTests|GeometryReaderSurfaceTests|AnchorPreferenceSurfaceTests|AsyncFrameTailRenderingTests)|CoreTests\.LayoutEngineTests'
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests
```

Results:

- Whitespace check passed.
- The focused geometry/container/engine filter passed: 84 tests in 6 suites.
- `SwiftUISurfaceTests` passed: 182 tests in 1 suite.

`bun run test` was not rerun because this audit made documentation-only
changes.
