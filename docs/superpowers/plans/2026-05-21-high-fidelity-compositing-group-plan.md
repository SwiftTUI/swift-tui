# High-Fidelity Compositing Group Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement SwiftUI-shaped, order-sensitive `.blendMode(_:)` and
`.compositingGroup()` semantics for SwiftTUI's cell rasterizer.

**Architecture:** Replace the current merged `DrawMetadata.blendMode` shortcut with an
ordered draw-effect stack that survives resolve, place, draw extraction, and rasterization.
The rasterizer evaluates that stack as nested paint effects: regular blend modes stream
through as per-cell writes, while `compositingGroup()` flattens the inner subtree into a
temporary cell layer and composites that flattened layer back into its parent using the
outer effects.

**Tech Stack:** Swift 6.3.1, SwiftPM via `swiftly run swift ...`, Swift Testing,
SwiftTUICore draw/raster phases, SwiftTUIViews primitive modifiers, Bun repo gate.

---

## Current State

This branch already has a useful v1 `.blendMode(_:)` implementation:

- `View.blendMode(_:)` currently lowers through `DrawMetadata.blendMode`.
- `Rasterizer.write(...)` can composite source foreground/background colors over the
  current cell using `ResolvedTextStyle.composited(over:blendMode:)`.
- `paint(node:)` currently inherits a single optional blend mode through the draw tree.
- `docs/RENDER-PIPELINE.md` currently documents that `compositingGroup()` is not
  implemented.

That v1 shape is intentionally not enough for high-fidelity SwiftUI ordering semantics
because `DrawMetadata.merging(_:)` coalesces modifier state. The implementation worker
should replace, not extend, the optional `DrawMetadata.blendMode` path.

## Required Semantics

Order must be observable:

```swift
view.blendMode(.multiply).compositingGroup()
```

The inner view's blend mode applies while building the group layer. The flattened group
then composites normally into its parent unless another outer effect says otherwise.

```swift
view.compositingGroup().blendMode(.multiply)
```

The view first flattens into a group layer. That flattened layer then multiplies against
the parent backdrop.

```swift
ZStack {
  backdrop
  HStack {
    Text("A")
    Text("B")
  }
  .blendMode(.screen)
}
```

Without a compositing group, the blend mode remains a streaming leaf-cell effect: each
leaf write blends with the current parent raster backdrop.

```swift
ZStack {
  backdrop
  HStack {
    Text("A")
    Text("B")
  }
  .compositingGroup()
  .blendMode(.screen)
}
```

With a compositing group before the blend mode, the HStack's children flatten first, then
the resulting layer blends with the backdrop as one layer.

## Design Constraints

- Preserve the repo's existing modifier-order model. `ModifiedContent` and
  `PrimitiveViewModifier.resolve(content:in:)` already resolve inner content before
  applying the outer modifier.
- Do not add public APIs that expose internal effect storage.
- Keep `BlendMode` discrete and non-animatable.
- Keep the default compositing working space as linear sRGB.
- Respect clipping, dirty-row culling, wide-glyph continuation cells, foreign surfaces,
  canvas cells, layout borders, and post-child commands.
- Keep image attachments explicit. If image attachment blending cannot be represented
  faithfully in a terminal cell layer, document and test the fallback behavior rather
  than silently pretending images were blended.

## File Map

- Modify `Sources/SwiftTUICore/Draw/DrawEffects.swift`
  - New file. Owns `DrawEffect` and a compact ordered effect collection.
- Modify `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - Carries ordered draw effects from resolve.
- Modify `Sources/SwiftTUICore/Place/PlacedNode.swift`
  - Mirrors ordered draw effects through placement metadata.
- Modify `Sources/SwiftTUICore/Draw/DrawTreeTypes.swift`
  - Carries ordered draw effects on `DrawNode`.
- Modify `Sources/SwiftTUICore/Draw/DrawExtractor.swift`
  - Copies effects from placed nodes into draw nodes.
- Modify `Sources/SwiftTUIViews/Modifiers/StyleModifiers.swift`
  - Public `.blendMode(_:)` should use the new ordered effect modifier.
  - Add public `.compositingGroup()`.
- Modify `Sources/SwiftTUIViews/Modifiers/ViewMetadataModifiers.swift`
  - Add a primitive modifier for ordered draw effects or a small dedicated file beside it.
- Modify `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift`
  - Replace single inherited optional blend mode with ordered effect evaluation.
  - Add off-screen cell-layer rendering for compositing groups.
- Modify raster helper files touched by v1:
  - `Rasterizer+Sampling.swift`
  - `Rasterizer+PaintCommands.swift`
  - `Rasterizer+Borders.swift`
  - `Rasterizer+LayoutBorders.swift`
  - Keep their `blendMode` plumbing, but feed it from the ordered paint context.
- Modify `Sources/SwiftTUICore/Styling/ResolvedTextStyle.swift`
  - Keep the internal blend-aware compositing helper.
- Modify docs:
  - `docs/RENDER-PIPELINE.md`
  - `Sources/SwiftTUIViews/SwiftTUIViews.docc/Authoring-Views.md`
  - Generated public API baseline files after adding `.compositingGroup()`.
- Modify/add tests:
  - `Tests/SwiftTUIViewsTests/BlendModeModifierTests.swift`
  - `Tests/SwiftTUICoreTests/RasterizerTests.swift`
  - `Tests/SwiftTUICoreTests/StackSafetyRegressionTests.swift`
  - `Tests/SwiftTUITests/SwiftUISurfaceTests.swift`
  - `Examples/gallery/Tests/GalleryDemoViewsTests/BordersAndShapesTabTests.swift`

## Task 1: Add Ordered Draw Effects To Phase Products

**Purpose:** Create a first-class ordered effect stack that can express
`.blendMode(.multiply).compositingGroup()` differently from
`.compositingGroup().blendMode(.multiply)`.

- [ ] Add `Sources/SwiftTUICore/Draw/DrawEffects.swift`:

```swift
package enum DrawEffect: Equatable, Sendable {
  case blendMode(BlendMode)
  case compositingGroup
}

package struct DrawEffects: Equatable, Sendable {
  package var ordered: [DrawEffect]

  package init(_ ordered: [DrawEffect] = []) {
    self.ordered = ordered
  }

  package var isEmpty: Bool {
    ordered.isEmpty
  }

  package mutating func append(_ effect: DrawEffect) {
    ordered.append(effect)
  }

  package func appending(_ effect: DrawEffect) -> Self {
    var copy = self
    copy.append(effect)
    return copy
  }
}
```

- [ ] Add `drawEffects: DrawEffects` to `ResolvedNode`, `PlacedNodeResolvedMetadata`,
  `PlacedNode`, and `DrawNode`.
- [ ] Ensure every initializer defaults to `.init()`.
- [ ] Copy `ResolvedNode.drawEffects` into `PlacedNodeResolvedMetadata(resolved:)`.
- [ ] Copy placed `drawEffects` through `DrawPhaseProjection` and into `DrawNode`.
- [ ] Remove `DrawMetadata.blendMode` once the ordered effect path is in place.
- [ ] Update or add stack-size tests in `StackSafetyRegressionTests`.
  - If a size budget fails, prefer boxed storage for `DrawEffects` rather than simply
    raising the budget.

Focused verification:

```bash
swiftly run swift test --filter 'StackSafetyRegressionTests|BlendModeModifierTests'
```

Expected before the next task: compile may fail until the modifier path is updated; size
tests should not be ignored.

## Task 2: Replace Blend Metadata With Ordered Primitive Effects

**Purpose:** Make modifier order durable during resolve.

- [ ] Add a primitive modifier, preferably near `DrawMetadataModifier`:

```swift
public struct DrawEffectModifier: PrimitiveViewModifier {
  package var effect: DrawEffect

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.drawEffects.append(effect)
    return [node]
  }
}
```

- [ ] Change `.blendMode(_:)` to:

```swift
public func blendMode(_ blendMode: BlendMode) -> some View {
  modifier(DrawEffectModifier(effect: .blendMode(blendMode)))
}
```

- [ ] Add:

```swift
public func compositingGroup() -> some View {
  modifier(DrawEffectModifier(effect: .compositingGroup))
}
```

- [ ] Rewrite `BlendModeModifierTests` so they assert ordered effects, not merged metadata:
  - `.blendMode(.multiply)` produces `[.blendMode(.multiply)]`.
  - `.blendMode(.multiply).blendMode(.screen)` produces
    `[.blendMode(.multiply), .blendMode(.screen)]`.
  - `.blendMode(.multiply).compositingGroup()` produces
    `[.blendMode(.multiply), .compositingGroup]`.
  - `.compositingGroup().blendMode(.multiply)` produces
    `[.compositingGroup, .blendMode(.multiply)]`.

Focused verification:

```bash
swiftly run swift test --filter BlendModeModifierTests
```

Expected: modifier propagation tests pass and no code path still references
`DrawMetadata.blendMode`.

## Task 3: Introduce A Raster Paint Context And Layer Model

**Purpose:** Make the rasterizer capable of evaluating ordered effects without
recursing the draw tree or losing dirty-row behavior.

- [ ] Add a private paint context in `Rasterizer+Paint.swift`:

```swift
private struct PaintContext {
  var clip: CellRect?
  var activeBlendMode: BlendMode?
  var dirtyRows: Set<Int>?
  var dirtyRowRange: (min: Int, max: Int)?
}
```

- [ ] Add a private layer target:

```swift
private struct RasterLayer {
  var bounds: CellRect
  var cells: [[RasterCell]]
  var imageAttachments: [RasterImageAttachment]
}
```

- [ ] Keep the existing `write(..., blendMode:)` API; it is still the correct leaf-cell
  compositor.
- [ ] Refactor `paint(node:...)` so the stack frame carries `PaintContext` rather than a
  single inherited `BlendMode?`.
- [ ] Create a helper that applies non-group blend effects to the current context:

```swift
private func applyingStreamingEffects(
  _ effects: DrawEffects,
  to context: PaintContext
) -> PaintContext
```

This helper should use the last ordered `.blendMode` encountered since the most recent
group boundary for streaming paints. Do not collapse effects across a
`.compositingGroup`.

Focused verification:

```bash
swiftly run swift test --filter RasterizerTests/blendModeComposites
```

Expected: existing v1 blend tests still pass before group behavior lands.

## Task 4: Render Compositing Groups Into Temporary Cell Layers

**Purpose:** Make `.compositingGroup()` flatten the inner subtree before outer effects
blend it with the parent.

- [ ] Add a helper that splits a node's effects at the first compositing group:

```swift
private struct EffectSplit {
  var inner: DrawEffects
  var outer: DrawEffects
  var hasGroup: Bool
}
```

For `[.blendMode(.multiply), .compositingGroup, .blendMode(.screen)]`, `inner` is
`[.blendMode(.multiply)]`, `hasGroup` is `true`, and `outer` is
`[.blendMode(.screen)]`.

- [ ] When a node has no group effect, keep the normal streaming path.
- [ ] When a node has a group effect:
  - Allocate a `RasterLayer` for the visible intersection of `node.bounds` and active clip.
  - Paint the node's commands, children, and post-commands into that layer with the inner
    effects applied and with no access to the parent cells as backdrop.
  - Composite the layer's lead cells back into the parent target using the outer effects and
    the parent context's active blend mode.
  - Preserve continuation cells by writing only lead cells via `write(...)`; let `write`
    clear/rebuild continuation cells.
  - Carry image attachments out only when their semantics are representable. If the image
    cannot be blended into the cell layer, keep current unblended attachment behavior and
    document the limitation in `RENDER-PIPELINE.md`.
- [ ] Ensure nested groups recurse through the same path.
- [ ] Ensure `visibleIdentities` is still recorded before dirty-row culling, matching the
  existing animation visibility contract.

Focused verification:

```bash
swiftly run swift test --filter 'RasterizerTests/compositingGroup|RasterizerTests/blendMode'
```

Expected: new group tests fail before implementation and pass after.

## Task 5: Pin The Ordering Semantics With Tests

**Purpose:** Make the high-fidelity behavior executable and hard to regress.

Add tests in `Tests/SwiftTUICoreTests/RasterizerTests.swift` using small hand-built
`DrawNode` trees with explicit effects:

- [ ] `blendModeWithoutGroupStreamsPerLeafAgainstBackdrop`
  - Backdrop: one blue cell.
  - Two overlapping child text/fill writes with `.blendMode(.screen)`.
  - Assert each write sees the current parent cell.
- [ ] `blendModeBeforeCompositingGroupDoesNotBlendTheFlattenedGroupWithBackdrop`
  - Effects: `[.blendMode(.multiply), .compositingGroup]`.
  - Assert the group output does not multiply against the external backdrop.
- [ ] `blendModeAfterCompositingGroupBlendsFlattenedGroupWithBackdrop`
  - Effects: `[.compositingGroup, .blendMode(.multiply)]`.
  - Assert the flattened group multiplies against the external backdrop.
- [ ] `nestedCompositingGroupsApplyInnerAndOuterBlendModesInOrder`
  - Outer and inner groups should each have a distinct, assertable color result.
- [ ] `compositingGroupRespectsClipBounds`
  - Group content outside clip must not appear in the parent surface.
- [ ] `compositingGroupPreservesWideGlyphContinuationCells`
  - A wide glyph inside a group should produce a lead cell plus continuation cell after
    compositing.
- [ ] `compositingGroupPreservesPostChildInsetBorderOrdering`
  - Use an inset border over child content and assert the border still wins.

Add tests in `Tests/SwiftTUITests/SwiftUISurfaceTests.swift` through public API:

- [ ] `.blendMode(.multiply).compositingGroup()` and
  `.compositingGroup().blendMode(.multiply)` produce different raster colors in the same
  authored `ZStack`.
- [ ] `.background(...).blendMode(...)` differs from
  `.blendMode(...).background(...)` where SwiftUI order should differ.

Focused verification:

```bash
swiftly run swift test --filter 'RasterizerTests/compositingGroup|SwiftUISurfaceTests/compositingGroup'
```

## Task 6: Update Docs, Gallery, And API Baseline

**Purpose:** Ship the public surface and make visual verification easy.

- [ ] Update `docs/RENDER-PIPELINE.md`:
  - Remove the current "not implemented" wording.
  - Document ordered draw effects.
  - Document the image attachment limitation if Task 4 leaves one.
- [ ] Update `Sources/SwiftTUIViews/SwiftTUIViews.docc/Authoring-Views.md`:
  - Mention `.blendMode(_:)` and `.compositingGroup()`.
- [ ] Update `Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift`:
  - Keep the existing "Blend Modes" section.
  - Add two small cards that visibly contrast:
    - `blend then group`
    - `group then blend`
- [ ] Update gallery smoke expectations if the section text changes.
- [ ] Regenerate the public API baseline:

```bash
Scripts/generate_public_api_inventory.sh
```

Expected generated changes:

- `docs/.public-api-baseline.txt` gains `SwiftTUIViews.View.compositingGroup()`.
- `docs/PUBLIC_API_BASELINE.md` generated date/member counts update.

Focused verification:

```bash
swiftly run swift test --package-path Examples/gallery --filter BordersAndShapesTabTests/rendersNonEmptySurface
Scripts/generate_public_api_inventory.sh --check
```

## Task 7: Final Verification And Cleanup

- [ ] Format touched Swift files:

```bash
swift format format -i --configuration .swift-format.json Sources/ Tests/ Examples/gallery/Sources/ Examples/gallery/Tests/
```

- [ ] Run focused tests one more time:

```bash
swiftly run swift test --filter 'BlendModeModifierTests|RasterizerTests/(blendMode|compositingGroup)|SwiftUISurfaceTests/compositingGroup'
swiftly run swift test --package-path Examples/gallery --filter BordersAndShapesTabTests/rendersNonEmptySurface
```

- [ ] Run the repo gate:

```bash
bun run test
```

- [ ] Confirm no stale internal path remains:

```bash
rg -n "DrawMetadata\\.blendMode|blendMode:" Sources Tests
```

Expected: no `DrawMetadata.blendMode` field or tests asserting metadata blend mode. It is fine
for raster helper parameters and public `.blendMode(_:)` call sites to remain.

- [ ] Run whitespace check:

```bash
git diff --check
```

## Implementation Notes

- Treat current `ResolvedTextStyle.composited(over:blendMode:)` and
  `Rasterizer.write(..., blendMode:)` as good primitives. The high-fidelity work should
  change when and where those primitives are called, not rewrite color math.
- The first correct version can allocate a temporary layer for the group's visible bounds.
  Optimize allocations only after tests are green.
- Be conservative with incremental rasterization. If a grouped subtree touches dirty rows in
  a way the existing damage adapter cannot prove, force the fresh-raster fallback rather than
  returning an incomplete retained surface.
- Keep terminal cell semantics explicit: a grouped layer has glyph, foreground, background,
  hyperlink, and continuation cells. It is not a pixel image.
- Do not silently coalesce multiple blend effects. The plan depends on preserving authored
  modifier order until raster evaluation.

## Done Criteria

- `.blendMode(_:)` remains public and order-sensitive.
- `.compositingGroup()` is public and documented.
- `.blendMode(...).compositingGroup()` and `.compositingGroup().blendMode(...)` have
  distinct tested raster outputs.
- Existing v1 blend mode tests still pass for all six built-in modes.
- Gallery has a visual comparison for group ordering.
- Public API baselines are regenerated.
- `bun run test` passes.
