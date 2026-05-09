---
title: "feat: deeper scroll control scope"
type: feature
status: planned
date: 2026-05-09
depends_on:
  - "../SOURCE_LAYOUT.md"
  - "../TERMINAL_NATIVE_DOCTRINE.md"
  - "../TERMINAL_NATIVE_UI_RESEARCH.md"
---

# Deeper Scroll Control Scope

> **For agentic workers:** this is a scoping and implementation-options record.
> Before implementation, re-check the current `ScrollView` surface and keep the
> first tranche small enough to validate with focused Core, surface, and composed
> runtime tests. Shared scroll changes must finish with `bun run test`.

**Goal:** Add first-class scroll control beyond raw cell offsets while keeping
`ScrollView` a terminal-native pane primitive. The next useful layer is identity
and anchor based scrolling, plus explicit page/home/end policy. Offset-only
helpers are already present and should not be mistaken for the deeper model.

**Architecture:** Preserve the current offset-backed runtime as the execution
substrate. Add semantic scroll targets during placement/semantics, route public
scroll commands through the existing local scroll-position registry, and compute
target offsets from committed `ScrollRoute` geometry.

**Tech Stack:** Swift 6.3 strict concurrency, `SwiftTUIViews` scroll authoring
APIs, `SwiftTUICore` semantics/runtime registries, `UnitPoint` anchors, terminal
cell geometry, Swift Testing, composed `RunLoop` input tests, and the repo-wide
`bun run test` gate.

---

## Starting State Snapshot

- `docs/TODO.md` tracks this gap as "Scope deeper scroll control": public
  `ScrollPosition`, binding-backed offsets, indicators, keyboard scrolling,
  pointer scrolling, and caret/focus reveal exist, but there is no higher-level
  reader/proxy model.
- `ScrollPosition` is currently a public cell-offset value with `x`, `y`,
  `scrolledBy(...)`, `scrollBy(...)`, and `scrollTo(x:y:)`.
- `ScrollView` owns either an internal `@State` position or an explicit
  `Binding<ScrollPosition>`, registers key/pointer handlers, clamps pointer
  deltas against event scroll context, and lowers to `ScrollViewLayout`.
- `ScrollViewLayout` measures one child, clamps the requested offset during
  placement, and passes `ScrollViewportContext` to child placement.
- `LocalScrollPositionRegistry` already has the important runtime seam:
  registered scroll identities expose `currentOffset` and `applyOffset`, and
  focus sync computes a minimal reveal offset from `ScrollRoute` geometry.
- `SemanticSnapshot.ScrollRoute` currently contains only the scroll identity,
  viewport rect, and content bounds. It does not expose target child rects,
  current offset, visible target IDs, phase, or page policy.
- `KeyEvent` already includes `.home` and `.end`, but `ScrollView` only consumes
  arrow keys. Page-up/page-down are not represented in the public key model.
- Pointer scrolling already chooses the deepest scroll route at the pointer
  location, favoring true `ScrollView` routes over list/table selection routes.

## Modern SwiftUI API Signal

Apple's current SwiftUI scroll surface separates five concerns that are worth
mirroring selectively:

- `scrollPosition(_:, anchor:)` binds a `ScrollPosition` to a `ScrollView`.
  Apple's `ScrollPosition` can represent a view identity, a concrete offset, or
  an edge. Identity positions depend on `scrollTargetLayout()` and are kept
  stable across reorder, resize, and initial layout when possible.
- `scrollPosition(id:anchor:)` is the simpler identity binding surface: the
  binding updates to the visible target ID as the user scrolls, and writes scroll
  to that target.
- `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` is still the
  imperative model. A nil anchor means "minimum movement to make the target
  wholly visible"; a non-nil anchor aligns a point in the target with the same
  point in the viewport.
- `scrollTargetLayout()` and `scrollTargetBehavior(_:)` split target discovery
  from settling policy. Built-ins include paging and view-aligned behavior, and
  custom behavior can adjust the proposed target.
- `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` cover initial
  position, size-change handling, and alignment of undersized content.

Documentation checked during this scope pass:

- Apple `scrollPosition(_:, anchor:)`:
  <https://developer.apple.com/documentation/swiftui/view/scrollposition%28_%3Aanchor%3A%29>
- Apple `ScrollPosition.scrollTo(id:anchor:)`:
  <https://developer.apple.com/documentation/swiftui/scrollposition/scrollto%28id%3Aanchor%3A%29>
- Apple `ScrollViewProxy.scrollTo(_:anchor:)`:
  <https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto%28_%3Aanchor%3A%29>
- Apple `ScrollTargetBehavior`:
  <https://developer.apple.com/documentation/swiftui/scrolltargetbehavior>
- Apple `defaultScrollAnchor(_:for:)`:
  <https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor%28_%3Afor%3A%29>
- Apple `ScrollPhase` and scroll observation links:
  <https://developer.apple.com/documentation/swiftui/scrollphase>

Related APIs are lower priority for this repo's next tranche:

- `onScrollGeometryChange(...)`, `onScrollPhaseChange(...)`, and target/visibility
  callbacks are observation surfaces. Useful later, but they require a stable
  event model and would widen the first implementation.
- `scrollDisabled(_:)` and `scrollInputBehavior(_:for:)` are input gating
  surfaces. The terminal equivalent should probably live with key/pointer policy,
  not identity targeting.
- `scrollClipDisabled(_:)`, `scrollDismissesKeyboard(_:)`, scroll transitions,
  bounce behavior, and content margins are not first-order terminal scroll
  control needs.

## Terminal Interpretation

SwiftTUI should not copy the whole GUI scroll vocabulary. The doctrine and
research docs both push toward pane-first, selection-driven terminal UX, so the
API should bias toward predictable movement in stable rectangular panes.

- Treat offsets as cell coordinates, not pixels.
- Treat nil-anchor identity scrolls as minimal reveal; this matches SwiftUI
  `ScrollViewProxy` and the repo's existing focus reveal behavior.
- Support `.top`, `.center`, `.bottom`, leading/trailing, and two-axis anchors
  through existing `UnitPoint` only when they produce deterministic cell offsets.
- Make page/home/end behavior explicit and bounded by the viewport/content
  geometry. Page movement should be "viewport minus overlap" for terminal
  readability, not animated deceleration.
- Keep scrollback and preview conventions as component-level patterns on top of
  this foundation. A log viewer or terminal scrollback pane wants bottom-stick
  behavior and search/preview affordances, but those should not force the core
  `ScrollView` API into a page model.

## Implementation Options

### Option A: Offset Policy Only

Add home/end/page helpers to `ScrollPosition` and teach `ScrollView` to consume
those keys.

Pros:

- Smallest patch.
- Immediately useful for keyboard users.
- Fits current `Binding<ScrollPosition>` implementation.

Cons:

- Does not solve scroll-to-identity or anchor based scrolling.
- Does not move the repo closer to SwiftUI's modern semantic scroll model.

Use this only as a preparatory tranche, not as the completion of this TODO item.

### Option B: ScrollViewReader And Proxy

Add a public `ScrollViewReader` that provides a `ScrollViewProxy` with:

```swift
proxy.scrollTo(id, anchor: UnitPoint? = nil)
proxy.scrollTo(edge: Edge)
proxy.scrollBy(x: Int = 0, y: Int = 0)
proxy.scrollTo(x: Int? = nil, y: Int? = nil)
```

The proxy should dispatch to a package-local registry keyed by scroll-view
identity. The registry can reuse the current `currentOffset` / `applyOffset`
pattern, but it needs access to target rects from the last committed semantic
snapshot.

Pros:

- Matches an established SwiftUI model without changing the public
  `ScrollPosition` storage immediately.
- Lets implementation stay runtime-driven and testable through composed
  `RunLoop` paths.
- Gives app code an imperative command surface, which is natural for terminal
  keybindings and command palettes.

Cons:

- Requires a target-registration mechanism and committed-frame lookup before
  commands can be resolved.
- Reader scope and identity ownership need careful authoring-context handling so
  proxy actions do not mutate stale view state.

This is the recommended V1 public shape.

### Option C: Modernize ScrollPosition Binding

Extend `ScrollPosition` beyond `x/y` so it can carry a semantic target:

```swift
position.scrollTo(id: itemID, anchor: .bottom)
position.scrollTo(edge: .bottom)
position.viewID(type: Item.ID.self)
```

Pros:

- Closest to modern SwiftUI.
- Enables declarative identity bindings and target-ID observation later.
- Gives content resize/reorder stability a natural home.

Cons:

- `ScrollPosition` is already public with public `x/y`; changing its semantics
  needs public API baseline review and careful source compatibility.
- Requires target identity extraction and visible-ID updates before the binding
  tells the truth.
- More risk than the reader/proxy surface because writes and reads both become
  semantic.

This should follow the proxy foundation unless a near-term consumer specifically
needs declarative ID binding.

### Option D: Target Behavior And Default Anchors

Add `scrollTargetLayout()`, `scrollTargetBehavior(_:)`, and
`defaultScrollAnchor(...)` equivalents.

Pros:

- Provides a clean future path for view-aligned lists, paging panes, chat/log
  bottom-stick, and resize behavior.
- Builds on the same target-rect registry needed by Options B and C.

Cons:

- Behavior policy gets complicated without first-class target metadata.
- Paging and view-aligned settling are less important in raw terminals because
  input is discrete and there is no inertial scroll.

Keep this as V2 once identity target resolution exists.

### Option E: Observation And Host Transport Hooks

Expose scroll geometry, phase, visible target IDs, or host transport callbacks.

Pros:

- Useful for status bars, lazy data loading, external host scrollbars, and
  browser/native wrappers.

Cons:

- Easy to over-design before the command model is stable.
- `ScrollPhase` maps poorly to raw terminal input without an animation/deceleration
  model.

Defer until after V1 command semantics and V2 target behavior are stable.

## Recommended V1 Boundary

Implement the smallest semantic layer that proves identity and anchor control:

- Add package-local scroll target metadata:
  - target identity
  - target rect in content coordinates
  - scroll-route identity
  - optional target role for future list/table integration
- Add a target-discovery modifier equivalent to `scrollTargetLayout()` if the
  existing identity tree cannot cheaply identify direct layout children. Prefer
  automatic target discovery for direct `ForEach`/`.id(...)` children only if it
  does not make every view identity a scroll target.
- Add `ScrollViewReader` / `ScrollViewProxy` as the first public high-level API.
- Implement `scrollTo(id, anchor:)` with:
  - nil anchor -> minimum reveal, using the same math as focus reveal
  - `UnitPoint` anchor -> align target anchor to viewport anchor, clamped to
    content bounds
  - missing target -> no-op
- Add `.home` and `.end` handling for focused `ScrollView` and indicator focus.
- Decide page key representation before implementing page policy. If terminals
  map PageUp/PageDown through CSI `5~`/`6~`, add explicit `KeyEvent.pageUp` and
  `KeyEvent.pageDown`; do not overload arrow modifiers.
- Keep `ScrollPosition`'s public `x/y` behavior intact in V1. If semantic
  binding is added later, make it additive and documented.

## Validation Plan

- Core tests for offset math:
  - minimal reveal below/above/left/right
  - anchored top/center/bottom calculations
  - clamping at all content edges
  - no-op for missing target or already visible target
- Surface tests:
  - `ScrollViewReader` scrolls to an `.id(...)` row before rasterization after
    a button/key action
  - nil anchor preserves minimal reveal, not centering
  - explicit `.bottom` anchor places the row at the viewport bottom when possible
- Runtime tests:
  - key command or button inside a composed `RunLoop` calls proxy scroll and
    rerenders immediately
  - home/end key handling mutates only the focused scroll view
  - pointer scrolling behavior remains unchanged
- Regression checks:
  - existing focus-driven caret reveal still uses minimal reveal
  - existing scroll indicator click/drag tests still pass
  - lazy-stack scroll placement and layout-dependent geometry tests remain green

## Open Decisions

- Should target discovery be explicit-only with `scrollTargetLayout()`, or should
  `.id(...)` direct children be targets by default? Lean explicit for parity and
  to avoid turning all identities into targets.
- Should `ScrollViewProxy` require a concrete scroll-view identity for nested
  scroll views, or should it scan descendant routes like SwiftUI's proxy does?
  Lean scan-first for parity, with future named-scope support if nested panes
  need stronger disambiguation.
- Should `List`/`Table` participate in V1 target discovery? Lean no: they already
  have selection semantics, and row-target scrolling should be designed with
  selection movement rather than bolted onto generic `ScrollView`.
- Should bottom-stick scrollback be a `defaultScrollAnchor(.bottom)` behavior or
  a dedicated terminal/log component policy? Lean component policy first, with
  `defaultScrollAnchor` later if multiple components need the same primitive.
