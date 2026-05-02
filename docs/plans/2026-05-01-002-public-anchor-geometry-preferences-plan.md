---
title: "feat: public anchor and geometry-bound preference API"
type: feature
status: shipped
date: 2026-05-01
depends_on: "2026-05-01-001-layout-dependent-content-realization-plan.md"
---

# feat: public anchor and geometry-bound preference API

## Overview

Ship SwiftUI-shaped anchor preferences on top of the layout-dependent
realization seam. The goal is to let view subtrees publish geometry references
that can be reduced through `PreferenceKey` and resolved later inside
`GeometryReader`, without returning to the old `terminalSize` proposal bridge.

This is the next step after layout-dependent `GeometryReader`: the framework can
now realize authored content during placement, but it still lacks a public
geometry token that survives preference reduction and can be resolved against
placed frames and named coordinate spaces.

## Implementation Record

Shipped on 2026-05-01.

- Added public `Anchor<Value>` and `AnchorSource<Value>` tokens with bounds and
  point sources.
- Added `anchorPreference(key:value:transform:)` and
  `transformAnchorPreference(_:value:transform:)` modifiers.
- Added a layout-time placed-frame table and threaded it into
  `LayoutRealizationContext` so `GeometryReader` content resolves against
  placement geometry.
- Added `GeometryProxy[Anchor<Rect>]`, `GeometryProxy[Anchor<Point>]`, and
  `GeometryProxy.frame(in:)`.
- Covered token publication, overlay resolution, point anchors, global/local
  frames, and named coordinate spaces in `AnchorPreferenceSurfaceTests`.
- Follow-up hardening records diagnostics for missing anchors, missing named
  spaces, and duplicate named spaces while preserving existing fallback and
  last-writer-wins behavior.
- Updated public API docs, baseline inputs, and current-status docs.

## Current State

Already shipped:

- `GeometryReader` content is realized during placement from assigned bounds.
- `EnvironmentValues.terminalSize` is host/root metadata only.
- Ordinary `PreferenceKey` values reduce during resolve.
- `overlayPreferenceValue` and `backgroundPreferenceValue` read ordinary
  reduced values and produce decoration content during resolve.
- `CoordinateSpace.local`, `.global`, and `.named(_:)` exist for gestures.
- `coordinateSpace(name:)` records placed named frames into
  `SemanticSnapshot.namedCoordinateSpaces`.
- Public `Anchor` tokens, `anchorPreference(...)`,
  `transformAnchorPreference(...)`, `GeometryProxy` anchor resolution, and
  `GeometryProxy.frame(in:)` have shipped.
- A layout-time placed-frame table now serves geometry resolution without
  making semantic extraction the source of layout truth.

## Requirements

- R1. Keep ordinary preferences resolve-time and source-compatible.
- R2. Represent anchor preferences as opaque geometry tokens, not early concrete
  rectangles.
- R3. Resolve anchors only after placement has produced actual frames.
- R4. Resolve anchors in the coordinate space of the `GeometryProxy` doing the
  lookup, with explicit support for `.local`, `.global`, and `.named(_)`.
- R5. Preserve preference reduction order and modifier order.
- R6. Do not commit lifecycle, task, gesture, command, drop, focus, or semantic
  side effects from unselected `ViewThatFits` candidates.
- R7. Keep async ordered commit: frame-tail workers may remain eligible only
  when the tree has no main-actor geometry realization requirement.
- R8. Keep the API intentionally small. Do not add `onGeometryChange`,
  `visualEffect`, or full affine transforms in the first public anchor pass.
- R9. Make missing named coordinate spaces deterministic and diagnosable.
- R10. Update the public API baseline and docs when public names ship.

## Public API Shape

Use SwiftUI-compatible names where the terminal geometry types differ only by
value type.

```swift
public struct Anchor<Value: Sendable>: Sendable {
  // Opaque public value. Package internals carry source identity and kind.
}

public struct AnchorSource<Value: Sendable>: Sendable {
  // Opaque public anchor source used by preference modifiers.
}

extension AnchorSource where Value == Rect {
  public static var bounds: Self { get }
}

extension AnchorSource where Value == Point {
  public static var topLeading: Self { get }
  public static var top: Self { get }
  public static var topTrailing: Self { get }
  public static var leading: Self { get }
  public static var center: Self { get }
  public static var trailing: Self { get }
  public static var bottomLeading: Self { get }
  public static var bottom: Self { get }
  public static var bottomTrailing: Self { get }
}

extension GeometryProxy {
  public subscript(anchor: Anchor<Rect>) -> Rect { get }
  public subscript(anchor: Anchor<Point>) -> Point { get }
  public func frame(in coordinateSpace: CoordinateSpace) -> Rect
}

extension View {
  public func anchorPreference<Key: PreferenceKey, Value: Sendable>(
    key: Key.Type = Key.self,
    value: AnchorSource<Value>,
    transform: @escaping (Anchor<Value>) -> Key.Value
  ) -> some View

  public func transformAnchorPreference<Key: PreferenceKey, Value: Sendable>(
    _ key: Key.Type = Key.self,
    value: AnchorSource<Value>,
    transform: @escaping (inout Key.Value, Anchor<Value>) -> Void
  ) -> some View
}
```

Notes:

- Public anchor values are intentionally opaque. They can be stored inside
  `PreferenceKey.Value` but cannot be inspected except through `GeometryProxy`.
- The first public pass supports `Rect` and `Point`. Avoid over-generalizing to
  arbitrary anchor value types until there is a real use case.
- `Rect` and `Point` are continuous cell-space types. `CellRect` remains the
  internal layout/raster frame type.
- `GeometryProxy[anchor]` returns coordinates relative to that proxy's placed
  bounds, matching the normal authoring expectation for overlay geometry.
- `GeometryProxy.frame(in: .global)` returns terminal-global continuous bounds.
  `.named(_)` subtracts the named coordinate-space frame. `.local` returns the
  proxy's own bounds with origin zero.

## Internal Model

Add package-internal storage parallel to, but separate from, ordinary
`PreferenceValues`.

Core concepts:

- `AnchorID`: stable token identity, derived from the contributing node
  identity plus source kind.
- `AnchorKind`: `.bounds` or `.point(UnitPoint)`.
- `AnchorPayload<Value>`: public opaque `Anchor<Value>` backing storage.
- `PlacedFrameTable`: maps `Identity` to placed `CellRect`, plus named
  coordinate-space frames.
- `AnchorResolver`: resolves an anchor payload through the placed frame table
  into the requesting `GeometryProxy` coordinate space.

Do not make `SemanticSnapshot` the anchor source of truth. Semantics can keep
publishing named coordinate spaces for gesture delivery, but anchor resolution
belongs to the post-placement geometry phase so it is available before
semantics/draw/raster and independent of hit-testing policy.

## Data Flow

Preferred first implementation:

```text
resolve:
  anchorPreference writes ordinary PreferenceKey.Value containing Anchor tokens

measure:
  unchanged

place:
  build PlacedNode tree
  build PlacedFrameTable from placed tree
  realize layout-dependent content with AnchorResolver in LayoutRealizationContext

GeometryReader realization:
  GeometryProxy carries local bounds + AnchorResolver
  proxy[anchor] resolves the anchor's source frame relative to proxy bounds

semantics/draw/raster/commit:
  consume finalized realized tree as today
```

This keeps anchors as preference values while delaying coordinate conversion.
The preference value itself does not need to be recomputed merely because layout
changed; only the later proxy lookup changes.

## Phase 0: Characterization

Add failing tests before implementation:

- `anchorPreference` can publish `.bounds` into a custom `PreferenceKey`.
- `overlayPreferenceValue` can use `GeometryReader { proxy in proxy[anchor] }`
  to place a marker at the base view's bounds.
- `transformAnchorPreference` preserves existing reduced values and modifier
  order.
- `GeometryProxy.frame(in: .local)` reports origin zero and the proxy size.
- `GeometryProxy.frame(in: .global)` reports terminal-global placed bounds.
- `GeometryProxy.frame(in: .named("board"))` subtracts the named frame.
- Missing named coordinate spaces follow the existing gesture behavior at first:
  fall back to global coordinates and record a diagnostic.

Focused files:

- `Tests/SwiftTUITests/PreferenceSurfaceTests.swift`
- `Tests/SwiftTUITests/CoordinateSpaceTests.swift`
- `Tests/SwiftTUITests/GeometryReaderSurfaceTests.swift`
- new `Tests/SwiftTUITests/AnchorPreferenceSurfaceTests.swift`

## Phase 1: Anchor Tokens And Preference Modifiers

Implement public opaque types and resolve-time preference writers.

Work:

- Add `Sources/Core/AnchorTypes.swift` or a View-layer file if public anchors
  should live in `View`.
- Add `AnchorSource<Rect>.bounds` and point sources.
- Implement `anchorPreference` by creating an `Anchor<Value>` token for the
  resolved content node and merging `transform(anchor)` into ordinary
  `PreferenceValues`.
- Implement `transformAnchorPreference` with the same modifier-order semantics
  as `transformPreference`.
- Keep public anchor storage opaque and `Sendable`.

Acceptance:

- Ordinary preference tests still pass unchanged.
- Anchor tokens reduce in view-tree order.
- Anchor modifiers do not require layout realization by themselves.

## Phase 2: Placed Frame Table

Add a geometry table created from the placed tree.

Work:

- Collect every placed node's `Identity -> CellRect`.
- Collect named coordinate spaces from `SemanticMetadata.namedCoordinateSpaceName`
  during the same post-placement walk.
- Include clip bounds only as metadata for future APIs; first-pass anchor
  resolution should use placed bounds, not clipped hit-test bounds.
- Store the table in frame artifacts and in `LayoutPassContext` or a sibling
  context that `GeometryReader` realization can read.

Acceptance:

- Named coordinate-space tests can be driven from the placed-frame table.
- Semantics still publishes the same named frames as before.
- No preference behavior changes yet.

## Phase 3: GeometryProxy Resolution

Teach `GeometryProxy` to resolve frames and anchors.

Work:

- Add package-internal anchor resolver storage to `GeometryProxy`.
- Add `frame(in:)`.
- Add `subscript(anchor: Anchor<Rect>) -> Rect`.
- Add `subscript(anchor: Anchor<Point>) -> Point`.
- Convert `CellRect` to continuous `Rect` at the API boundary.
- Define deterministic fallback for unresolved anchor identities:
  return `.zero` for rects / points and record a diagnostic, or trap in debug
  builds. Prefer diagnostic fallback for terminal runtime resilience.

Acceptance:

- `GeometryReader` at root and under wrappers resolves `.local`, `.global`, and
  `.named(_)` correctly.
- Anchor lookup changes when layout changes without re-running preference
  reduction.

## Phase 4: Anchor Preferences In Decorations

Make the common SwiftUI pattern work:

```swift
base
  .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
  .overlayPreferenceValue(BoundsKey.self) { anchor in
    GeometryReader { proxy in
      let rect = proxy[anchor]
      marker.frame(width: Int(rect.size.width), height: 1)
        .offset(x: Int(rect.origin.x), y: Int(rect.origin.y))
    }
  }
```

Work:

- Ensure `overlayPreferenceValue` / `backgroundPreferenceValue` decoration
  children that include `GeometryReader` receive an anchor resolver through the
  layout-dependent boundary.
- Ensure selected `ViewThatFits` candidates are the only source of committed
  anchor-resolved decoration side effects.
- Ensure overlay/background preference values continue to include both base and
  decoration preference sources according to current tests.

Acceptance:

- Overlay and background marker examples pass under frames, padding, safe-area
  padding, `safeAreaInset`, stacks, `ViewThatFits`, and custom `Layout`.
- No duplicate lifecycle/task/gesture registrations from anchor overlays.

## Phase 5: Coordinate-Space Hardening

Make coordinate-space behavior explicit enough for public docs.

Work:

- Decide whether missing named coordinate spaces should keep gesture-compatible
  fallback-to-global behavior or become a logged diagnostic plus `.zero`.
- Add frame table diagnostics for duplicate named spaces. Current behavior is
  last-writer-wins; public anchor docs should either codify that or warn.
- Add tests for nested named coordinate spaces and names inside layout-dependent
  content.
- Consider adding package-internal `CoordinateSpaceResolution` result values so
  callers can distinguish resolved, missing, and ambiguous cases.

Acceptance:

- `CoordinateSpaceTests` cover named, nested, missing, and duplicate names.
- Docs state that named coordinate-space names should be unique in a rendered
  frame.

## Phase 6: Async, Reuse, And Diagnostics

Harden runtime behavior.

Work:

- Include anchor resolver/table creation in sync and async render paths.
- Preserve ordered commit when anchor-resolving overlays force main-actor
  layout realization.
- Verify retained layout reuse invalidates correctly when frame-table inputs
  change.
- Add diagnostics for anchor resolution misses and duplicate named spaces.

Acceptance:

- Static trees without `GeometryReader` or anchor-resolving content remain
  worker eligible.
- Anchor-resolving `GeometryReader` content falls back to the main actor with
  existing layout-dependent diagnostics.
- `bun run test` passes.

## Phase 7: Public Docs And Baseline

Finalize the public surface.

Work:

- Update `docs/STATUS.md` to remove the anchor-preference deferral.
- Update `docs/PUBLIC_API_BASELINE.md`.
- Update `docs/PUBLIC_API_INVENTORY.md`.
- Add DocC pages/examples for:
  - publishing bounds with `anchorPreference`,
  - resolving anchors in `GeometryReader`,
  - `GeometryProxy.frame(in:)`,
  - named coordinate spaces.
- Update `docs/SWIFTUI_LAYOUT.md` with the preference/anchor split:
  ordinary preference values reduce during resolve, anchor values resolve
  during placement through geometry proxies.

Acceptance:

- Public API policy scripts pass.
- Examples compile against the public API.

## Non-Goals

- No public `onGeometryChange` in this plan.
- No public `visualEffect` in this plan.
- No affine transforms, rotations, or non-rectangular anchor values.
- No multi-host coordinate conversion.
- No source compatibility promise for package-internal anchor storage.

## Open Questions

- OQ1. Should `Anchor<Rect>` resolve to `Rect` or `CellRect`? This plan chooses
  `Rect` because `CoordinateSpace` and pointer APIs already use continuous cell
  coordinates, and it keeps sub-cell evolution open.
- OQ2. Should missing named coordinate spaces trap, return global, or return
  zero? Gesture resolution currently falls back to global; the public anchor
  API may need a visible diagnostic to avoid silently misplaced overlays.
- OQ3. Should duplicate named coordinate spaces be last-writer-wins or
  first-writer-wins? Current semantics collection overwrites by name. Prefer
  preserving that behavior initially and adding diagnostics.
- OQ4. Does `overlayPreferenceValue` need its own layout-dependent realization
  variant, or is the SwiftUI pattern of resolving anchors inside a nested
  `GeometryReader` sufficient for the first public pass?
- OQ5. Should `GeometryProxy.frame(in:)` ship before `anchorPreference` as a
  smaller coordinate-space milestone?

## Verification Matrix

Focused:

```bash
swiftly run swift test --filter AnchorPreferenceSurfaceTests
swiftly run swift test --filter PreferenceSurfaceTests
swiftly run swift test --filter CoordinateSpaceTests
swiftly run swift test --filter GeometryReaderSurfaceTests
swiftly run swift test --filter AsyncFrameTailRenderingTests
```

Runtime/examples:

```bash
swiftly run swift test --package-path Examples/gallery
swiftly run swift test --package-path Examples/layouts
```

Final:

```bash
bun run test
```
