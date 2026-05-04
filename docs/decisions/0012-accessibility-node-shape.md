---
adr: "0012"
title: "AccessibilityNode shape: flat array, parent identity, no live focus"
status: accepted
date: 2026-05-04
sources:
  - docs/proposals/ACCESSIBILITY.md
  - docs/proposals/SUBSTRATE_AUDIT.md
  - docs/proposals/EMBEDDED_WEB_HOST.md
  - Sources/Core/Semantics.swift
  - Sources/Core/RenderTreeAndSemanticsTypes.swift
  - Sources/Core/FocusTracker.swift
---

# ADR-0012: AccessibilityNode shape

## Context

Phase 3b of the accessibility plan
([`ACCESSIBILITY.md`](../proposals/ACCESSIBILITY.md) §"Suggested
phasing") extends `SemanticSnapshot` with a new collection of
`AccessibilityNode` records, populated by `SemanticExtractor` during
the existing depth-first walk over the placed tree
([`Sources/Core/Semantics.swift`](../../Sources/Core/Semantics.swift)).

The shape of `AccessibilityNode` flows downstream into:

1. The CLI runtime (drives cursor-as-focus, drives the accessible-mode
   linear renderer).
2. The embedded web host wire format
   ([`EMBEDDED_WEB_HOST.md`](../proposals/EMBEDDED_WEB_HOST.md) Phase
   6 step 1) — gets serialized into the `accessibilityTree` field of
   the `web-surface` v2 envelope.
3. The browser bundle (mounts as DOM with ARIA attributes).
4. The SwiftUI host bridge — translates to `.accessibilityLabel` /
   `.accessibilityAddTraits` / `.accessibilityHidden` modifiers.
5. The (future) WASM web target — same wire format as the embedded
   host.

Five different consumers; the shape needs to be agreeable to all of
them. Several open dimensions:

- **Tree shape:** flat array vs nested.
- **Parent encoding:** parent identity reference vs nested children.
- **Focus state:** baked into the node vs computed by the consumer.
- **Pruning:** every PlacedNode emits one, vs only nodes that have
  a11y-relevant data, vs only nodes that pass a relevance cut.
- **Document order:** layout reading order vs source order.
- **Cursor anchor:** field on the node vs separate channel.

The `SemanticSnapshot`'s existing collections — `interactionRegions`,
`focusRegions`, `scrollRoutes`, `selectionRoutes` — are flat arrays
with parent context encoded via `scopePath: [Identity]` and
`sectionIdentity: Identity?`. That's the established pattern in the
substrate.

## Decision

```swift
public struct AccessibilityNode: Equatable, Sendable {
  /// Stable identity matching the corresponding PlacedNode.
  public var identity: Identity

  /// Parent node's identity. nil for roots. Tree reconstruction at
  /// the consumer is `Dictionary(grouping:by:)` over this field.
  public var parentIdentity: Identity?

  /// Bounds in cell coordinates (matches the `PlacedNode.bounds`
  /// the extractor saw, after clip/transient/visibility filtering).
  public var rect: CellRect

  /// Role, post-inference. See "Role inference" below.
  public var role: AccessibilityRole

  /// Authored or derived label. nil when no label is reachable
  /// (consumers may fall back to inner text content).
  public var label: String?

  /// Authored hint. nil when not authored.
  public var hint: String?

  /// True when this subtree was authored as
  /// `accessibilityHidden(true)` — but emitted nodes do **not**
  /// include hidden subtrees in the output. This flag is reserved
  /// for nodes that *contain* hidden subtrees and need to advertise
  /// that fact (e.g. for unit tests of the extractor); production
  /// consumers can ignore it.
  public var hidden: Bool

  /// Authored politeness for live-region announcement. nil when
  /// the node is not a live region.
  public var liveRegion: AccessibilityPoliteness?

  /// Cell point inside `rect` where the hardware cursor should sit
  /// when this node is focused. Coordinates are absolute (already
  /// translated relative to the surface origin). nil means "use
  /// the node's own origin."
  public var cursorAnchor: CellPoint?
}
```

`SemanticSnapshot` gains:

```swift
public struct SemanticSnapshot: Equatable, Sendable {
  // ... existing fields ...
  public var accessibilityNodes: [AccessibilityNode]
}
```

### Tree shape: flat array, parent via identity

Rationale:

- Matches the established pattern of every other field in
  `SemanticSnapshot` (`interactionRegions`, `focusRegions`,
  `scrollRoutes`, `selectionRoutes` are all flat arrays).
- Equatable / Sendable on `AccessibilityNode` is straightforward.
  Recursive structures with `[AccessibilityNode]` children are
  Equatable but the per-frame diff cost is worse and the
  serialization is harder.
- The browser bundle and SwiftUI bridge both ultimately want a tree;
  reconstructing from `(identity, parentIdentity)` pairs is `O(n)`
  with one pass.

### Focus state is NOT on the node

Rationale:

- Focus changes between commits. If we baked `isFocused` into the
  node, every focus move would need to either re-extract semantics
  or mutate the snapshot in place. Both are expensive or break
  invariants.
- The `FocusTracker` already owns `currentFocusIdentity: Identity?`
  and updates it independently of the semantic snapshot. Consumers
  cross-reference: `node.identity == focusTracker.currentFocusIdentity`.
- The wire-format encoder for the embedded host **does** bake
  `isFocused` into each serialized entry, computed at encode time
  by combining the snapshot with the focus tracker. The wire-side
  representation is allowed to be richer than the snapshot-side
  representation.

### Pruning rule

Emit an `AccessibilityNode` for a `PlacedNode` if **any** of:

1. The node has a non-default role
   (`accessibilityRole != nil` after inference).
2. The node has an authored label, hint, or live-region.
3. The node is on the focus chain (its identity appears in any
   `FocusRegion.scopePath` or matches a `FocusRegion.identity`).
4. The node has a `cursorAnchor` set.
5. The node has descendants that pass any of (1)–(4).

Rule 5 is the tree-connectivity rule: containers that wouldn't
otherwise be relevant get emitted to keep the parent chain intact.
Tree reconstruction at the consumer relies on every emitted node's
`parentIdentity` referencing another emitted node (or nil for
roots).

Nodes that fail all five rules are skipped entirely. A typical
80×24 frame might have 100s of `PlacedNode`s but only 10–30
`AccessibilityNode`s after pruning.

### Hidden subtrees are skipped, not flagged

When a node has `accessibilityHidden(true)`, **no `AccessibilityNode`
is emitted for it or any of its descendants**. The descendants are
not "hidden but present"; they are absent from the tree.

The `hidden: Bool` field on the struct is reserved for the *extractor's
own bookkeeping* — specifically, when a containing node has a hidden
subtree but is itself emitted, the field can be set on that container
to advertise "I'm here but I have things below me you can't see."
Production consumers (browser bundle, SwiftUI bridge) should treat
`hidden == true` as informational only.

### Document order = layout reading order

The order in which `AccessibilityNode`s appear in the
`accessibilityNodes` array is the order the depth-first walk visited
their corresponding `PlacedNode`s — i.e., **layout reading order**,
not source order. Under RTL the walk is mirrored at the layout
level, so the array is naturally RTL-correct.

This is also what `interactionRegions` does today; we're following
established practice.

### Cursor anchor is on the node

Rationale:

- Built-in `TextField` and `SecureField` need a per-character anchor
  (the caret moves with input). Authoring this once per visited node
  is cheaper than asking the cursor-placement policy to walk into the
  draw payload.
- For nodes that don't care, `cursorAnchor` is `nil`; the
  cursor-placement policy uses the node's own origin (or another
  policy-driven default).
- Coordinates are **absolute** (already translated to surface
  coordinates) so consumers don't need bounds context to use them.
  The extractor does the translation during the walk — same place
  it already builds `interactionRegions`' absolute rects.

### Role inference (when not explicitly authored)

When a consumer hasn't called `accessibilityRole(_:)` explicitly:

1. Use the role on `SemanticMetadata.accessibilityRole` if set
   (built-in widgets set this; see ADR-0011).
2. Else, derive from `NodeKind`:
   - `Text` → no `AccessibilityNode` emitted unless other criteria
     trigger (label is the text content; role is inferred at the
     consumer as "static text").
   - Any container kind with no children passing the cut → no node
     emitted.
   - Any container with relevant descendants → `.group`.
3. Else, no node emitted.

When a consumer **has** called `accessibilityRole(_:)`, the authored
value wins outright.

### Label inference (when not explicitly authored)

When `accessibilityLabel` was not called explicitly:

1. For `.button`, `.link`, `.tab`, `.menuItem`, `.heading`: the
   label is the rendered text content of the node's text payload, if
   any. The extractor reads `DrawPayload.text(_:)` /
   `DrawPayload.richText(_:).plainText` for this.
2. For `.tabView` children: use the `tabItemLabel.title` if set.
3. For everything else: `label = nil`. Consumers may fall back to
   inner content traversal at their own layer.

Authored labels always win.

## Status

Accepted. Locked in before Phase 3b of the accessibility plan.
Phase 3b implements this struct; Phase 6 step 1 serializes it into
the wire format.

## Consequences

**Enabled:**

- One representation flows through five consumers (CLI runtime,
  embedded-host wire format, browser DOM, SwiftUI bridge, WASM web).
  No per-target invention.
- The flat-array shape diffs cleanly across frames. The extractor
  emits a fresh array per commit; downstream consumers either
  rebuild their tree (cheap; sparse trees) or diff against the
  previous frame's array (also cheap, by identity).
- Cursor placement, ARIA mounting, and SwiftUI accessibility traits
  all read the same field set. No per-target schema drift.
- The pruning rule keeps the tree small even on dense screens.
  Empirically: most cells aren't accessibility-relevant; the
  emitted set is roughly proportional to the count of focusable
  widgets.

**Foreclosed:**

- We cannot represent dynamic state (focus, scroll position) inside
  the node. Snapshot is structural; dynamic state lives in the
  trackers. Consumers compose the two at use time.
- We cannot represent overlap or z-order on nodes. `AccessibilityNode`
  has no z-index. Consumers should treat document order as
  authoritative for AT traversal regardless of visual stacking.
  (This is also how ARIA works.)
- We cannot represent disabled / unavailable state independently of
  role. If we need it later, it's a new optional field
  (`isEnabled: Bool` defaulting to true), not a structural change.

**Discipline imposed:**

- Authored modifiers that affect AT
  (`accessibilityLabel(_:)`, `accessibilityHint(_:)`,
  `accessibilityHidden(_:)`, `accessibilityLiveRegion(_:)`,
  `accessibilityCursorAnchor(_:)`, `accessibilityRole(_:)`) all write
  into `SemanticMetadata`. The extractor reads from
  `SemanticMetadata` and emits `AccessibilityNode`s. The two-step
  authoring → metadata → snapshot path is the only way to populate
  the tree.
- Wire-format extensions (Phase 6 step 1) translate
  `AccessibilityNode` 1:1. Adding a field to `AccessibilityNode` is
  a wire-format-version bump.
- Tests that assert AT structure read from `SemanticSnapshot
  .accessibilityNodes`, not from the raster output. Snapshot tests
  for the accessibility surface live alongside snapshot tests for
  the visual surface, but they're distinct fixtures.

**Migration / dependencies:**

- Depends on ADR-0011 (`AccessibilityRole` rename) for the role
  field type.
- The extractor changes are localized to
  [`Sources/Core/Semantics.swift`](../../Sources/Core/Semantics.swift).
  The walk already exists; we add a per-node emission step inside
  the existing `preVisit` / `postVisit` callbacks.
- `SemanticSnapshot` gains one new field. All existing call sites
  that construct it with the explicit init pick up the default
  empty array.
- New tests under `Tests/CoreTests/Accessibility/` exercise the
  pruning rule, the role inference, the label inference, and the
  parent-identity reconstruction.

The bet: a flat array of structurally-pure, statically-shaped nodes
gives us a representation that's cheap to extract, cheap to
serialize, cheap to diff, and rich enough for every downstream
consumer. Dynamic state stays where it lives; structure stays where
it lives.
