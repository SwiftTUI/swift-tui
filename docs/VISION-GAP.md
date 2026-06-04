# Vision Gap

This document is the **only gap register** in the documentation. Every other
document describes the code as it is at `HEAD`. This one records, concretely,
where the code falls short of the project's intent ([VISION.md](VISION.md)).

Each entry states what is **shipped today** and what is **not yet built**. None
of the unbuilt work is scheduled or promised here — this is a gap register, not
a roadmap.

Items that [VISION.md](VISION.md) declares out of scope are intentionally
omitted even when SwiftUI exposes a corresponding API.

## Accessibility

**Shipped.** The semantic substrate, the terminal linear renderer,
cursor-follows-focus, the Web/WASI ARIA tree, and the SwiftUI-host overlay that
pushes runtime focus to VoiceOver.

**Not yet built.**

- **Bidirectional focus.** Focus flows runtime → VoiceOver only.
  VoiceOver-originated focus traversal is not fed back into SwiftTUI's runtime
  focus.
- **A WCAG-referenced conformance suite** and **automated screen-reader
  testing.** Accessibility is verified by unit tests and guardrail scripts, not
  by a conformance checklist.

## Terminal-program embedding

**Shipped.** `TerminalView`, `TerminalProcessSession` over a pty, and the
`SwiftTUITerminalWorkspace` tabbed/split-pane layer, on macOS and Linux.

**Not yet built.**

- Sixel/Kitty graphics inside embedded panes.
- The Kitty keyboard protocol and OSC 99 notification namespacing.
- A pane-local selection/copy/scrollback mode.
- **Process reattachment** — reconnecting to a still-running child process
  after the host app restarts — and a daemon-backed session lifecycle.
- iOS and WASI builds of the embedding products.

## Layout and pipeline internals

**Shipped.** The seven-phase pipeline, off-main frame-tail execution, and
explicit work-stack paths for parts of measurement and placement.

**Not yet built.**

- **Fully iterative built-in layout.** The explicit work-stack migration is
  partial: built-in layout still recurses on the Swift call stack, so the
  frame-tail worker still runs with an enlarged stack rather than a bounded
  iterative engine.
- **`ViewGraph` decomposition.** Splitting `ViewGraph` into smaller types with
  cleaner ownership, dependency-aware (profile-gated) body re-evaluation,
  explicit context threading through resolve, and interning of `Identity`
  values are all design-only — no corresponding code.

## Structural identity

**Shipped.** The four-axis identity model is built and integrated: a distinct
opaque `ViewNodeID` for runtime lifetime, `StructuralPath` for ordered tree
position, `EntityIdentity` for explicit user/data identity, and a re-rooted
`StateSlotKey {owner: ViewNodeID, ordinal}` plus typed `StateGraphScopeID` for
state slots. The registration-alias layer and the `__SwiftTUIStateGraph` path
string-splice are gone; `@State`, focus, and animation continuity survive
identity-changing moves via the persistent `EntityRoutingTable`.

**Not yet built / accepted limits.**

- **Incremental retained-index patch.** `RetainedFrameIndex` is rebuilt in full
  every committed frame; `init(patching:with:)` currently delegates to a full
  rebuild, so the structural-fragment diff/reuse/prune path (the Stage 1 "L3"
  perf win) does not exist, and its `#if DEBUG` byte-equivalence oracle is inert
  (it compares two rebuilds). This is a deliberate deferral, not an oversight:
  the `synthetic-narrow-invalidation` corpus shows retained-index construction
  is a sub-1% slice of frame time and off the critical path (`resolve_ms`
  dominates at ~40%), so the incremental patcher was not worth its complexity.
- **Duplicate explicit ids — lifetime preservation.** Duplicate runtime
  identities (a non-unique `ForEach` id keypath, or a reused `.id(_:)`) are
  *contained* on the structural diff axis: each colliding sibling gets a distinct
  `EntityIdentity.occurrence`, and a non-fatal diagnostic fires (verified at the
  reconciliation level by `StructuralDiffTests`). Occurrence is a containment
  mechanism, not a lifetime key: it is assigned by resolved order, so a change to
  the collision *count* re-aligns the survivors and falls back to a conservative
  subtree rebuild — duplicate-id siblings get no cross-reorder
  `@State`/animation/focus preservation in that case. This is user error and
  undefined in SwiftUI too; the limit is recorded rather than modeled away.
  > **Node-store containment (G13, closed).** Same-collection duplicate ids now
  > receive *distinct `ViewNodeID`s*. `ViewGraph.nodeForIdentity` is
  > occurrence-aware: when a duplicate-occurrence sibling (`occurrence > 0`, e.g.
  > the second `7` in `ForEach([7, 7])`) collides on the `Identity` it shares with
  > the primary (`occurrence == 0`), it no longer adopts or evicts the primary's
  > node — it mints a fresh lifetime, so both siblings coexist as separate
  > `ViewNode`s with independent `@State`. Cross-frame routing of each occurrence
  > is handled by the entity-keyed `EntityRoutingTable`; the 1:1 `nodeIDByIdentity`
  > stays an *index* (last-writer-wins on the shared key is harmless because the
  > node store, entity routing, and parent→child teardown all track both siblings).
  > Teardown was corrected alongside: the deferred entity-routed removal prune now
  > keys on the frame-stamped `visitedThisFrame` signal instead of the stored
  > `wasVisitedThisFrame` bool, which stayed stale-`true` for a node in the frame it
  > disappeared and previously leaked gone entity-routed nodes in `nodesByNodeID`.
  > Verified by `EntityRoutingTests.duplicateIDsShouldResolveToDistinctViewNodeIDs`
  > and `…duplicateIDSiblingsTearDownWithoutOrphans` (a
  > `ForEach([7, 7]) → [7] → []` churn asserting the node store and routing table
  > return to empty). The collision-*count*-change limit above still holds.
- **Presentation GC keys on declaring `Identity`, not the owner entity.** Both
  Stage-4 typed edge carriers now have live consumers — `structuralEdgeRole`
  drives the retained-reuse viewport-barrier gate, and `DeclarationOwnerEdge`
  participates in `ResolvedNode` placement-equivalence/equality (so an owner
  change correctly defeats reuse). What is **not** done is routing the
  *presentation* garbage collector through `declarationOwnerEdge.owner`:
  `PresentationFamilyItemStore` still keys `declarativeItemsBySource` on the
  declaring view's runtime `Identity` and reaps sources not re-synced this frame.
  This is **deliberate**, not a missed migration: declarative presentation
  continuity across an identity-changing move is already preserved on the
  `item.id` axis (the activation-ordinal lookup searches every source by item id,
  so z-order and identity survive a re-parent), the declaration flows through the
  preference system carrying only `sourceIdentity` (not the owner entity), and
  `DeclarationOwnerEdge` is populated only for portal-backed presentations — so an
  entity-keyed GC would need an `Identity` fallback anyway. Re-keying the store to
  the owner entity is parked until it earns its cost.
- **Runtime registries key containment on `Identity`-as-structural-projection.**
  The commit-path invalidation engine reasons over `StructuralPath`, and the live
  resolve/retained classifiers carry real structural adjacency. But the per-frame
  runtime registries (focus, scroll, command, drop, pointer, preference,
  lifecycle) still evaluate subtree containment with `Identity.isAncestor` /
  `isDescendant`. This is **deliberate**, not a missed migration: `Identity` and
  `StructuralPath` are lossless mutual projections with an identical
  component-wise prefix relation, so these checks are already structurally
  correct; rewriting them to construct a `StructuralPath` per check would add an
  allocation to hot containment paths (pointer hit-testing, focus, scroll) for no
  behavioral gain — a net perf regression. Re-keying the stored `scopePath`
  element type to `StructuralPath` (to avoid per-check construction) is a large
  refactor parked until it earns its cost.

## Animation, transitions, and gestures

**Shipped.** Value-gated `.animation(_:value:)`, the timing-curve family
(bezier, spring, repeat/autoreverse), `.transition(_:)` with opacity and offset
effects, `matchedGeometryEffect`, `TapGesture`/`DragGesture` with
`.updating`/`.onChanged`/`.onEnded`, and a `Transaction` that carries animation
intent.

**Not yet built.** These carry the SwiftUI API shape but a narrower behavior.
Each is noted in a source doc comment; they are registered here so the
divergence from SwiftUI is recorded rather than silent.

- **Transition travel distance.** `.move(edge:)`, `.slide`, and `.push(from:)`
  slide a fixed ±10 cells rather than the transitioning view's own measured
  extent, so a view larger than 10 cells along the travel axis stays partly
  visible mid-transition. SwiftUI slides the view fully off its own bounds.
- **Custom `Transition` effects.** The transition compositor interpolates only
  opacity and offset; other modifiers applied inside a custom `Transition.body`
  are ignored, and there is no built-in `.scale` transition.
- **`Gesture.updating(_:body:)` transaction.** The `inout Transaction` passed to
  the closure is a no-op stand-in; mutations to it are discarded.
- **`matchedGeometryEffect` size.** It interpolates position only, not size; a
  matched pair that changes size snaps to the destination size for the whole
  animation.
- **`TapGesture` multi-tap timing.** Multi-tap counts have no inter-tap timeout:
  consecutive on-target taps count as a multi-tap regardless of elapsed time.
- **`Transaction` fields.** Only animation intent is exposed; other SwiftUI
  transaction fields are not.

## Canvas and drawing

**Shipped.** The continuous coordinate type system (`Point`/`CellPoint`/
`PixelPoint`, `PointerLocation` with sub-cell precision) and the `Canvas`
drawing surface with Braille subpixel rendering.

**Not yet built.** `Canvas`'s internal drawing coordinate model is still the
legacy integer-cell interface; it has not been migrated to the fractional
cell-coordinate model the rest of the geometry system uses.

## Image rendering and compositing

**Shipped.** PNG and JPEG images render as host presentation attachments, and
`SwiftTUIAnimatedImage` displays pre-composed frames by feeding PNG bytes
through the same image surface. `View.blendMode(_:)` works for terminal-cell
content such as text, fills, strokes, and borders.

**Not yet built.** Image pixels are not part of the blend-mode compositor.
`Image(...).blendMode(...)` and `AnimatedImage(...).blendMode(...)` still emit
unblended image attachments. Closing this gap means precomposing a blended
image variant: sampling the captured cell backdrop under the image's visible
bounds, applying the active `BlendMode` in linear sRGB, and presenting the
result through the existing attachment path so unblended images keep their fast
native path.

## Web packaging

**Shipped.** The `@swifttui/web` runtime and `@swifttui/build` helper packages
exist in the repo, and the localhost WebHost works.

**Not yet built.**

- **npm publishing** of `@swifttui/web` and `@swifttui/build`. The public
  pre-release uses GitHub release tarballs until npm publication is enabled.
- A **SwiftPM plugin** wrapping the web build flow.
- Localhost-WebHost extensions: a multi-scene host, remote/shared sessions, and
  lifecycle polish such as ephemeral ports, QR-code launch, and server
  discovery.

## Android

**Shipped.** `aarch64` Android cross-compilation with the Swift Android SDK.

**Not yet built.** `x86_64` Android currently fails: the vendored `swift-png`
LZ77/SIMD path imports Intel builtin intrinsics that are unavailable on that
target. Android is a cross-compilation target, not a declared SwiftPM platform.

## Performance

**Shipped.** The `Tools/TermUIPerf` harness records repeatable scenarios and
compares runs from frame diagnostics. `compare` has an opt-in **gate**:
`compare <base-aggregate> <candidate-aggregate> --gate` exits non-zero when a
watched lower-is-better metric shows a *real* regression (a median delta beyond
the variance-aware noise band), and `--require-improvement <metric…>` makes the
command additionally certify that each named metric shows a *real* improvement —
so a claimed perf win is provable and a regression is catchable.

**Not yet built.** The gate is not yet wired into CI as a required budget check:
it must be invoked explicitly against two aggregate runs, and there is no
phase-level (`resolve_ms`) aggregate metric — resolve-time cost is gated via its
`CPU seconds/frame` proxy, not a dedicated metric.

## Project and release

- **`0.9.0` public beta.** The intended next milestone — broadening
  contributors and stabilizing the surface toward `1.0.0` — has not been
  reached. The project is a single-maintainer `0.0.7` alpha.
- **Global documentation linting.** `AllPublicDeclarationsHaveDocumentation` is
  deliberately off. In its place, `generate_public_api_inventory.sh --check`
  runs a report-only ratchet that counts `canonical` public symbols with no
  `///` summary. It does not fail the gate yet; once the count reaches zero,
  flipping `ENFORCE_DOC_COMMENTS` makes it a hard gate. The global rule stays
  off because it would also force low-value comments onto package-only seams.
- **The name.** "SwiftTUI" collides with other terminal-UI projects in the
  Swift ecosystem. Whether to rename the package is unresolved.
