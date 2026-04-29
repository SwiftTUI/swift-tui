---
title: "refactor: border / stroke simplification"
type: refactor
status: active
date: 2026-04-26
---

# Border / Stroke Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the framework's four parallel border/stroke "stories" down to two coherent systems (`BorderSet` palette + `StrokeStyle` configuration), shift the canonical default from full-cell box-drawing glyphs to half-block glyphs, and delete sugar duplicates.

**Architecture:**
- Move `placement` from `BorderSet` to `StrokeStyle` so glyph palette and layout placement are orthogonal.
- Collapse `Placement` enum from three cases (`.outset` / `.inset` / `.decorative`) to two (`.outset` / `.inset`) — `.decorative` has no code-path distinction from `.outset` today.
- Change the canonical default for `StrokeStyle.init()` (and therefore `Shape.stroke(...)`, `chromeStrokeBorder(...)`, every implicit-default container chrome) from `BorderSet.single` to `BorderSet.outerHalfBlock`. `View.border(...)` already defaults to the same glyph palette; align placement.
- Delete the `.single → .rounded` rasterizer auto-upgrade entirely. Callers that want rounded corners against a radiused-rectangle geometry now pass `.rounded` explicitly. The `resolvedStrokeBorderSet(for:strokeStyle:)` helper becomes a pass-through and is removed.
- Delete sugar duplicates: `BorderSet.presentationChrome`, `StrokeStyle.normal`, `StrokeStyle.outerHalfBlock`, `StrokeStyle.presentationChrome`.

**Tech Stack:** Swift 6, Swift Testing (`@Test`, `#expect`), SwiftPM, snapshot fixtures recorded via `PARALLEL_RECORD_RENDERED_FIXTURES=1`.

---

## Decisions baked into this plan (correct before execution if any are wrong)

| # | Decision | Why |
|---|---|---|
| D1 | Move `placement` field from `BorderSet` → `StrokeStyle`. | Orthogonalizes glyph choice from layout placement; cleanly enables deleting `presentationChrome` (which is `innerHalfBlock` + different placement). |
| D2 | Collapse `Placement` enum to `.outset` / `.inset` (delete `.decorative`). | `.decorative` has no code-path distinction from `.outset` anywhere in `Sources/` — only in docstrings. It's a documentation distinction masquerading as a behavior distinction. |
| D3 | New canonical default = `BorderSet.outerHalfBlock` (top `▀`, bottom `▄`, sides `▌`/`▐`, corners `▛▜▙▟`) with `.outset` placement. | Internally consistent half-block palette; corners that don't look broken; matches what `View.border(...)` already defaults to. |
| D4 | **Delete** the `.single → .rounded` rasterizer auto-upgrade entirely. The `resolvedStrokeBorderSet` helper becomes a pass-through and is removed. Any caller that wants `╭╮╰╯` corners on a radiused rectangle passes `borderSet: .rounded` explicitly. | Removes hidden behavior that was a workaround for the old single-line default. The new default already has corner glyphs designed for rounded chrome. Callers stating their intent explicitly is clearer than the rasterizer second-guessing them. |
| D5 | Removing `placement` from `BorderSet` is a public API break. Accept it. | Pre-1.0 framework. The cleaner internal surface is worth the migration ask for any external consumers. (The only known external consumer — `Examples/` — only constructs `BorderSet` via static presets, not the public initializer's `placement:` argument.) |
| D6 | **Out of scope** for this plan: hand-rolled glyph systems in tabs (`TabViewStyles.swift`), tables (`TableBorderGlyphs`), scrollbars (`DrawExtractor+Lists.swift`), sliders (`SelectionAndValueSupport.swift`), progress (`ProgressView.swift`), charts (`ChartSupport.swift`), and metric tracks (`MetricTrackSupport.swift`). These are widget-internal glyph palettes, not "border/stroke" decisions, and most have distinct visual identities that shouldn't auto-track the canonical default. They are catalogued in the audit as "System 4" and remain unchanged. A follow-up plan can address them piecewise. |
| D7 | After Task 6, `View.border(...)`'s placement changes from `.decorative` → `.outset`. Code paths are identical today, so this is a no-op behaviorally. | See D2 — `.decorative` and `.outset` are the same code path. |

---

## File map

**Created:**
- `Sources/Core/StrokeStyle+Placement.swift` (new — but only if we want a separate file; otherwise place new types/extensions inline in `Styling.swift`. Tasks below put them inline.)
- `docs/proposals/BORDERS_AND_STROKES.md` (new architecture doc, written in Task 9)

**Modified:**
- `Sources/Core/BorderSet.swift` — remove `placement` field, remove `Placement` enum (move it), remove `presentationChrome`, simplify the public initializer
- `Sources/Core/Styling.swift` — add `placement` to `StrokeStyle`, change `init` default, delete `.normal` / `.outerHalfBlock` / `.presentationChrome` presets
- `Sources/Core/LayoutEngine.swift:1479` — read placement from `StrokeStyle` instead of `BorderSet`
- `Sources/Core/DrawExtractor.swift:314` — same
- `Sources/Core/Rasterizer.swift:2795-2815` — comment update only (auto-upgrade logic unchanged)
- `Sources/Core/Snapshots.swift:739-760` — drop `presentationChrome` case from `describeBorderSetName`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift` — adjust border draw payload to thread `StrokeStyle.placement` through (specifically the `.border(...)` enum case at line 1055)
- `Sources/View/Modifiers/ViewModifiers.swift:895` — `BorderModifier` carries `placement` instead of relying on `BorderSet.placement`
- `Sources/View/Modifiers/StyleModifiers.swift:160-235` — `View.border(...)` overloads pass `.outset` placement
- `Sources/View/Presentation/PresentationModifiers.swift:494` — replace `.presentationChrome` StrokeStyle preset with explicit `StrokeStyle(borderSet: .innerHalfBlock, placement: .inset)` (or `.outset` — see Task 5 sub-decision)
- `Tests/CoreTests/BorderSetTests.swift` — update tests that assert `placement` lives on `BorderSet`
- `Tests/CoreTests/LayoutBehaviorBorderEqualityTests.swift` — refresh if it checks placement
- `Tests/TerminalUITests/BorderRenderingTests.swift` — refresh assertions
- `Tests/TerminalUITests/BorderModifierLayoutTests.swift` — refresh assertions
- `Tests/TerminalUITests/Fixtures/**/*.txt` — re-record snapshot fixtures (~115 files; many won't change because they don't render bordered chrome)

**Deleted:**
- No files deleted.

---

## Task 1: Lock in baseline behavior with regression tests

Goal: Before changing anything, write tests that pin down today's defaults so the diff in Task 6 is explicit and reviewable.

**Files:**
- Test: `Tests/CoreTests/BorderStrokeDefaultsTests.swift` (create)

- [ ] **Step 1.1: Create the baseline test file**

Create `Tests/CoreTests/BorderStrokeDefaultsTests.swift`:

```swift
import Testing

@testable import Core

/// Baseline test capturing the framework's canonical border/stroke
/// defaults. Updated as part of the border/stroke simplification plan;
/// each `@Test` lists the *expected post-simplification* default and
/// the *current pre-simplification* default it replaces. After Task 6
/// these tests should pass; before Task 6 the marked tests fail.
@Test("StrokeStyle.init produces outerHalfBlock by default")
func strokeStyleInitDefaultIsOuterHalfBlock() {
  let style = StrokeStyle()
  // PRE-SIMPLIFICATION: this would be `.single`.
  // POST-TASK-6: expected to be `.outerHalfBlock`.
  #expect(style.borderSet == .outerHalfBlock)
}

@Test("StrokeStyle.init defaults placement to .outset")
func strokeStyleInitDefaultPlacementIsOutset() {
  let style = StrokeStyle()
  // POST-TASK-2: StrokeStyle gains a placement field, defaults .outset.
  #expect(style.placement == .outset)
}

@Test("StrokeStyle.init lineWidth defaults to 1")
func strokeStyleInitDefaultLineWidth() {
  #expect(StrokeStyle().lineWidth == 1)
}

@Test("BorderSet.outerHalfBlock has consistent half-block corners")
func outerHalfBlockCornersAreConsistent() {
  let set = BorderSet.outerHalfBlock
  #expect(set.top == "▀")
  #expect(set.bottom == "▄")
  #expect(set.left == "▌")
  #expect(set.right == "▐")
  #expect(set.topLeading == "▛")
  #expect(set.topTrailing == "▜")
  #expect(set.bottomLeading == "▙")
  #expect(set.bottomTrailing == "▟")
}
```

- [ ] **Step 1.2: Run the new tests; the placement test will fail until Task 2; the default-borderset test will fail until Task 6**

Run:
```bash
swift test --filter BorderStrokeDefaultsTests 2>&1 | tail -30
```

Expected:
- `outerHalfBlockCornersAreConsistent` PASS (today's glyphs already match).
- `strokeStyleInitDefaultLineWidth` PASS.
- `strokeStyleInitDefaultPlacementIsOutset` FAIL (compile error — no `placement` field on `StrokeStyle` yet).

The compile error means the file won't even build until Task 2. That's intentional — it's the spec we'll satisfy.

- [ ] **Step 1.3: Mark the file as expected-to-fail-until-X; commit**

Add an explanatory header comment to the file pointing to this plan, then commit:

```bash
git add Tests/CoreTests/BorderStrokeDefaultsTests.swift
git commit -m "test: add baseline assertions for border/stroke defaults

Pre-implementation regression test for plan
docs/plans/2026-04-26-003-border-stroke-simplification-plan.md.
Some assertions intentionally fail until Tasks 2 and 6 land."
```

Note: This commit will leave the test target in a non-compiling state. If that's unacceptable for the project's commit-must-build invariant, comment out the `#expect(style.placement == ...)` line and uncomment it in Task 2's commit instead.

---

## Task 2: Add `placement` to `StrokeStyle` (additive, no behavior change)

Goal: Plumb a new `placement` field through `StrokeStyle` and the rasterizer/layout call sites that need it. Behavior is preserved by reading `BorderSet.placement` as a fallback when `StrokeStyle.placement` matches its default.

**Files:**
- Modify: `Sources/Core/Styling.swift:514-525`
- Modify: `Sources/Core/LayoutEngine.swift:1465-1490` (the `borderInsets` helper)
- Modify: `Sources/Core/DrawExtractor.swift:300-330` (the inset-vs-outset branch around line 314)
- Modify: `Sources/Core/RenderTreeAndSemanticsTypes.swift:1050-1070` (the `.border(...)` payload, threading placement)
- Test: `Tests/CoreTests/BorderStrokeDefaultsTests.swift` (uncomment placement test if it was commented in Task 1)

- [ ] **Step 2.1: Add the placement field to StrokeStyle**

Edit `Sources/Core/Styling.swift` (around line 514):

```swift
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int
  public var borderSet: BorderSet
  public var placement: Placement

  public enum Placement: Equatable, Sendable {
    case outset
    case inset
  }

  public init(
    lineWidth: Int = 1,
    borderSet: BorderSet = .single,
    placement: Placement = .outset
  ) {
    self.lineWidth = max(1, lineWidth)
    self.borderSet = borderSet
    self.placement = placement
  }
}
```

Note: `StrokeStyle.Placement` only has two cases (`.outset`, `.inset`). `.decorative` from `BorderSet.Placement` is dropped per D2.

- [ ] **Step 2.2: Add a transitional shim that resolves the effective placement**

Add a private extension to `StrokeStyle` that produces the effective placement during the migration window (until Task 4 deletes `BorderSet.placement`):

```swift
extension StrokeStyle {
  /// The placement that should drive layout/draw decisions. While
  /// `BorderSet.placement` still exists (Tasks 2-3), this prefers a
  /// non-default `BorderSet.placement` over the StrokeStyle's own,
  /// preserving behavior for callers that haven't migrated yet.
  /// After Task 4 this becomes `placement` directly.
  var effectivePlacement: Placement {
    switch borderSet.placement {
    case .outset: return placement
    case .decorative: return placement  // .decorative ≡ .outset
    case .inset: return .inset
    }
  }
}
```

- [ ] **Step 2.3: Replace the two real consumers of `BorderSet.placement` with `StrokeStyle.effectivePlacement`**

Edit `Sources/Core/LayoutEngine.swift:1479`:

Before:
```swift
guard set.placement != .inset else { return EdgeInsets() }
```

After (the surrounding helper signature must be threaded with `StrokeStyle` instead of bare `BorderSet`. Inspect the calling context — `borderInsets` is called from one place; that call site can pass the StrokeStyle's effectivePlacement as a separate argument):

```swift
guard placement != .inset else { return EdgeInsets() }
```

And update the helper signature to take `placement: StrokeStyle.Placement` alongside `set: BorderSet`. Find every caller of `borderInsets` and thread the placement through.

Edit `Sources/Core/DrawExtractor.swift:314`:

Before:
```swift
if set.placement == .inset {
```

After:
```swift
if placement == .inset {
```

Same threading work — caller must supply `placement`.

- [ ] **Step 2.4: Build and run the full test suite to verify zero behavior change**

Run:
```bash
swift build 2>&1 | tail -20
swift test 2>&1 | tail -40
```

Expected: all tests pass. Snapshot fixtures unchanged.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/Core/Styling.swift \
        Sources/Core/LayoutEngine.swift \
        Sources/Core/DrawExtractor.swift \
        Sources/Core/RenderTreeAndSemanticsTypes.swift \
        Tests/CoreTests/BorderStrokeDefaultsTests.swift
git commit -m "feat(core): add placement field to StrokeStyle (additive)

Threads StrokeStyle.placement through the layout and draw paths
alongside the existing BorderSet.placement field. Behavior is
preserved during the migration window via effectivePlacement,
which prefers a non-default BorderSet.placement to the StrokeStyle's
own. Step 1 of the border/stroke simplification plan."
```

---

## Task 3: Migrate internal call sites that rely on `BorderSet.placement`

Goal: After this task, every internal site that currently expresses placement via `BorderSet.placement` instead expresses it via `StrokeStyle.placement` (or the equivalent on `BorderModifier`). Then `BorderSet.placement` can be deleted in Task 4.

**Files:**
- Modify: `Sources/View/Modifiers/ViewModifiers.swift:895` (BorderModifier struct — add `placement` field)
- Modify: `Sources/View/Modifiers/StyleModifiers.swift:160-235` (View.border overloads — pass placement)
- Modify: `Sources/View/Presentation/PresentationModifiers.swift:494` (use `.innerHalfBlock` + explicit `.inset` placement)
- Modify any other internal site that reads `BorderSet.placement`. Confirm with: `grep -rn "\.placement" Sources/ --include="*.swift" | grep -v "//"`

- [ ] **Step 3.1: Add placement to BorderModifier**

Edit `Sources/View/Modifiers/ViewModifiers.swift` around line 895:

```swift
package struct BorderModifier: ViewModifier {
  package var set: BorderSet
  package var placement: StrokeStyle.Placement
  // …existing fields…
}
```

Update its initializer and all read sites. The renderer reads from this struct; thread `placement` through to wherever it currently reaches into `set.placement`.

- [ ] **Step 3.2: Update View.border() overloads to pass placement explicitly**

Edit `Sources/View/Modifiers/StyleModifiers.swift` around lines 160-235. The three public overloads currently default `set: BorderSet = .outerHalfBlock` (which today carries `.decorative` placement). They should now also default `placement` explicitly:

```swift
public func border<S: ShapeStyle>(
  _ style: S = SemanticShapeStyle.foreground,
  set: BorderSet = .outerHalfBlock,
  placement: StrokeStyle.Placement = .outset,
  sides: Edge.Set = .all
) -> some View {
  borderModified(
    set: set,
    placement: placement,
    foreground: BorderEdgeStyle(AnyShapeStyle(style)),
    background: nil,
    blend: nil,
    blendPhase: 0,
    sides: sides
  )
}
```

Apply to all three overloads (lines 160, 176, 201). Update `borderModified` (line 217) and `BorderModifier` constructor.

NOTE: This changes the *default placement* of `View.border(...)` from `.decorative` (today, via `outerHalfBlock`) to `.outset` (explicit new default). Per D7 this is a no-op since `.decorative` and `.outset` use the same code path. Confirm with the test run in step 3.5.

- [ ] **Step 3.3: Migrate PresentationModifiers.swift**

The presentation chrome at line 494 currently uses `style: .presentationChrome`. The `.presentationChrome` StrokeStyle preset (defined in `Styling.swift:536`) wraps `BorderSet.presentationChrome` (which is `innerHalfBlock` glyphs + `.decorative` placement).

Replace with the explicit equivalent:

```swift
RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
  .terminalBorder(.accent),
  style: StrokeStyle(borderSet: .innerHalfBlock, placement: .outset)
)
```

(`.outset` — not `.inset` — because the original `.decorative` ≡ `.outset` per D2/D7. The interior placement of `innerHalfBlock` glyphs is a *visual* property of the glyphs themselves, independent of the layout placement.)

- [ ] **Step 3.4: Verify no remaining reads of `BorderSet.placement` outside its own type**

Run:
```bash
grep -rn "\.placement\b" Sources/ --include="*.swift" \
  | grep -v "BorderSet\.swift\|Styling\.swift" \
  | grep -v "// " \
  | grep -v "Toolbar\|toolbar\|Layout\.swift"  # toolbar/layout have unrelated 'placement' uses
```

Expected: empty output (no internal site still reads `BorderSet.placement`). If anything appears, migrate it.

- [ ] **Step 3.5: Build, test, verify zero snapshot changes**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -40
```

Expected: all tests pass, snapshot fixtures bit-identical to before (no `git diff` in `Tests/.../Fixtures/`).

- [ ] **Step 3.6: Commit**

```bash
git add Sources/View/ Sources/Core/
git commit -m "refactor(view): route placement through StrokeStyle/BorderModifier

Migrates every internal consumer of BorderSet.placement to express
the same intent via StrokeStyle.placement (Shape.stroke path) or
BorderModifier.placement (View.border path). No behavior change —
the rasterizer's effective-placement shim still defers to
BorderSet.placement when set. Step 2 of the border/stroke
simplification plan."
```

---

## Task 4: Remove `placement` from `BorderSet`; collapse `Placement` enum

Goal: Drop `BorderSet.placement` and `BorderSet.Placement`. `StrokeStyle.Placement` becomes the single placement enum. Glyph palette and placement are now fully orthogonal.

**Files:**
- Modify: `Sources/Core/BorderSet.swift:1-52, 115-139` (remove placement field, enum, init param; remove `placement:` from preset constructors)
- Modify: `Sources/Core/Styling.swift` (delete `effectivePlacement` shim from Task 2; `StrokeStyle.placement` is now the source of truth)
- Modify: `Tests/CoreTests/BorderSetTests.swift` (remove placement-related assertions)

- [ ] **Step 4.1: Delete the placement field, enum, and constructor parameter from BorderSet**

Edit `Sources/Core/BorderSet.swift`. Remove:
- The `Placement` enum (lines 20-24)
- The `placement: Placement` field (line 18)
- The `placement: Placement = .outset` initializer parameter and assignment (lines 35, 50)
- The `placement: .decorative)` and `placement: .inset)` arguments on the `outerHalfBlock`, `innerHalfBlock`, and `presentationChrome` static lets (lines 119, 127, 139)

The simplified BorderSet:

```swift
public struct BorderSet: Equatable, Sendable {
  public var top: String
  public var bottom: String
  public var left: String
  public var right: String
  public var topLeading: String
  public var topTrailing: String
  public var bottomLeading: String
  public var bottomTrailing: String
  public var middleLeading: String
  public var middleTrailing: String
  public var middle: String
  public var middleTop: String
  public var middleBottom: String

  public init(
    top: String, bottom: String, left: String, right: String,
    topLeading: String, topTrailing: String,
    bottomLeading: String, bottomTrailing: String,
    middleLeading: String = "",
    middleTrailing: String = "",
    middle: String = "",
    middleTop: String = "",
    middleBottom: String = ""
  ) {
    self.top = top
    self.bottom = bottom
    self.left = left
    self.right = right
    self.topLeading = topLeading
    self.topTrailing = topTrailing
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.middleLeading = middleLeading
    self.middleTrailing = middleTrailing
    self.middle = middle
    self.middleTop = middleTop
    self.middleBottom = middleBottom
  }
}
```

- [ ] **Step 4.2: Delete the effectivePlacement shim from Styling.swift**

The shim added in Task 2 step 2.2 is no longer needed. Delete the `extension StrokeStyle { var effectivePlacement: ... }` block. Update the layout/draw call sites to use `placement` directly.

- [ ] **Step 4.3: Update BorderSetTests.swift**

Edit `Tests/CoreTests/BorderSetTests.swift`. Remove tests that mention `placement` or `.outset`/`.inset`/`.decorative` on BorderSet. Examples:

- "BorderSet stores 13 string slots" — remove `placement: .outset` from the call and the `#expect(set.placement == .outset)` line.
- "BorderSet placement defaults to outset" — delete the entire test.

- [ ] **Step 4.4: Build and test**

```bash
swift build 2>&1 | tail -20
swift test 2>&1 | tail -40
```

Expected: all pass. Snapshot fixtures unchanged.

- [ ] **Step 4.5: Commit**

```bash
git add Sources/Core/BorderSet.swift Sources/Core/Styling.swift Tests/CoreTests/BorderSetTests.swift
git commit -m "refactor(core): remove placement from BorderSet

BREAKING: BorderSet.placement and BorderSet.Placement are removed.
Placement now lives exclusively on StrokeStyle.Placement (.outset
and .inset; .decorative collapsed into .outset since they shared
the same code path). Step 3 of the border/stroke simplification
plan."
```

---

## Task 5: Delete `BorderSet.presentationChrome` and `StrokeStyle.presentationChrome`

Goal: With placement orthogonalized, `presentationChrome` is now an exact glyph-level duplicate of `innerHalfBlock`. Delete both presets.

**Files:**
- Modify: `Sources/Core/BorderSet.swift:135-139` (delete `presentationChrome`)
- Modify: `Sources/Core/Styling.swift:536` (delete `StrokeStyle.presentationChrome`)
- Modify: `Sources/Core/Snapshots.swift:748` (delete the `case .presentationChrome` row from `describeBorderSetName`)

- [ ] **Step 5.1: Delete BorderSet.presentationChrome**

Edit `Sources/Core/BorderSet.swift`. Delete the `presentationChrome` static let (lines 129-139) and its docstring.

- [ ] **Step 5.2: Delete StrokeStyle.presentationChrome**

Edit `Sources/Core/Styling.swift`. Delete:
```swift
public static let presentationChrome = StrokeStyle(borderSet: .presentationChrome)
```

- [ ] **Step 5.3: Update Snapshots.swift**

Edit `Sources/Core/Snapshots.swift:748`. Delete the line:
```swift
case .presentationChrome: return "presentationChrome"
```

- [ ] **Step 5.4: Verify no remaining external references**

```bash
grep -rn "presentationChrome" Sources/ Tests/ Examples/ --include="*.swift"
```

Expected: empty output. If anything still references it, replace with `StrokeStyle(borderSet: .innerHalfBlock, placement: ...)`.

The Task 3 update to `PresentationModifiers.swift:494` already replaced the one internal user; this step is the audit.

- [ ] **Step 5.5: Build, test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -30
```

Expected: all pass. Snapshot fixtures unchanged.

- [ ] **Step 5.6: Commit**

```bash
git add Sources/Core/BorderSet.swift Sources/Core/Styling.swift Sources/Core/Snapshots.swift
git commit -m "refactor(core): delete presentationChrome border preset

presentationChrome was a glyph-level duplicate of innerHalfBlock
distinguished only by placement — which is now a StrokeStyle field.
Callers that want innerHalfBlock glyphs with non-inset placement
can now express that directly. Step 4 of the border/stroke
simplification plan."
```

---

## Task 6: Change `StrokeStyle.init` default + re-record snapshots

Goal: Flip the canonical default. After this commit, every implicit-default container chrome in the framework draws half-block glyphs.

**Files:**
- Modify: `Sources/Core/Styling.swift:520` (change init default)
- Modify: `Sources/Core/Rasterizer.swift:2795-2815` (comment update; logic unchanged)
- Modify: `Tests/TerminalUITests/Fixtures/**/*.txt` (re-recorded fixtures)

- [ ] **Step 6.1: Confirm baseline test will flip from FAIL → PASS**

Re-run the baseline test from Task 1:
```bash
swift test --filter BorderStrokeDefaultsTests 2>&1 | tail -20
```

Expected (PRE-step 6.2): `strokeStyleInitDefaultIsOuterHalfBlock` FAILS.

- [ ] **Step 6.2: Change the default**

Edit `Sources/Core/Styling.swift:520`:

Before:
```swift
public init(
  lineWidth: Int = 1,
  borderSet: BorderSet = .single,
  placement: Placement = .outset
) {
```

After:
```swift
public init(
  lineWidth: Int = 1,
  borderSet: BorderSet = .outerHalfBlock,
  placement: Placement = .outset
) {
```

- [ ] **Step 6.3: Delete the auto-upgrade helper and inline its callers**

Edit `Sources/Core/Rasterizer.swift:2795-2815`. Delete the `resolvedStrokeBorderSet(for:strokeStyle:)` function entirely:

```swift
// DELETE THIS WHOLE BLOCK (lines 2795–2815):
private func resolvedStrokeBorderSet(
  for geometry: ShapeGeometry,
  strokeStyle: StrokeStyle
) -> BorderSet {
  if strokeStyle.borderSet == .single,
    case .roundedRectangle(let radius) = geometry,
    radius > 0
  {
    return .rounded
  }
  return strokeStyle.borderSet
}
```

Now find the two call sites that use it (`Rasterizer.swift:1353` and `Rasterizer.swift:2023`) and inline the field access:

Before (line 1353):
```swift
let resolvedSet = resolvedStrokeBorderSet(
  for: geometry,
  strokeStyle: strokeStyle
)
```

After:
```swift
let resolvedSet = strokeStyle.borderSet
```

Apply the same change at line 2023. After this, `resolvedSet` is just a local alias — feel free to inline it further at each call site (replace `resolvedSet` with `strokeStyle.borderSet`) and remove the binding entirely if the surrounding code is short.

- [ ] **Step 6.4: Audit explicit `.single` callers against radiused-shape geometry**

The auto-upgrade silently turned `.single` into `.rounded` whenever a positive-radius `RoundedRectangle` was stroked. Now that it's deleted, any caller that explicitly passes `.single` against a radiused shape will get sharp `┌┐└┘` corners instead of `╭╮╰╯`. Find them:

```bash
grep -rn "borderSet: \.single\|StrokeStyle(borderSet: \.single)\|\.init(borderSet: \.single)" \
  Sources/ Tests/ Examples/ --include="*.swift"
```

For each hit, look at the surrounding shape geometry. Three categories:

1. **Caller draws against `Rectangle()` (no radius)** — no behavior change. Leave it.
2. **Caller draws against `RoundedRectangle(cornerRadius: r>0)` and *wants* sharp corners** — leave it. The behavior change is the user-visible improvement: their stated intent (`.single`) is now respected.
3. **Caller draws against `RoundedRectangle(cornerRadius: r>0)` and *was relying on* the auto-upgrade for rounded corners** — change the explicit `.single` to `.rounded`. The most likely candidate based on the audit is `Sources/Core/DrawExtractor+Lists.swift:125` (list section chrome). Read each candidate and decide.

Document each decision with a one-line comment in the diff if it isn't obvious from the surrounding code (`// .rounded explicitly: this draws against a RoundedRectangle and the visual contract is curved corners.`).

- [ ] **Step 6.5: Build (snapshot tests will fail until re-recording)**

```bash
swift build 2>&1 | tail -10
```

Expected: clean build.

- [ ] **Step 6.6: Run a non-snapshot test slice to confirm logic correctness**

```bash
swift test --filter BorderStrokeDefaultsTests 2>&1 | tail -20
swift test --filter BorderSetTests 2>&1 | tail -20
swift test --filter BorderRenderingTests 2>&1 | tail -20
```

Expected:
- `BorderStrokeDefaultsTests` PASS (the baseline test now matches the new default).
- `BorderSetTests` PASS.
- `BorderRenderingTests` may have specific assertions that need updating — read failures and either update the assertion to expect half-block glyphs (if the test is intentionally exercising default-stroke output) or pass an explicit `.single` style (if the test was incidentally relying on the default).

- [ ] **Step 6.7: Re-record snapshot fixtures**

```bash
PARALLEL_RECORD_RENDERED_FIXTURES=1 swift test 2>&1 | tail -30
```

This regenerates every `Tests/TerminalUITests/Fixtures/**/*.txt` file from the current rendering. Many won't change (no bordered chrome). The ones that do change should switch from `─│┌┐└┘`-style chrome to `▀▄▌▐▛▜▙▟`-style chrome.

- [ ] **Step 6.8: Visually inspect a sample of re-recorded fixtures**

```bash
git diff --stat Tests/TerminalUITests/Fixtures/ | tail -20
```

Identify the fixture directories with the largest diffs (most border-affected views). For each, inspect the new content:

```bash
git diff Tests/TerminalUITests/Fixtures/button/preview-unicode.txt
git diff Tests/TerminalUITests/Fixtures/text-field/preview-unicode.txt
git diff Tests/TerminalUITests/Fixtures/labeled-content/preview-unicode.txt
```

For each: confirm the new output has internally consistent half-block chrome (no broken corners, no leftover `─`/`│` mixed with half-blocks within the same frame). If anything looks broken, that's a bug in the migration — investigate before committing.

- [ ] **Step 6.9: Re-run full test suite in verify mode (no recording)**

```bash
swift test 2>&1 | tail -30
```

Expected: all tests pass against the freshly-recorded fixtures.

- [ ] **Step 6.10: Commit (will be a large diff because of fixture updates)**

```bash
git add Sources/Core/Styling.swift \
        Sources/Core/Rasterizer.swift \
        Sources/Core/DrawExtractor+Lists.swift \
        Tests/TerminalUITests/Fixtures/ \
        Tests/CoreTests/ \
        Tests/TerminalUITests/
git commit -m "feat(core): change default StrokeStyle to outerHalfBlock; drop auto-upgrade

Flips the framework's canonical border/stroke default from
BorderSet.single (full-cell box-drawing glyphs) to
BorderSet.outerHalfBlock (half-block glyphs with consistent
corners). Implicit-default container chrome backed by `StrokeStyle()`
— Shape.stroke, chromeStrokeBorder, Button/Picker/Menu/TextField/GroupBox
frames, etc. — now draws with the half-block palette. `Divider()` is now
an explicit single-line exception.

Also deletes the rasterizer's resolvedStrokeBorderSet helper that
silently upgraded BorderSet.single to .rounded against
positive-radius shape geometry. Callers that want curved corners
now pass .rounded explicitly. Internal callers that relied on the
implicit upgrade have been migrated.

Snapshot fixtures re-recorded. Step 5 of the border/stroke
simplification plan."
```

---

## Task 7: Delete `StrokeStyle.normal` and `StrokeStyle.outerHalfBlock` sugar duplicates

Goal: After Task 6, `StrokeStyle.normal == StrokeStyle(borderSet: .single)` is no longer the default — but it's also no longer "normal" in any meaningful sense. And `StrokeStyle.outerHalfBlock == StrokeStyle()` is now an exact alias for the default. Delete both.

**Files:**
- Modify: `Sources/Core/Styling.swift:528, 534` (delete the two static lets)
- Modify: any caller — find with grep below.

- [ ] **Step 7.1: Inventory callers**

```bash
grep -rn "StrokeStyle\.normal\b\|StrokeStyle\.outerHalfBlock\b\|\.normal\b\|\.outerHalfBlock\b" \
  Sources/ Tests/ Examples/ --include="*.swift" \
  | grep -E "StrokeStyle\.(normal|outerHalfBlock)|style: \.(normal|outerHalfBlock)"
```

Expected output: a list of call sites. Each is either a `StrokeStyle.normal`/`.outerHalfBlock` direct reference, or a `style: .normal`/`style: .outerHalfBlock` shorthand (where Swift's type inference resolves the leading dot against `StrokeStyle`). For each:

- `.normal` callers → replace with `StrokeStyle(borderSet: .single)`.
- `.outerHalfBlock` callers → replace with `StrokeStyle()` (or just delete the explicit `style:` argument since it's now the default).

Be careful: `.normal` is also used in unrelated enums in this codebase (`TodoPriority.normal`, etc., visible in the earlier grep). Only replace `.normal` references whose type context is `StrokeStyle`.

- [ ] **Step 7.2: Migrate the callers**

For each caller from Step 7.1, edit and replace.

Example pattern — `StrokeStyle.normal`:
```swift
// Before:
.stroke(.foreground, style: .normal)
// After:
.stroke(.foreground, style: StrokeStyle(borderSet: .single))
```

Example pattern — `StrokeStyle.outerHalfBlock`:
```swift
// Before:
.stroke(.foreground, style: .outerHalfBlock)
// After:
.stroke(.foreground)  // .outerHalfBlock is now the default
```

- [ ] **Step 7.3: Delete the two static lets**

Edit `Sources/Core/Styling.swift`. Delete:

```swift
public static let normal = StrokeStyle(borderSet: .single)
public static let outerHalfBlock = StrokeStyle(borderSet: .outerHalfBlock)
```

- [ ] **Step 7.4: Build and test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -30
```

Expected: all pass. Snapshot fixtures unchanged from Task 6.

- [ ] **Step 7.5: Commit**

```bash
git add Sources/ Tests/ Examples/
git commit -m "refactor(core): delete StrokeStyle.normal and .outerHalfBlock sugar

After the default flip in the previous commit, .outerHalfBlock is
an exact alias for StrokeStyle() and .normal is misleadingly named
(it's no longer the default). Callers updated to either rely on
the implicit default or pass StrokeStyle(borderSet: .single)
explicitly. Step 6 of the border/stroke simplification plan."
```

---

## Task 8: Documentation pass

Goal: Update doc comments and write a short architecture doc explaining the new two-system model so future work doesn't re-invent System 3 or System 4.

**Files:**
- Modify: `Sources/Core/BorderSet.swift` (top-of-file doc comment)
- Modify: `Sources/Core/Styling.swift:506-525` (StrokeStyle doc comment)
- Modify: `Sources/View/Modifiers/StyleModifiers.swift:153-159` (View.border doc)
- Create: `docs/proposals/BORDERS_AND_STROKES.md`

- [ ] **Step 8.1: Update BorderSet doc comment**

Add a top-of-file doc comment to `Sources/Core/BorderSet.swift`:

```swift
/// A glyph palette for drawing rectangular borders around content.
///
/// `BorderSet` is one of the two systems that define the framework's
/// border/stroke story (the other is ``StrokeStyle``):
///
/// - **`BorderSet`** — *what* glyphs to draw. Top, bottom, side, and
///   corner characters; optional middle-junction glyphs for tables and
///   subdivided containers.
/// - **`StrokeStyle`** — *how* to draw them: line width, layout
///   placement (``StrokeStyle/Placement/outset`` or
///   ``StrokeStyle/Placement/inset``), and which `BorderSet` to use.
///
/// The framework's canonical default (``StrokeStyle/init()``) selects
/// ``outerHalfBlock``. Callers who want the legacy single-line look pass
/// ``single`` explicitly. There is *no* implicit transformation between
/// `BorderSet`s — what you ask for is what you get drawn.
public struct BorderSet: Equatable, Sendable {
```

- [ ] **Step 8.2: Update StrokeStyle doc comment**

Replace the doc comment block at `Sources/Core/Styling.swift:506-513`:

```swift
/// Stroke settings used when drawing outlines and rules.
///
/// `StrokeStyle` pairs:
/// - a numeric `lineWidth` (currently always 1, reserved for future use)
/// - a ``BorderSet`` (the glyph palette — see ``BorderSet`` for details)
/// - a ``Placement`` (`.outset` reserves a cell on each side for the
///   border to live in; `.inset` draws the border into the outermost
///   cells of the content frame).
///
/// The default (``init(lineWidth:borderSet:placement:)`` with no
/// arguments) produces ``BorderSet/outerHalfBlock`` glyphs in
/// `.outset` placement. Use this for the framework-canonical look.
///
/// For a single-line look matching pre-2026-04 framework defaults,
/// pass `borderSet: .single` explicitly. For curved corners on a
/// radiused rectangle, pass `borderSet: .rounded` — there is no
/// implicit upgrade; what you ask for is what you get drawn.
public struct StrokeStyle: Equatable, Sendable {
```

- [ ] **Step 8.3: Update View.border doc comment**

Edit `Sources/View/Modifiers/StyleModifiers.swift:153-159` to align with the new defaults and the explicit `placement:` parameter added in Task 3.

- [ ] **Step 8.4: Write the architecture doc**

Create `docs/proposals/BORDERS_AND_STROKES.md`:

```markdown
# Borders and Strokes

This framework has *two* systems for drawing rectangular borders:

1. **`BorderSet`** — a 13-slot glyph palette (top/bottom/sides + four
   corners + optional middle joins). Defined in
   `Sources/Core/BorderSet.swift`. Pure data; no behavior.
2. **`StrokeStyle`** — `lineWidth` + `BorderSet` + `Placement`. Defined
   in `Sources/Core/Styling.swift`. Configures *how* a `BorderSet` is
   drawn against a shape.

These two are deliberately the only sources of truth. Earlier
revisions had two additional implicit "systems" — distinct defaults
on the `View.border(...)` modifier vs. `Shape.stroke(...)`, and
hand-rolled glyph painting in tables, tabs, scrollbars, sliders,
progress, and charts. As of 2026-04 the modifier and stroke defaults
are aligned, and the hand-rolled widget glyphs are documented as
intentional widget-specific palettes (out of the
`BorderSet`/`StrokeStyle` story by design).

## The canonical default

`StrokeStyle()` and `View.border(...)` both default to:

- `borderSet: .outerHalfBlock` — top `▀`, bottom `▄`, sides `▌`/`▐`,
  corners `▛▜▙▟`. Internally consistent half-block palette.
- `placement: .outset` — the border lives in a cell on each side of the
  content; the layout engine reserves space for it.
- `lineWidth: 1` — currently the only supported value.

If you write `Rectangle().stroke(.red)` or `Rectangle().border(.red)`,
this is what you get.

## Opting into single-line chrome

For the legacy `─│┌┐└┘` look, pass `borderSet: .single` explicitly:

```swift
Rectangle()
  .stroke(.foreground, style: StrokeStyle(borderSet: .single))
```

For curved corners on a `RoundedRectangle`, pass `borderSet: .rounded`
explicitly:

```swift
RoundedRectangle(cornerRadius: 1)
  .stroke(.foreground, style: StrokeStyle(borderSet: .rounded))
```

There is **no** implicit transformation — the rasterizer draws exactly
the `BorderSet` you ask for. The historical "single → rounded
auto-upgrade" against radiused shapes was removed in 2026-04 along
with the canonical-default flip.

## Available palettes

See `BorderSet`'s static let declarations:

- `single` / `rounded` / `heavy` / `double` — line-drawing variants
- `outerHalfBlock` / `innerHalfBlock` — half-block variants
- `block` — solid `█` perimeter
- `singleDouble` / `doubleSingle` — mixed line/double
- `ascii` / `markdown` — fallback palettes for restricted terminals
- `dashed` / `dashedHeavy` — dashed variants
- `hidden` (reserves space, draws spaces) / `none` (zero contribution)

## Out of scope (intentional widget palettes)

The following draw their own glyphs and do not participate in
`BorderSet`/`StrokeStyle`:

- Tables (`Sources/Core/CollectionStylePresentations.swift`,
  `TableBorderGlyphs`) — fork of BorderSet shape with extra junction
  fields. Migration is feasible but defers junction synthesis for
  half-block palettes.
- Tabs (`Sources/View/NavigationViews/TabViewStyles.swift`) — three
  distinct hand-rolled chromes (underline, literal, labeled).
- Scrollbars (`Sources/Core/DrawExtractor+Lists.swift`) — `┃`/`━`/`█`.
- Sliders, progress bars, charts, metric tracks — thin-line interior
  glyph painting, not container chrome.

These are documented for inventory; their visual identity is
intentionally distinct from the canonical container border.
```

- [ ] **Step 8.5: Commit**

```bash
git add Sources/Core/BorderSet.swift \
        Sources/Core/Styling.swift \
        Sources/View/Modifiers/StyleModifiers.swift \
        docs/proposals/BORDERS_AND_STROKES.md
git commit -m "docs: capture two-system border/stroke architecture

Updates BorderSet, StrokeStyle, and View.border doc comments to
reflect the post-simplification defaults. Adds an architecture
doc to BORDERS_AND_STROKES.md explaining what the canonical
default is, how to opt back into single-line chrome, and which
widget glyph systems are deliberately out of scope. Final step
of the border/stroke simplification plan."
```

---

## Self-review checklist (run before handing off)

- [ ] Every spec requirement (D1–D7 above) maps to at least one task.
- [ ] No "TBD" / "implement later" / "similar to Task N" placeholders anywhere.
- [ ] Type names are consistent: `StrokeStyle.Placement` (not `BorderSet.Placement`) everywhere after Task 4.
- [ ] Default-change task (Task 6) is a single atomic commit including snapshot updates — no half-recorded state.
- [ ] Auto-upgrade helper (`resolvedStrokeBorderSet`) deleted in Task 6, and both call sites in `Rasterizer.swift` (lines 1353 and 2023) inlined to read `strokeStyle.borderSet` directly.
- [ ] Internal callers that explicitly pass `.single` against a radiused shape have been audited (Step 6.4); any that visually depended on the auto-upgrade are migrated to `.rounded`.
- [ ] Public API breakage (removing `placement` from `BorderSet.init`) is called out in D5 and in the Task 4 commit message.

---

## Execution notes

**Suggested execution mode: subagent-driven** (one subagent per task). Tasks 6 and 7 are the riskiest:

- Task 6 has the largest diff (snapshot fixture re-recording across ~115 files). Review the fixture diff carefully before commit — any inconsistent half-block chrome (e.g., `▀` next to `┌`) indicates a missed migration in Task 3.
- Task 7's caller migration is grep-and-replace work; the test suite is the safety net. Don't skip the build between Steps 7.2 and 7.4.

Tasks 1–5 are mechanical and low-risk; tasks 8 is documentation.

**If you find a missed migration after Task 6:** the most likely cause is a code path that called `Shape.stroke(...)` with no explicit style, but where the surrounding chrome is supposed to stay single-line for visual reasons (e.g., a widget that intentionally combines a single-line frame with half-block content). Fix at the call site by passing `style: StrokeStyle(borderSet: .single)` explicitly — don't try to special-case it inside the rasterizer.
