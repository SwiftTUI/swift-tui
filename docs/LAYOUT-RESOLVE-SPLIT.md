# Layout/Resolve Split And GeometryReader

> Historical note: this document records the bug and the earlier bridge-based
> mitigation path. The shipped implementation now realizes layout-dependent
> `GeometryReader` content during placement, and `EnvironmentValues.terminalSize`
> is host-surface metadata rather than local proposal geometry.

## Summary

Before layout-dependent content realization, `GeometryReader` behaved like a
resolve-time environment reader, not like a layout-time proposal reader. Its
`GeometryProxy.size` was built from `EnvironmentValues.terminalSize` while the
authored tree was being resolved. The actual layout proposal was computed later
by `LayoutEngine`.

That split is the root of the spinner bug: a `GeometryReader` inside
`.frame(minWidth: 1, idealWidth: 1, maxWidth: 1, minHeight: 1, idealHeight: 1,
maxHeight: 1)` saw the sheet/root terminal width during resolve, even though
layout later constrained the view to one cell. The spinner therefore took its
wide rendering branch and then the outer frame clipped the same first cell on
every tick.

The original spot fixes kept the previous architecture by making common static
proposal-transforming wrappers maintain the same geometry environment contract
that exact `.frame(width:height:)` already used. That mitigation has been
replaced by the layout-dependent boundary described in the implementation plan
under `docs/plans/`.

## Former Resolve-Time Structure

The runtime pipeline is:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`GeometryReader` previously lived entirely in the first phase:

```swift
GeometryProxy(
  size: context.environmentValues.terminalSize,
  safeAreaInsets: context.environmentValues.safeAreaInsets,
  cellPixelMetrics: context.environmentValues.cellPixelMetrics,
  pointerInputCapabilities: context.environmentValues.pointerInputCapabilities
)
```

It then lowers its authored content into:

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

That second step makes the reader occupy available layout space once layout
runs. It does not change where the proxy size came from. The proxy size has
already been captured from the resolve context.

This meant `EnvironmentValues.terminalSize` was doing two jobs:

- At the root, it is the host surface size.
- Inside certain containers, it is also the local geometry proposal that
  `GeometryReader` is expected to report.

That second meaning was not automatic. Any modifier that changed its child's
layout proposal before measurement also had to update the resolve-time
`terminalSize` if `GeometryReader` was expected to observe the tightened size.

## Existing Behavior Before The Bridge Patch

Exact frames already bridged the split:

```swift
.frame(width: 7, height: 2)
```

`FrameModifier.resolve` updates `EnvironmentValues.terminalSize` for explicit
axes before resolving its child. So `GeometryReader` inside an exact frame sees
`7x2`, matching the later layout proposal.

Flexible frames did not:

```swift
.frame(minWidth: 1, idealWidth: 1, maxWidth: 1, minHeight: 1, idealHeight: 1, maxHeight: 1)
```

`FlexibleFrameModifier.resolve` previously resolved child content under the
parent context unchanged. Layout later clamped the child proposal to `1x1`, but
the `GeometryReader` had already captured the parent terminal size.

Static inset wrappers had the same class of bug:

- `.padding(...)` reduces the child proposal in layout.
- `.safeAreaPadding(...)` reduces the child proposal in layout.
- Outset `.border(...)` reserves border cells and reduces the child proposal in
  layout.
- Authored `.ignoresSafeArea(...)` can expand the child proposal again when it
  reclaims safe-area padding that already tightened the resolve geometry.

Before this patch, the shrinking wrappers resolved their child under the
unchanged `terminalSize`, and `ignoresSafeArea` had no way to distinguish safe
area that had actually been subtracted from `terminalSize` from root safe area
that was only carried as `safeAreaInsets`.

## Bridge Spot Fixes Previously Applied

These notes explain the intermediate mitigation that existed before
layout-dependent content realization shipped. The current implementation no
longer rewrites `terminalSize` in these modifiers.

### Flexible frame

`FlexibleFrameModifier.resolve` was changed to resolve child content under a
`terminalSize` clamped by finite `min` and `max` constraints.

For a finite parent terminal size:

- finite `maxWidth` / `maxHeight` clamp the child size down;
- finite `minWidth` / `minHeight` clamp the child size up;
- `.infinity` leaves the axis unchanged;
- `idealWidth` / `idealHeight` do not alter the child proposal.

The last point matches the layout engine's behavior for a finite parent
proposal. Ideal dimensions matter when a proposal is unspecified; the
resolve-time geometry environment is a concrete `CellSize`, so there is no
unspecified state to carry here.

### Padding and safe-area padding

`PaddingModifier.resolve` and `SafeAreaPaddingModifier.resolve` were changed to
subtract the known layout insets from `terminalSize` before resolving child
content.

`SafeAreaPaddingModifier` still applies its existing safe-area environment
transform. The change only keeps `GeometryProxy.size` aligned with the
proposal that layout will hand to the child.

`safeAreaPadding` also tracks the safe-area insets that it has applied to the
resolve-time terminal-size channel so a later `ignoresSafeArea` can restore the
same geometry on matching edges.

### Safe-area ignore

`IgnoreSafeAreaModifier.resolve` was changed to expand `terminalSize` only by
safe-area insets that were previously tracked as having tightened the
resolve-time geometry. It then cleared those tracked insets on the ignored
edges.

This is intentionally narrower than adding all reclaimed `safeAreaInsets` to
`terminalSize`: root safe area is exposed separately through
`GeometryProxy.safeAreaInsets` and has not necessarily been subtracted from the
root `terminalSize`.

### Outset border

`BorderModifier.resolve` was changed to compute the same static layout insets
used by the layout engine for non-inset borders and subtract those cells from
`terminalSize` before resolving child content.

Inset borders continue to contribute zero layout insets, so they do not alter
the child geometry environment.

## Tests Added

`Tests/SwiftTUITests/GeometryReaderSurfaceTests.swift` was expanded to pin:

- root `GeometryReader` still reports the terminal surface size;
- `GeometryReader` sees exact frame constraints;
- `GeometryReader` sees padding-reduced constraints;
- `GeometryReader` sees outset border-reduced constraints;
- `GeometryReader` sees finite flexible-frame constraints;
- unconstrained flexible axes keep the parent terminal size.

`Tests/SwiftTUITests/SafeAreaSurfaceTests.swift` was expanded to pin:

- `safeAreaPadding` tightens `GeometryReader` size while preserving the existing
  safe-area behavior.
- `ignoresSafeArea` does not over-expand root geometry.
- `ignoresSafeArea` restores safe-area-padding-tightened geometry on selected
  edges.

These are deliberately surface-level tests because the bug is visible at the
public authoring API, not in raw `LayoutEngine` measurement alone.

## How Deep The Issue Goes

The issue is deeper than `FlexibleFrameModifier`, but not every instance is
equally fixable.

There are two categories.

### 1. Static proposal transforms

These containers know their child proposal during resolve, or can derive the
same transform from values already available during resolve:

- exact `.frame(width:height:)`;
- finite min/max `.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)`
  when the current terminal size is known;
- `.padding(...)`;
- `.safeAreaPadding(...)`;
- `.ignoresSafeArea(...)` when restoring safe-area geometry that an authored
  static wrapper already subtracted;
- outset `.border(...)`.

For these, the bridge-era spot fix rewrote the child resolve context's
`terminalSize` to match the proposal the layout engine would later use.

### 2. Measurement-dependent proposal transforms

These containers do not know the final child proposal until measurement or
placement:

- `safeAreaInset`, because base-content shrinkage depends on measuring the
  inset child and comparing it to reclaimed safe area;
- `ViewThatFits`, because the selected child is chosen by measuring candidates;
- `ScrollView`, because the viewport/content relationship depends on proposal,
  indicators, axes, and content measurement;
- stacks, because space distribution depends on sibling measurements, layout
  priorities, spacers, compression, and in some cases lazy viewport state;
- custom `Layout`, especially worker-safe layouts, because the proposal
  transform lives behind user-supplied layout code and may run off the main
  actor;
- decorations/overlays where secondary children may need geometry derived from
  the primary child's measured size or placement.

For these, a resolve-time environment shim is not enough. The correct geometry
may not exist yet when the child view's body is being evaluated.

## Why This Is Structurally Incorrect

The framework exposed `GeometryReader` as though it reported local layout
geometry, but its implementation reported a value from resolve context. That
created a hidden maintenance contract:

> Any view or modifier that changes a child's local proposal must remember to
> encode that proposal into `EnvironmentValues.terminalSize` before resolving
> the child.

That contract was fragile because the canonical source of layout truth is not
the environment. It is `ProposedSize` during measurement and placement.

The split also makes it easy for tests to pass at one layer and fail at the
authored runtime surface:

- `LayoutEngine` can correctly measure a child under a tightened proposal.
- `GeometryReader` can still report a stale parent size because it never sees
  that later proposal.

That is exactly what happened with the spinner.

## Why Not Just Make GeometryReader Use LayoutEngine?

A fully faithful fix is not a one-line plumbing change. `GeometryReader`'s
closure returns authored views:

```swift
GeometryReader { proxy in
  content(proxy)
}
```

Running that closure during layout would mean building or rebuilding a subtree
after the normal resolve phase. That affects:

- identity allocation;
- `@State` ownership;
- environment and observation dependency tracking;
- action, key, task, gesture, focus, and lifecycle registrations;
- retained-tree reuse;
- async frame-head/frame-tail behavior;
- custom layout execution boundaries.

If layout re-resolves a subtree after measurement, the framework must prevent
duplicate lifecycle/task effects, merge runtime registrations safely, and
decide how retained snapshots are invalidated when geometry changes.

That is architecture work, not a safe spot fix.

## Possible Long-Term Designs

### Option A: Keep the bridge and harden it

Continue treating `terminalSize` as the resolve-time geometry channel, but make
the contract explicit:

- centralize helper APIs for static proposal transforms;
- require every static layout modifier to use those helpers;
- add regression tests for every public modifier that deterministically changes
  child proposal;
- document measurement-dependent containers as not providing fully local
  geometry during resolve.

This was the smallest bridge path.

### Option B: Add an explicit resolve proposal field

Add a `ResolveContext` field such as `geometryProposal` or `localProposal`, and
make `GeometryReader` read that instead of overloading `terminalSize`.

This makes the current bridge clearer, but it does not solve
measurement-dependent containers. They still cannot provide a proposal before
layout unless the framework adds a second pass.

### Option C: Two-pass geometry subtrees

Make `GeometryReader` a special boundary:

1. Resolve a placeholder node.
2. During layout, compute the actual proposal for that node.
3. Re-resolve the reader's content using that proposal.
4. Re-enter measurement/placement for the generated subtree.

This is the most semantically accurate direction, but it is also the highest
risk. It needs a design for lifecycle staging, registration reconciliation,
state identity, dependency tracking, and retained-tree reuse across a
layout-triggered re-resolve.

### Option D: Layout-protocol-owned geometry content

Introduce a lower-level primitive where layout code owns a geometry-dependent
content closure and returns resolved children through a controlled runtime
registration channel.

This could generalize beyond `GeometryReader`, but it would be a new framework
capability. It should not be introduced as a bug fix.

## Current Status

Option C has shipped as the generalized layout-dependent content boundary
tracked in the
[layout-dependent content realization plan](docs/plans/2026-05-01-001-layout-dependent-content-realization-plan.md).

Current guidance:

- Use `GeometryReader` for local placed geometry, including frame, padding,
  safe-area, decoration, `ViewThatFits`, stack, and custom `Layout` contexts.
- Use `EnvironmentValues.terminalSize` for the root host surface size, not local
  proposal geometry.
- Use `GeometryProxy.cellPixelMetrics` and
  `GeometryProxy.pointerInputCapabilities` when authored content needs terminal
  precision data tied to the realized geometry.
- Keep ordinary preferences resolve-time. Public anchor and geometry-bound
  preference APIs remain deferred until coordinate-space resolution is ready.
