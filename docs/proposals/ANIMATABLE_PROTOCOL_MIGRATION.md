# Animatable Protocol Migration Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Date:** 2026-04-13
**Status:** Shipped. Retained as the implementation record for the migration to the SwiftUI-shaped `Animatable` protocol pipeline.
**Branch:** `main`
**Supersedes (in part):** the enum-dispatch model established by `docs/proposals/ANIMATION_PLAN.md` (shipped 2026-04-10). That plan remains the historical record of the original animation system; this plan migrates its value-interpolation model to the SwiftUI-shaped `Animatable` protocol.

**Goal:** Replace the hand-rolled `AnimatableProperty` / `AnimatableValue` enum-dispatch animation pipeline with a SwiftUI-shaped `Animatable` protocol pipeline so compound animatable types — gradients, `PatternFill`, future shape styles — animate through a one-line conformance instead of per-type controller code.

**Architecture:** Introduce `UnitPoint` as a continuous replacement for `Alignment` on gradients. Add `Animatable` conformances for every animatable type (`UnitPoint`, `EdgeInsets`, `Color`, `Gradient.Stop`, `Gradient`, `LinearGradient`, `RadialGradient`, `PatternFill.Paint`, `PatternFill`) routing through a new `AnimatableArray` primitive for variable-length stop arrays. Rewrite `AnimationController`'s value-interpolation path around a type-erased `AnyAnimatable` keyed by an `AnimatableSlot` enum that identifies the writeback destination. Unify the three parallel side-channel maps (`activeAnimations`, `insertionOffsetAnimations`, `matchedGeometryAnimations`) under one `ActiveAnimation` machine. Delete `dominantActiveRequest()` re-injection and the empty-`affectedIdentities` viewport-gate bypass now that the tick-result semantics are clean.

**Tech Stack:** Swift 6.2+ (strict concurrency), Swift Testing (`import Testing`, `@Test`, `#expect`), Xcode 26+, swift-tui package (Core + View + SwiftTUI module split).

---

## Table of Contents

1. [Background](#background)
2. [Scope](#scope)
3. [Architectural Decisions](#architectural-decisions)
4. [Phase Overview](#phase-overview)
5. [Cross-Phase Invariants](#cross-phase-invariants)
6. [Phase 0 — Bedrock Primitives](#phase-0--bedrock-primitives)
7. [Phase 1 — Alignment to UnitPoint on Gradients](#phase-1--alignment-to-unitpoint-on-gradients)
8. [Phase 2 — Compound Animatable Conformances](#phase-2--compound-animatable-conformances)
9. [Phase 3 — AnimationController Value-Interpolation Rewrite](#phase-3--animationcontroller-value-interpolation-rewrite)
10. [Phase 4 — Controller Polish](#phase-4--controller-polish)
11. [Phase 5 — Gallery Demo + Docs + Validation](#phase-5--gallery-demo--docs--validation)
12. [Risks and Mitigations](#risks-and-mitigations)
13. [Rollback Strategy](#rollback-strategy)
14. [Execution Handoff](#execution-handoff)

---

## Background

The animation controller today uses a hand-rolled enum-dispatch model:

- `AnimatableProperty` enum with 15 hardcoded cases (one per animatable slot: `opacity`, `foregroundColor`, `backgroundColor`, `borderColor`, `borderBlendPhase`, `paddingTop/Leading/Bottom/Trailing`, `offsetX/Y`, `positionX/Y`, `frameWidth/Height`).
- `AnimatableValue` enum with 3 variants: `.double(Double)`, `.integer(Int)`, `.color(Color)`.
- `AnimatableSnapshot` struct with a field per slot, extracted from a `ResolvedNode` via a field-by-field assignment helper.
- `diffAndEnqueue` with 15 hardcoded `enqueueIfChanged` calls, one per property.
- `interpolate(from:to:progress:)` with a 3-arm switch on `AnimatableValue`.
- `applyValue(_:property:value:)` with an ~80-line switch on `(property, value)` pairs that writes interpolated values back into `DrawMetadata` or `LayoutBehavior`.

This model worked correctly for scalar properties but does not generalize to compound types. The `gradient bgs` commit (`dd3dcf9`, 2026-04-13) exposed the gap: `PatternFill` gained the ability to carry gradients as its foreground/background `Paint`, but the animation controller has no way to extract, diff, or interpolate those gradients. The `AnimatableSnapshot.extractColor` helper (`Sources/SwiftTUI/AnimationController.swift:133-143`) returns `nil` for any shape style that isn't `.color` or `.opacity(inner, _)`, which means pattern-filled shapes, gradient-filled shapes, and every compound shape style effectively have *no* animatable state from the controller's perspective.

The immediate consequence was the `PhaseAnimator` demo in `Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift` freezing on phase 0. `PhaseAnimator` wraps each phase transition in `withAnimation(anim) { currentPhase = nextPhase } completion: { continuation.resume() }`. Because the body changed nothing the controller could diff, the batch was never retained, so `releaseBatch` was a no-op, so the completion never fired, so the awaited continuation never resumed, so the phase loop never advanced.

The `9d6a87d` commit (2026-04-13, "Drain stranded withAnimation completions on empty batches") shipped a targeted fix for the stranded-completion half of the problem. `PhaseAnimator` now advances correctly but the transitions are step functions: the gradient snaps between orientations every 500 ms instead of rotating smoothly. Fixing the step-function visual requires the controller to actually interpolate gradient interior (stops, colors, start/end points) between frames — which is what this plan is for.

The rewrite has a second motivation beyond the gradient use case. Every future compound animatable type — matrix transforms, animatable per-stop gradient arrays, custom shape styles, animatable transition modifiers, user-defined `View: Animatable` conformances — would need its own `AnimatableProperty` case, its own `AnimatableValue` variant, and its own extract / interpolate / apply branches. The enum-dispatch model doesn't generalize; every new animatable type pays the full per-property controller cost. The SwiftUI-shaped `Animatable` protocol lets new types ship with a one-line conformance and the controller stays unchanged.

---

## Scope

### In scope

1. **Bedrock primitives.** `AnimatableArray<Element: VectorArithmetic>`, `UnitPoint`, `EdgeInsets: Animatable`, `Color: Animatable` using the existing OKLab converter (`Color.oklab()` + `Color._fromOklab(_:alpha:profile:)`).
2. **Gradient endpoint type migration.** `Alignment` → `UnitPoint` on `LinearGradient.startPoint` / `.endPoint` and `RadialGradient.center`. Direct replacement — no dual-API. `.topLeading` / `.center` / etc. become static constants on `UnitPoint` so most call sites compile unchanged.
3. **Compound `Animatable` conformances.** `Gradient.Stop`, `Gradient`, `LinearGradient`, `RadialGradient`, `PatternFill.Paint`, `PatternFill`.
4. **`AnyAnimatable`.** Type-erased wrapper carrying `any Animatable` with same-type equality, same-type diffing, and same-type interpolation via `animatableData` arithmetic. Returns `nil` from `interpolated(to:progress:)` on type mismatch (caller snaps).
5. **`AnimatableSlot` enum + slot-keyed `AnimatableSnapshot`.** `AnimatableSnapshot` becomes `[AnimatableSlot: AnyAnimatable]`. Slots enumerate the writeback destinations on `DrawMetadata` / `LayoutBehavior`.
6. **`AnimationController` value-interpolation rewrite.** `extract` → `diffAndEnqueue` → `interpolate` → `applyValue` all route through `AnimatableSlot` / `AnyAnimatable`. The old `AnimatableProperty` and `AnimatableValue` enums are deleted entirely.
7. **Side-channel map unification.** `activeAnimations`, `insertionOffsetAnimations`, `matchedGeometryAnimations` become one `activeAnimations: [AnimationKey: ActiveAnimation]` map where `AnimationKey` identifies the (identity, kind) pair and `ActiveAnimation` is a polymorphic struct discriminated on kind.
8. **`AnimationTickResult` semantics cleanup.** Split `affectedIdentities` into `redrawIdentities` (which cells need redraw) and `hasWakeUp` (should the scheduler wake us up regardless of visibility). The `isIdentityAgnosticTick` bypass introduced by commit `9d6a87d` in `RunLoop+Rendering.swift` goes away.
9. **`dominantActiveRequest()` deletion.** The inject-animation-into-tick-frames hack in `RunLoop+Rendering.swift:288-291` becomes unnecessary once the controller retargets cleanly through `AnyAnimatable`.
10. **Gallery demo refactor.** `BordersAndShapesTab` shows smooth gradient rotation via `PhaseAnimator`. A new "animated gradient" demo section shows direct `withAnimation`-driven gradient interpolation.
11. **Test pass.** Every pre-existing test green. New unit tests for each `Animatable` conformance with perceptual-equivalence pins. New end-to-end RunLoop tests for gradient animation.

### Explicitly out of scope

- **User-defined `View: Animatable` conformances.** The SwiftUI pattern where a view declares its own `animatableData` to animate arbitrary state is not added in this plan. The `Animatable` protocol itself will support it once `AnyAnimatable` exists, but we don't enumerate any user-level examples or add the necessary `Animatable`-consuming `ViewModifier` infrastructure here.
- **Matrix transforms.** Affine / 3D transforms are not animatable today and are not added here.
- **Custom shape styles beyond the existing set.** The animatable shape-style slot accepts `Color`, `LinearGradient`, `RadialGradient`, `PatternFill`, and the semantic / terminal-chrome wrappers as currently supported. No new shape-style *kinds* are introduced.
- **New animation curves or spring behavior.** `Animation`, `BezierSolver`, `SpringSolver`, `CustomAnimation` stay unchanged.
- **Test file reorganization.** `Tests/SwiftTUITests/AnimationControllerTests.swift` stays one file even though it's large (~2000 lines). Splitting it is a separate cleanup.
- **Profile-preserving color space interpolation.** Colors keep their source profile through animation (`self.profile` is preserved in the `Color.animatableData` setter). Cross-profile interpolation is not added; if an animation's `from` and `to` have different color profiles, the controller interpolates in the `from` profile's OKLab space — which is what the existing `Color.interpolated(to:progress:method:.perceptual)` does today.

---

## Architectural Decisions

### 1. SwiftUI-shaped `Animatable` protocol as the primary abstraction

The controller stores an `AnyAnimatable` per slot; diffing, interpolation, and equality all dispatch through the wrapped type's `animatableData`. Every concrete animatable type conforms to `Animatable` with `animatableData: some VectorArithmetic`. This is the SwiftUI contract and we follow it directly.

The one place we still pattern-match by slot name is the `applyValue` writeback path, because different slots have structurally different writeback targets (`opacity` writes to `drawMetadata.baseStyle.explicitOpacity`, `foregroundShapeStyle` writes to `drawMetadata.baseStyle.foregroundStyle`, `padding` writes to `node.layoutBehavior`, and so on). There's no way to erase that — the destination is genuinely slot-specific. But the *value-interpolation* half becomes fully uniform: one generic code path replaces 15 hand-written ones.

### 2. `UnitPoint` replaces `Alignment` on gradients — no dual-API

`Alignment` stays for layout (`VStack.alignment`, `Text.multilineTextAlignment`, `.frame(alignment:)`, etc.) because it's fundamentally a named-slot system with opaque `ObjectIdentifier`-keyed guides and it's user-extensible via `AlignmentID`. Gradients take `UnitPoint` — a concrete `(x: Double, y: Double)` struct — because they need continuous interpolation.

The two types share the same named constants (`.topLeading`, `.center`, etc.) as static members, so most gradient call sites compile without changes. Sites that construct `Alignment(horizontal: .leading, vertical: .center)` inline for a gradient get a source-incompatible break, migrate directly to `UnitPoint(x: 0, y: 0.5)` or the named constant.

**Rejected alternative:** Make `Alignment` itself carry coordinate data. Rejected because `HorizontalAlignment` / `VerticalAlignment` are user-extensible via `AlignmentID`, and a custom alignment's "coordinate" is genuinely not well-defined — layout guides don't have unit coordinates, they have integer pixel offsets computed per-frame from `ViewDimensions`. Mixing the two semantics would create API ambiguity.

### 3. `Color.animatableData` uses OKLab components

`Color.animatableData` is `AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>` carrying `(L, a, b, alpha)` in OKLab space. The getter calls the existing `self.oklab()`; the setter calls `Color._fromOklab(_:alpha:profile:).mapped(to: self.profile, policy: .compressPerceptual)`. Both helpers already exist in `Sources/Core/Color.swift` and are used by the existing `Color.interpolated(to:progress:method:.perceptual)` path at `Color.swift:1615-1624`.

OKLab is designed so that linear arithmetic in L-a-b space equals perceptual interpolation. `a + (b - a) * t` through `VectorArithmetic` produces the same result as `Color.interpolated(to:progress:method:.perceptual)` at the same `t`. Phase 4 tests pin this equivalence to within a floating-point epsilon.

**Rejected alternative:** sRGB components. Rejected because linear-RGB interpolation produces visibly muddy grays through the middle of red→green transitions — a visible regression from the existing perceptual path.

### 4. `Gradient` stop arrays use `AnimatableArray` with count-match precondition

`AnimatableArray<Element: VectorArithmetic>` is a new primitive in Phase 0. It wraps `[Element]` with element-wise arithmetic. Count mismatches cannot produce valid `VectorArithmetic` operations, so the operators return a zero-element result on mismatch, and callers check `isInterpolable(to:)` before composing. The animation controller's diff path snaps when `isInterpolable` is false (matches SwiftUI semantics).

### 5. `PatternFill.Paint` cross-variant changes snap

`PatternFill.Paint` is an enum of `.color(Color)`, `.linearGradient(LinearGradient)`, `.radialGradient(RadialGradient)`. Same-variant interpolation delegates to the wrapped animatable (`.linearGradient(a)` + `.linearGradient(b)` → interpolated linear gradient). Cross-variant (`.color(a)` → `.linearGradient(b)`) snaps — no cross-variant bridging. SwiftUI does the same.

### 6. Side-channel map unification: one `ActiveAnimation` keyed dictionary

The three parallel maps in `Sources/SwiftTUI/AnimationController.swift` (`activeAnimations` for property animations, `insertionOffsetAnimations` for transition-driven insertion offsets, `matchedGeometryAnimations` for matched-geometry translations) get consolidated. A new `AnimationKey` struct carries both an `Identity` and a `Kind` discriminator (`.property(AnimatableSlot)`, `.insertionOffset`, `.matchedGeometry`). Retain/release bookkeeping runs through one code path instead of three parallel ones.

### 7. Keep `pendingEmptyBatchCompletions` as a safety net

The drain path shipped in `9d6a87d` still has a job after the rewrite: any `withAnimation { untracked-slot change }` body (e.g., a `Text` content change, a `@State` counter increment that doesn't drive any slot) still produces an empty batch. The drain is the mechanism by which those completions fire on time. It's hit less often after the rewrite but it isn't dead code.

---

## Phase Overview

| # | Phase | Files touched | Source LOC | Test LOC | Commit message |
|---|---|---|---|---|---|
| 0 | Bedrock primitives | 4 | ~280 | ~260 | `Add AnimatableArray, UnitPoint, EdgeInsets/Color Animatable conformances` |
| 1 | Alignment → UnitPoint on gradients | ~10 | ~150 | ~50 | `Replace Alignment with UnitPoint on LinearGradient and RadialGradient` |
| 2 | Compound Animatable conformances | 3 | ~310 | ~300 | `Add Animatable conformances for Gradient, LinearGradient, RadialGradient, PatternFill` |
| 3 | AnimationController value-interpolation rewrite | 3 | ~420 replaced | ~220 | `Rewrite AnimationController value-interpolation path around AnyAnimatable` |
| 4 | Controller polish: unify side-channels, clean AnimationTickResult, delete dominantActiveRequest | 3 | ~260 | ~120 | `Unify animation side-channels and clean up tick-result semantics` |
| 5 | Gallery demo + docs + validation | ~5 | ~150 | ~150 | `Gallery: smooth gradient rotation via PhaseAnimator` |

**Total:** ~1570 source LOC, ~1100 test LOC, six commits landed in order.

Each commit is independently compilable, independently green against the full test suite, and independently reviewable. A reviewer can understand Phase 3 without reading Phase 4; each commit message lists file-level changes and purpose. Phases 3 and 4 are the riskiest; all others are additive or mechanical.

---

## Cross-Phase Invariants

These hold at every commit boundary:

1. **`swift build` is green.** No phase intentionally breaks the build.
2. **`swift test` is green.** Full suite runs before each commit. Target: all 895+ tests passing.
3. **No visible animation regressions.** A checkpoint of pre-existing animations (opacity fade, color tween, padding animation, offset tween, position tween, frame size, border color, border blend phase) is exercised at each phase boundary. Fixtures: `AnimationControllerPropertyTests` suite in `Tests/SwiftTUITests/AnimationControllerTests.swift`.
4. **OKLab perceptual parity.** After Phase 0 lands `Color: Animatable`, any existing code path that animates a color produces output within `0.001` relative RGB error of the pre-Phase-0 path. Pinned by a dedicated regression test in Phase 0's test suite.
5. **No deprecated API at phase boundaries.** Migrated types don't sit half-migrated with `@available(*, deprecated)` shims. If a type's API is changing in Phase N, it changes fully in Phase N.
6. **Commits are reviewable independently.** No Phase references symbols defined in a later Phase. Phase N's test suite passes without Phase N+1's code.
7. **No gallery regression.** After each phase, the gallery app (`Examples/gallery`) builds cleanly. Phase 5 is the only phase that intentionally changes gallery demo code.
8. **Pre-existing drain behavior preserved.** The stranded-completion drain tests from commit `9d6a87d` (`completionClosureFiresAfterDurationForStrandedBatch`, `completionClosureFiresImmediatelyForDisabledStrandedBatch`, `completionClosureSuppressedForForeverStrandedBatch`, `strandedBatchDrainSurfacesWakeupDeadline`) stay green at every phase. The drain is load-bearing for `withAnimation { untracked slot }` and is not deleted.

---

## Phase 0 — Bedrock Primitives

**Goal:** Add the `VectorArithmetic` / `Animatable` primitives that subsequent phases depend on, without touching any existing code path. Every addition is dead code until Phases 1-3 consume it. Full test coverage before integration.

**Files:**
- Create: `Sources/Core/AnimatableArray.swift`
- Modify: `Sources/Core/GeometryTypes.swift` (add `UnitPoint` struct + `EdgeInsets: Animatable` extension)
- Create: `Sources/Core/ColorAnimatable.swift`
- Create: `Tests/CoreTests/AnimatableArrayTests.swift`
- Create: `Tests/CoreTests/UnitPointTests.swift`
- Create: `Tests/CoreTests/EdgeInsetsAnimatableTests.swift`
- Create: `Tests/CoreTests/ColorAnimatableTests.swift`

### Task 0.1: `AnimatableArray` primitive

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/AnimatableArrayTests.swift`:

```swift
import Testing

@testable import Core

@Test("AnimatableArray element-wise addition with equal counts")
func animatableArrayEqualCountAddition() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5, 0.5])
  let sum = a + b
  #expect(sum.elements == [1.5, 2.5, 3.5])
}

@Test("AnimatableArray element-wise subtraction with equal counts")
func animatableArrayEqualCountSubtraction() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5, 0.5])
  let diff = a - b
  #expect(diff.elements == [0.5, 1.5, 2.5])
}

@Test("AnimatableArray mismatched counts snap to empty")
func animatableArrayMismatchedCountSnap() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  let b = AnimatableArray<Double>([0.5, 0.5])
  let sum = a + b
  #expect(sum.elements.isEmpty)
  #expect(!a.isInterpolable(to: b))
  #expect(a.isInterpolable(to: AnimatableArray<Double>([9, 9, 9])))
}

@Test("AnimatableArray scale mutates in place")
func animatableArrayScale() {
  var a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  a.scale(by: 0.5)
  #expect(a.elements == [0.5, 1.0, 1.5])
}

@Test("AnimatableArray magnitudeSquared sums element magnitudes")
func animatableArrayMagnitudeSquared() {
  let a = AnimatableArray<Double>([1.0, 2.0, 3.0])
  #expect(a.magnitudeSquared == 1.0 + 4.0 + 9.0)
}

@Test("AnimatableArray zero is an empty array")
func animatableArrayZero() {
  let z: AnimatableArray<Double> = .zero
  #expect(z.elements.isEmpty)
}

@Test("AnimatableArray compound assignment operators")
func animatableArrayCompoundAssignment() {
  var a = AnimatableArray<Double>([1.0, 2.0])
  a += AnimatableArray<Double>([0.5, 0.5])
  #expect(a.elements == [1.5, 2.5])
  a -= AnimatableArray<Double>([0.25, 0.25])
  #expect(a.elements == [1.25, 2.25])
}

@Test("AnimatableArray nested AnimatablePair composition")
func animatableArrayNestedPair() {
  let a = AnimatableArray<AnimatablePair<Double, Double>>([
    .init(1.0, 2.0),
    .init(3.0, 4.0),
  ])
  let b = AnimatableArray<AnimatablePair<Double, Double>>([
    .init(0.5, 0.5),
    .init(0.5, 0.5),
  ])
  let sum = a + b
  #expect(sum.elements[0].first == 1.5)
  #expect(sum.elements[0].second == 2.5)
  #expect(sum.elements[1].first == 3.5)
  #expect(sum.elements[1].second == 4.5)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "AnimatableArray"
```

Expected: compilation failure — `AnimatableArray` is not defined.

- [ ] **Step 3: Implement `AnimatableArray`**

Create `Sources/Core/AnimatableArray.swift`:

```swift
/// Variable-length animatable storage for compound values whose size
/// isn't fixed at type level — e.g. ``Gradient`` stop arrays.
///
/// Arithmetic operations require both operands to have the same
/// element count. With mismatched counts, `+`, `-`, `+=`, `-=`
/// return a zero-element result (which propagates through subsequent
/// arithmetic as zero).  The animation controller checks
/// ``isInterpolable(to:)`` before composing arithmetic and snaps to
/// the target value when the counts don't match — this matches
/// SwiftUI's behavior of snapping gradient animations when the stop
/// count changes between frames.
public struct AnimatableArray<Element: VectorArithmetic & Sendable>:
  VectorArithmetic, Sendable
{
  public var elements: [Element]

  public init(_ elements: [Element]) {
    self.elements = elements
  }

  public static var zero: Self { .init([]) }

  /// Returns `true` when this array and `other` have the same element
  /// count and can therefore be composed under ``+`` / ``-``.
  public func isInterpolable(to other: Self) -> Bool {
    elements.count == other.elements.count
  }

  public static func + (lhs: Self, rhs: Self) -> Self {
    guard lhs.elements.count == rhs.elements.count else {
      return .init([])
    }
    var result: [Element] = []
    result.reserveCapacity(lhs.elements.count)
    for i in lhs.elements.indices {
      result.append(lhs.elements[i] + rhs.elements[i])
    }
    return .init(result)
  }

  public static func - (lhs: Self, rhs: Self) -> Self {
    guard lhs.elements.count == rhs.elements.count else {
      return .init([])
    }
    var result: [Element] = []
    result.reserveCapacity(lhs.elements.count)
    for i in lhs.elements.indices {
      result.append(lhs.elements[i] - rhs.elements[i])
    }
    return .init(result)
  }

  public static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  public static func -= (lhs: inout Self, rhs: Self) {
    lhs = lhs - rhs
  }

  public mutating func scale(by rhs: Double) {
    for i in elements.indices {
      elements[i].scale(by: rhs)
    }
  }

  public var magnitudeSquared: Double {
    elements.reduce(0) { $0 + $1.magnitudeSquared }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "AnimatableArray"
```

Expected: all 8 tests pass.

- [ ] **Step 5: Run the full suite to confirm no regression**

```bash
swift test
```

Expected: all 895+ tests pass (unchanged from pre-Phase-0 baseline).

### Task 0.2: `UnitPoint` struct + `Animatable` conformance

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/UnitPointTests.swift`:

```swift
import Testing

@testable import Core

@Test("UnitPoint named constants match unit-coordinate specification")
func unitPointNamedConstants() {
  #expect(UnitPoint.topLeading == UnitPoint(x: 0, y: 0))
  #expect(UnitPoint.top == UnitPoint(x: 0.5, y: 0))
  #expect(UnitPoint.topTrailing == UnitPoint(x: 1, y: 0))
  #expect(UnitPoint.leading == UnitPoint(x: 0, y: 0.5))
  #expect(UnitPoint.center == UnitPoint(x: 0.5, y: 0.5))
  #expect(UnitPoint.trailing == UnitPoint(x: 1, y: 0.5))
  #expect(UnitPoint.bottomLeading == UnitPoint(x: 0, y: 1))
  #expect(UnitPoint.bottom == UnitPoint(x: 0.5, y: 1))
  #expect(UnitPoint.bottomTrailing == UnitPoint(x: 1, y: 1))
}

@Test("UnitPoint zero static property")
func unitPointZero() {
  #expect(UnitPoint.zero == UnitPoint(x: 0, y: 0))
}

@Test("UnitPoint is Equatable and Hashable")
func unitPointEquatableHashable() {
  let a = UnitPoint(x: 0.25, y: 0.75)
  let b = UnitPoint(x: 0.25, y: 0.75)
  let c = UnitPoint(x: 0.25, y: 0.5)
  #expect(a == b)
  #expect(a != c)
  #expect(a.hashValue == b.hashValue)
}

@Test("UnitPoint animatableData getter returns (x, y) pair")
func unitPointAnimatableDataGetter() {
  let p = UnitPoint(x: 0.25, y: 0.75)
  #expect(p.animatableData.first == 0.25)
  #expect(p.animatableData.second == 0.75)
}

@Test("UnitPoint animatableData setter writes back to x and y")
func unitPointAnimatableDataSetter() {
  var p = UnitPoint(x: 0, y: 0)
  p.animatableData = AnimatablePair(0.1, 0.9)
  #expect(p.x == 0.1)
  #expect(p.y == 0.9)
}

@Test("UnitPoint interpolation via animatableData arithmetic")
func unitPointInterpolation() {
  let from = UnitPoint.topLeading
  let to = UnitPoint.bottomTrailing
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result == UnitPoint.center)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "unitPoint"
```

Expected: compilation failure — `UnitPoint` is not defined.

- [ ] **Step 3: Implement `UnitPoint` and its `Animatable` conformance**

Append to `Sources/Core/GeometryTypes.swift` (after the existing `EdgeInsets` struct at `:52-85`):

```swift
/// A normalized point in a shape's bounds where `(0, 0)` is the
/// top-leading corner and `(1, 1)` is the bottom-trailing corner.
///
/// Used by gradient start/end points where interpolation requires
/// continuous unit coordinates — ``Alignment`` identifies named
/// layout slots via `AlignmentID`-keyed guides, while ``UnitPoint``
/// is a concrete `(x, y)` pair that can be interpolated element-wise
/// by the animation pipeline.  The named static constants
/// (``topLeading``, ``center``, etc.) mirror ``Alignment``'s named
/// constants so most gradient call sites compile unchanged.
public struct UnitPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public static let zero = UnitPoint(x: 0, y: 0)

  public static let topLeading = UnitPoint(x: 0, y: 0)
  public static let top = UnitPoint(x: 0.5, y: 0)
  public static let topTrailing = UnitPoint(x: 1, y: 0)

  public static let leading = UnitPoint(x: 0, y: 0.5)
  public static let center = UnitPoint(x: 0.5, y: 0.5)
  public static let trailing = UnitPoint(x: 1, y: 0.5)

  public static let bottomLeading = UnitPoint(x: 0, y: 1)
  public static let bottom = UnitPoint(x: 0.5, y: 1)
  public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

extension UnitPoint: Animatable {
  public var animatableData: AnimatablePair<Double, Double> {
    get { .init(x, y) }
    set {
      x = newValue.first
      y = newValue.second
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "unitPoint"
```

Expected: all 6 tests pass.

### Task 0.3: `EdgeInsets: Animatable` conformance

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/EdgeInsetsAnimatableTests.swift`:

```swift
import Testing

@testable import Core

@Test("EdgeInsets animatableData getter carries all four edges")
func edgeInsetsAnimatableGetter() {
  let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
  let data = insets.animatableData
  #expect(data.first.first == 1)
  #expect(data.first.second == 2)
  #expect(data.second.first == 3)
  #expect(data.second.second == 4)
}

@Test("EdgeInsets animatableData setter writes back to all four edges")
func edgeInsetsAnimatableSetter() {
  var insets = EdgeInsets()
  insets.animatableData = AnimatablePair(
    AnimatablePair(5, 6),
    AnimatablePair(7, 8)
  )
  #expect(insets.top == 5)
  #expect(insets.leading == 6)
  #expect(insets.bottom == 7)
  #expect(insets.trailing == 8)
}

@Test("EdgeInsets halfway interpolation via animatableData")
func edgeInsetsHalfwayInterpolation() {
  let from = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
  let to = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result.top == 5)
  #expect(result.leading == 10)
  #expect(result.bottom == 15)
  #expect(result.trailing == 20)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "edgeInsets"
```

Expected: compilation failure — `EdgeInsets` does not conform to `Animatable`.

- [ ] **Step 3: Implement the conformance**

Append to `Sources/Core/GeometryTypes.swift` below the new `UnitPoint` extension:

```swift
extension EdgeInsets: Animatable {
  public typealias AnimatableData = AnimatablePair<
    AnimatablePair<Int, Int>,
    AnimatablePair<Int, Int>
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        AnimatablePair(top, leading),
        AnimatablePair(bottom, trailing)
      )
    }
    set {
      top = newValue.first.first
      leading = newValue.first.second
      bottom = newValue.second.first
      trailing = newValue.second.second
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "edgeInsets"
```

Expected: all 3 tests pass.

### Task 0.4: `Color: Animatable` conformance (OKLab-backed)

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/ColorAnimatableTests.swift`:

```swift
import Testing

@testable import Core

@Test("Color animatableData round-trips via OKLab")
func colorAnimatableRoundTrip() {
  var red = Color.red
  let originalRed = red
  let data = red.animatableData
  red.animatableData = data
  // Round-trip through the OKLab representation should produce a
  // color within a tight epsilon of the original (floating point
  // drift through sRGB → OKLab → sRGB is bounded but non-zero).
  #expect(abs(red.red - originalRed.red) < 0.001)
  #expect(abs(red.green - originalRed.green) < 0.001)
  #expect(abs(red.blue - originalRed.blue) < 0.001)
  #expect(abs(red.alpha - originalRed.alpha) < 0.001)
}

@Test("Color halfway interpolation via animatableData matches perceptual method")
func colorHalfwayInterpolationMatchesPerceptual() {
  let from = Color.red
  let to = Color.blue

  // Path A: animatable-data arithmetic.
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var pathA = from
  var pathAData = pathA.animatableData
  pathAData += delta
  pathA.animatableData = pathAData

  // Path B: existing Color.interpolated(to:progress:method:.perceptual).
  let pathB = from.interpolated(to: to, progress: 0.5, method: .perceptual)

  // Both paths go through OKLab perceptual interpolation and must
  // produce colors within floating-point epsilon of each other.
  #expect(abs(pathA.red - pathB.red) < 0.001)
  #expect(abs(pathA.green - pathB.green) < 0.001)
  #expect(abs(pathA.blue - pathB.blue) < 0.001)
  #expect(abs(pathA.alpha - pathB.alpha) < 0.001)
}

@Test("Color animatableData zero from arithmetic-zero OKLab")
func colorAnimatableZero() {
  // Zero for AnimatablePair<AnimatablePair<Double, Double>, ...>
  // should be the origin in OKLab space, which round-trips to a
  // zero-alpha black.
  let data: Color.AnimatableData = .zero
  #expect(data.first.first == 0)
  #expect(data.first.second == 0)
  #expect(data.second.first == 0)
  #expect(data.second.second == 0)
}

@Test("Color alpha animates independently via animatableData")
func colorAlphaAnimation() {
  let opaque = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
  let transparent = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.0)
  var delta = transparent.animatableData
  delta -= opaque.animatableData
  delta.scale(by: 0.5)
  var halfway = opaque
  var halfwayData = halfway.animatableData
  halfwayData += delta
  halfway.animatableData = halfwayData
  #expect(abs(halfway.alpha - 0.5) < 0.001)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "colorAnimatable"
```

Expected: compilation failure — `Color` does not conform to `Animatable`.

- [ ] **Step 3: Implement the conformance using the existing OKLab converter**

Create `Sources/Core/ColorAnimatable.swift`:

```swift
/// ``Color``'s ``Animatable`` conformance uses OKLab components so
/// that linear ``VectorArithmetic`` arithmetic — which is what the
/// animation controller performs during interpolation —
/// corresponds to perceptually linear color transitions.  OKLab is
/// designed so that `a + (b - a) * t` in L-a-b space equals the
/// result of ``Color/interpolated(to:progress:method:)`` with
/// ``Color/MixingMethod/perceptual``, preserving the existing
/// visual behavior of color animation introduced in
/// `ANIMATION_PLAN.md`'s Phase 6.
///
/// The getter delegates to ``Color/oklab()``; the setter
/// reconstructs a color via ``Color/_fromOklab(_:alpha:profile:)``
/// and gamut-maps it back to the source profile with
/// ``Color/GamutMappingPolicy/compressPerceptual`` — the same
/// sequence the existing `perceptual` interpolation path uses at
/// `Color.swift:1615-1624`.
///
/// Profile preservation: the setter uses `self.profile` as the
/// destination profile so an animation that starts with an sRGB
/// color stays in sRGB through interpolation.  Cross-profile
/// animation isn't supported today (the `from` and `to` of an
/// animation always share a profile in practice because they
/// originate from the same `Color` literal family).
extension Color: Animatable {
  public typealias AnimatableData = AnimatablePair<
    AnimatablePair<Double, Double>,
    AnimatablePair<Double, Double>
  >

  public var animatableData: AnimatableData {
    get {
      let lab = self.oklab()
      return AnimatablePair(
        AnimatablePair(lab.l, lab.a),
        AnimatablePair(lab.b, self.alpha)
      )
    }
    set {
      let lab = OklabColor(
        l: newValue.first.first,
        a: newValue.first.second,
        b: newValue.second.first
      )
      let alpha = newValue.second.second
      let reconstructed = Color._fromOklab(
        lab,
        alpha: alpha,
        profile: self.profile
      )
      self = reconstructed.mapped(
        to: self.profile,
        policy: .compressPerceptual
      )
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "colorAnimatable"
```

Expected: all 4 tests pass. The critical test is `colorHalfwayInterpolationMatchesPerceptual` — it pins the equivalence between the new `animatableData` path and the existing perceptual interpolation path. If it fails, the OKLab arithmetic is not in fact perceptually linear in this library's OKLab implementation, and the plan needs to be re-checked before proceeding.

- [ ] **Step 5: Run the full suite to confirm no regression**

```bash
swift test
```

Expected: all pre-existing 895+ tests still pass, plus the ~21 new Phase 0 tests.

### Task 0.5: Commit Phase 0

- [ ] **Step 1: Review the staged changes**

```bash
git status
git diff --stat
```

Expected files modified/created:

```
Sources/Core/AnimatableArray.swift        (new)
Sources/Core/ColorAnimatable.swift         (new)
Sources/Core/GeometryTypes.swift           (modified: +UnitPoint, +EdgeInsets: Animatable)
Tests/CoreTests/AnimatableArrayTests.swift (new)
Tests/CoreTests/ColorAnimatableTests.swift (new)
Tests/CoreTests/EdgeInsetsAnimatableTests.swift (new)
Tests/CoreTests/UnitPointTests.swift       (new)
```

- [ ] **Step 2: Stage the files and commit**

```bash
git add \
  Sources/Core/AnimatableArray.swift \
  Sources/Core/ColorAnimatable.swift \
  Sources/Core/GeometryTypes.swift \
  Tests/CoreTests/AnimatableArrayTests.swift \
  Tests/CoreTests/ColorAnimatableTests.swift \
  Tests/CoreTests/EdgeInsetsAnimatableTests.swift \
  Tests/CoreTests/UnitPointTests.swift

git commit -m "$(cat <<'EOF'
Add AnimatableArray, UnitPoint, EdgeInsets/Color Animatable conformances

Phase 0 of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Adds the
VectorArithmetic / Animatable primitives subsequent phases depend on,
without touching any existing code path.  Everything added here is
dead code until Phase 1 starts consuming it.

AnimatableArray<Element: VectorArithmetic>:
  Variable-length animatable storage for compound values whose size
  isn't fixed at type level (Gradient stop arrays in Phase 2).
  Element-wise arithmetic; snap-to-target on count mismatch via
  isInterpolable(to:) check.

UnitPoint:
  Normalized (x, y) coordinate type with named statics matching
  Alignment's (topLeading, center, ..., bottomTrailing).  Replaces
  Alignment on LinearGradient / RadialGradient in Phase 1, chosen
  over making Alignment coordinate-aware because HorizontalAlignment
  is user-extensible via AlignmentID and a custom alignment's "unit
  coordinate" is genuinely undefined.  Conforms to Animatable with
  animatableData = AnimatablePair<Double, Double>.

EdgeInsets: Animatable:
  animatableData = AnimatablePair<AnimatablePair<Int, Int>,
  AnimatablePair<Int, Int>>.  Replaces the four hand-written
  paddingTop/Leading/Bottom/Trailing enum cases in Phase 3.

Color: Animatable:
  animatableData = 4 Doubles of OKLab (L, a, b, alpha), getter via
  existing Color.oklab(), setter via existing Color._fromOklab(...)
  + .mapped(to: self.profile, policy: .compressPerceptual).  Reuses
  the exact conversion path used by Color.interpolated(to:progress:
  method:.perceptual) so the animatableData arithmetic is pixel-
  equivalent to perceptual color interpolation.  Pinned by
  colorHalfwayInterpolationMatchesPerceptual test.
EOF
)"
```

- [ ] **Step 3: Verify the commit**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: commit present, stats match the file list above.

---

## Phase 1 — Alignment to UnitPoint on Gradients

**Goal:** Replace the `Alignment` type on `LinearGradient.startPoint` / `.endPoint` and `RadialGradient.center` with `UnitPoint`. No dual-API — this is a direct type-swap. The `.topLeading` / `.center` / etc. named constants already exist on `UnitPoint` from Phase 0, so most call sites compile unchanged.

**Files:**
- Modify: `Sources/Core/Styling.swift` (LinearGradient / RadialGradient type changes)
- Modify: `Sources/Core/Rasterizer.swift` (delete `unitCoordinates(for alignment:)`, inline direct `UnitPoint` access)
- Modify: `Sources/View/Foundation/StylePrimitives.swift` (initializer overloads, if any)
- Modify: `Sources/Core/Snapshots.swift` (describe helper for gradients)
- Modify: `Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift` (call sites)
- Modify: `Tests/SwiftTUITests/*GradientRenderingTests.swift` (fixtures)
- Modify: `Tests/SwiftTUITests/BorderGradientTests.swift` (fixtures)
- Modify: `Tests/CoreTests/*Tests.swift` (any fixtures constructing gradients inline)

### Task 1.1: Change `LinearGradient` and `RadialGradient` field types

- [ ] **Step 1: Read the current `LinearGradient` / `RadialGradient` definitions**

```bash
sed -n '123,193p' Sources/Core/Styling.swift
```

Current shape (from research): `LinearGradient.startPoint: Alignment`, `.endPoint: Alignment`; `RadialGradient.center: Alignment`, `.startRadius: Double`, `.endRadius: Double`.

- [ ] **Step 2: Modify the field types**

Edit `Sources/Core/Styling.swift`, in the `LinearGradient` struct:

```swift
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
  public var gradient: Gradient
  public var startPoint: UnitPoint
  public var endPoint: UnitPoint

  public init(
    gradient: Gradient,
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) {
    self.gradient = gradient
    self.startPoint = startPoint
    self.endPoint = endPoint
  }

  public init(
    colors: [Color],
    startPoint: UnitPoint,
    endPoint: UnitPoint
  ) {
    self.init(
      gradient: Gradient(colors: colors),
      startPoint: startPoint,
      endPoint: endPoint
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .linearGradient(self)
  }
}
```

And in `RadialGradient`:

```swift
public struct RadialGradient: ShapeStyle, Equatable, Sendable {
  public var gradient: Gradient
  public var center: UnitPoint
  public var startRadius: Double
  public var endRadius: Double

  public init(
    gradient: Gradient,
    center: UnitPoint,
    startRadius: Double,
    endRadius: Double
  ) {
    self.gradient = gradient
    self.center = center
    self.startRadius = startRadius
    self.endRadius = endRadius
  }

  public init(
    colors: [Color],
    center: UnitPoint = .center,
    startRadius: Double = 0,
    endRadius: Double
  ) {
    self.init(
      gradient: Gradient(colors: colors),
      center: center,
      startRadius: startRadius,
      endRadius: endRadius
    )
  }

  public func eraseToAnyShapeStyle() -> AnyShapeStyle {
    .radialGradient(self)
  }
}
```

- [ ] **Step 3: Rewrite `Rasterizer.unitCoordinates` to read `UnitPoint` directly**

Edit `Sources/Core/Rasterizer.swift` at `:2474-2510` (approximate — the `unitCoordinates(for alignment:)` helper).

Delete:

```swift
private func unitCoordinates(
  for alignment: Alignment
) -> (x: Double, y: Double) {
  // ...switch on alignment.horizontal / .vertical...
}
```

And replace its call sites in the same file:

```swift
// Before (around :2367-2368):
let start = unitCoordinates(for: gradient.startPoint)
let end = unitCoordinates(for: gradient.endPoint)

// After:
let start = (x: gradient.startPoint.x, y: gradient.startPoint.y)
let end = (x: gradient.endPoint.x, y: gradient.endPoint.y)
```

Do the same for the `RadialGradient` center call site in the same file.

- [ ] **Step 4: Update `Snapshots.swift` describe helper**

At `Sources/Core/Snapshots.swift` the `describe(_ gradient: LinearGradient)` and `describe(_ gradient: RadialGradient)` helpers likely print the `Alignment` debug name. Update them to print `UnitPoint(x:y:)` instead. Example:

```swift
private func describe(_ gradient: LinearGradient) -> String {
  let stops = gradient.gradient.stops
    .map { "\($0.color.hexString(format: .rrggbbaa))@\($0.location)" }
    .joined(separator: ",")
  return
    "stops=[\(stops)],"
    + "start=(\(gradient.startPoint.x),\(gradient.startPoint.y)),"
    + "end=(\(gradient.endPoint.x),\(gradient.endPoint.y))"
}
```

Same structural change for `RadialGradient`.

- [ ] **Step 5: Build the package and fix call-site failures**

```bash
swift build
```

Expected: several compile errors at call sites that passed `Alignment` values to `LinearGradient` or `RadialGradient` initializers. For each error:

- If the caller passed a named `Alignment` constant (`.topLeading`, `.center`, etc.), the same name exists on `UnitPoint` and no code change is needed — but the type annotation or explicit constructor may need updating.
- If the caller constructed `Alignment(horizontal: .leading, vertical: .top)` inline, replace it with the equivalent `UnitPoint(x: 0, y: 0)` (or the named constant when one matches).
- If the caller stored an `Alignment` value in a variable and passed it to a gradient, introduce a conversion helper or refactor the variable to `UnitPoint`.

Repeat until `swift build` is green. Then:

```bash
cd Examples/gallery && swift build && cd ../..
```

Expected: gallery builds clean.

- [ ] **Step 6: Run the snapshot and rendering tests**

```bash
swift test --filter "Gradient|BorderGradient"
```

Expected: all gradient-related tests pass. Snapshot output should be identical to pre-Phase-1 because the unit-coordinate conversion produces the same `(x, y)` values that the deleted `Rasterizer.unitCoordinates` switch would have produced (`.topLeading` → `(0, 0)`, `.bottomTrailing` → `(1, 1)`, etc.).

- [ ] **Step 7: Run the full suite**

```bash
swift test
```

Expected: all tests pass.

### Task 1.2: Commit Phase 1

- [ ] **Step 1: Stage and commit**

```bash
git add -u
git commit -m "$(cat <<'EOF'
Replace Alignment with UnitPoint on LinearGradient and RadialGradient

Phase 1 of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Gradient start/end
points and center are now typed as UnitPoint, a concrete (x, y) pair
that can be interpolated element-wise.  Alignment stays unchanged for
layout use — it's a named-slot system with user-extensible
AlignmentID guides, which is fundamentally incompatible with
continuous interpolation.

Direct type-swap, no dual-API.  Most call sites compile unchanged
because .topLeading / .center / .bottomTrailing etc. are declared as
static constants on UnitPoint with the same names Alignment uses.
Inline-constructed Alignment values passed to gradient initializers
required direct migration to UnitPoint(x:y:) form.

Rasterizer.unitCoordinates(for alignment:) deleted — the switch from
named alignment to unit coordinates was the only place the library
converted discrete alignment slots to continuous coordinates, and
UnitPoint eliminates the need.  Call sites now read startPoint.x /
startPoint.y directly.

Snapshot describe helpers updated to print UnitPoint coordinates
instead of Alignment debug names.
EOF
)"
```

---

## Phase 2 — Compound Animatable Conformances

**Goal:** Add `Animatable` conformances to `Gradient.Stop`, `Gradient`, `LinearGradient`, `RadialGradient`, `PatternFill.Paint`, and `PatternFill`. Each uses `AnimatablePair` (for fixed composition) or `AnimatableArray` (for variable-length stop arrays). Cross-variant `PatternFill.Paint` changes snap.

**Files:**
- Create: `Sources/Core/GradientAnimatable.swift`
- Create: `Sources/Core/PatternFillAnimatable.swift`
- Create: `Tests/CoreTests/GradientAnimatableTests.swift`
- Create: `Tests/CoreTests/PatternFillAnimatableTests.swift`

### Task 2.1: `Gradient.Stop` and `Gradient` conformances

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/GradientAnimatableTests.swift`:

```swift
import Testing

@testable import Core

@Test("Gradient.Stop animatableData carries color and location")
func gradientStopAnimatableData() {
  let stop = Gradient.Stop(color: .red, location: 0.25)
  let data = stop.animatableData
  // color's animatableData is an AnimatablePair of pairs; location
  // is the second element of the outer pair.
  #expect(data.second == 0.25)
}

@Test("Gradient.Stop halfway interpolation")
func gradientStopInterpolation() {
  let from = Gradient.Stop(color: .red, location: 0.0)
  let to = Gradient.Stop(color: .blue, location: 1.0)
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(abs(result.location - 0.5) < 0.001)
  // Color should be perceptual midpoint between red and blue.
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(result.color.red - expected.red) < 0.001)
  #expect(abs(result.color.blue - expected.blue) < 0.001)
}

@Test("Gradient animatableData count-mismatch is non-interpolable")
func gradientCountMismatchSnap() {
  let two = Gradient(colors: [.red, .blue])
  let three = Gradient(colors: [.red, .green, .blue])
  #expect(!two.animatableData.isInterpolable(to: three.animatableData))
}

@Test("Gradient animatableData matching counts interpolate element-wise")
func gradientMatchingCountsInterpolate() {
  let from = Gradient(colors: [.red, .blue])
  let to = Gradient(colors: [.blue, .red])
  #expect(from.animatableData.isInterpolable(to: to.animatableData))
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(result.stops.count == 2)
  // Each stop should be halfway between its from and to.
  let firstExpected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(result.stops[0].color.red - firstExpected.red) < 0.001)
}

@Test("LinearGradient animatableData interpolates gradient and endpoints")
func linearGradientInterpolation() {
  let from = LinearGradient(
    colors: [.red, .blue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  let to = LinearGradient(
    colors: [.blue, .red],
    startPoint: .topTrailing,
    endPoint: .bottomLeading
  )
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  // Start point should be halfway between (0,0) and (1,0).
  #expect(abs(result.startPoint.x - 0.5) < 0.001)
  #expect(abs(result.startPoint.y - 0) < 0.001)
  // End point should be halfway between (1,1) and (0,1).
  #expect(abs(result.endPoint.x - 0.5) < 0.001)
  #expect(abs(result.endPoint.y - 1) < 0.001)
}

@Test("RadialGradient animatableData interpolates center and radii")
func radialGradientInterpolation() {
  let from = RadialGradient(
    colors: [.red, .blue],
    center: .topLeading,
    startRadius: 0,
    endRadius: 10
  )
  let to = RadialGradient(
    colors: [.blue, .red],
    center: .bottomTrailing,
    startRadius: 5,
    endRadius: 20
  )
  var delta = to.animatableData
  delta -= from.animatableData
  delta.scale(by: 0.5)
  var result = from
  var resultData = result.animatableData
  resultData += delta
  result.animatableData = resultData
  #expect(abs(result.center.x - 0.5) < 0.001)
  #expect(abs(result.center.y - 0.5) < 0.001)
  #expect(abs(result.startRadius - 2.5) < 0.001)
  #expect(abs(result.endRadius - 15) < 0.001)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter "gradient"
```

Expected: compilation failure — `Gradient.Stop`, `Gradient`, `LinearGradient`, `RadialGradient` do not conform to `Animatable`.

- [ ] **Step 3: Implement the conformances**

Create `Sources/Core/GradientAnimatable.swift`:

```swift
extension Gradient.Stop: Animatable {
  public typealias AnimatableData = AnimatablePair<Color.AnimatableData, Double>

  public var animatableData: AnimatableData {
    get { AnimatablePair(color.animatableData, location) }
    set {
      color.animatableData = newValue.first
      location = newValue.second
    }
  }
}

extension Gradient: Animatable {
  public typealias AnimatableData = AnimatableArray<Gradient.Stop.AnimatableData>

  public var animatableData: AnimatableData {
    get {
      AnimatableArray(stops.map { $0.animatableData })
    }
    set {
      // Count mismatch → caller should have checked isInterpolable
      // first.  If they didn't, clamp to the current stop count so
      // we never produce a half-rebuilt gradient.
      guard newValue.elements.count == stops.count else { return }
      for i in stops.indices {
        stops[i].animatableData = newValue.elements[i]
      }
    }
  }
}

extension LinearGradient: Animatable {
  public typealias AnimatableData = AnimatablePair<
    Gradient.AnimatableData,
    AnimatablePair<UnitPoint.AnimatableData, UnitPoint.AnimatableData>
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        gradient.animatableData,
        AnimatablePair(startPoint.animatableData, endPoint.animatableData)
      )
    }
    set {
      gradient.animatableData = newValue.first
      startPoint.animatableData = newValue.second.first
      endPoint.animatableData = newValue.second.second
    }
  }
}

extension RadialGradient: Animatable {
  public typealias AnimatableData = AnimatablePair<
    Gradient.AnimatableData,
    AnimatablePair<
      UnitPoint.AnimatableData,
      AnimatablePair<Double, Double>
    >
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        gradient.animatableData,
        AnimatablePair(
          center.animatableData,
          AnimatablePair(startRadius, endRadius)
        )
      )
    }
    set {
      gradient.animatableData = newValue.first
      center.animatableData = newValue.second.first
      startRadius = newValue.second.second.first
      endRadius = newValue.second.second.second
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "gradient"
```

Expected: all 6 tests pass. Note that `Gradient.Stop` and `Gradient` need to be mutated through the conformance, so `var stops: [Gradient.Stop]` on `Gradient` must remain settable — it already is (see `Sources/Core/Styling.swift:99`).

### Task 2.2: `PatternFill.Paint` and `PatternFill` conformances

- [ ] **Step 1: Write the failing tests**

Create `Tests/CoreTests/PatternFillAnimatableTests.swift`:

```swift
import Testing

@testable import Core

@Test("PatternFill.Paint same-variant color interpolation")
func patternFillPaintSameVariantColor() {
  let from = PatternFill.Paint.color(.red)
  let to = PatternFill.Paint.color(.blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let color) = halfway else {
    Issue.record("expected .color variant after same-variant interpolation")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(color.red - expected.red) < 0.001)
}

@Test("PatternFill.Paint same-variant linear gradient interpolation")
func patternFillPaintSameVariantLinearGradient() {
  let from = PatternFill.Paint.linearGradient(
    LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  )
  let to = PatternFill.Paint.linearGradient(
    LinearGradient(colors: [.blue, .red], startPoint: .topTrailing, endPoint: .bottomLeading)
  )
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .linearGradient(let g) = halfway else {
    Issue.record("expected .linearGradient variant")
    return
  }
  #expect(abs(g.startPoint.x - 0.5) < 0.001)
}

@Test("PatternFill.Paint cross-variant is not interpolable")
func patternFillPaintCrossVariantSnap() {
  let color = PatternFill.Paint.color(.red)
  let gradient = PatternFill.Paint.linearGradient(
    LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
  )
  #expect(!color.isInterpolable(to: gradient))
  // Interpolation with non-interpolable variants returns the target
  // (snap behavior).
  let snapped = color.interpolated(to: gradient, progress: 0.5)
  guard case .linearGradient = snapped else {
    Issue.record("cross-variant interpolation must snap to the target variant")
    return
  }
}

@Test("PatternFill Animatable — foreground color interpolation")
func patternFillAnimatableForeground() {
  let from = PatternFill(glyph: "░", foreground: .red)
  let to = PatternFill(glyph: "░", foreground: .blue)
  #expect(from.isInterpolable(to: to))
  let halfway = from.interpolated(to: to, progress: 0.5)
  guard case .color(let fgColor) = halfway.foreground else {
    Issue.record("expected color foreground")
    return
  }
  let expected = Color.red.interpolated(to: .blue, progress: 0.5)
  #expect(abs(fgColor.red - expected.red) < 0.001)
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter "patternFillPaint|patternFillAnimatable"
```

Expected: compilation failure.

- [ ] **Step 3: Implement the conformances**

Create `Sources/Core/PatternFillAnimatable.swift`:

```swift
extension PatternFill.Paint {
  /// Returns `true` when `self` and `other` can be interpolated
  /// under the animation pipeline.  Cross-variant transitions
  /// (e.g. `.color` → `.linearGradient`) snap at the controller
  /// level — same-variant transitions interpolate via the wrapped
  /// type's own `animatableData`.
  public func isInterpolable(to other: PatternFill.Paint) -> Bool {
    switch (self, other) {
    case (.color, .color):
      return true
    case (.linearGradient(let a), .linearGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    case (.radialGradient(let a), .radialGradient(let b)):
      return a.gradient.stops.count == b.gradient.stops.count
    default:
      return false
    }
  }

  /// Returns the interpolated paint at `progress` from `self` to
  /// `other`.  Cross-variant transitions snap to `other`.
  public func interpolated(
    to other: PatternFill.Paint,
    progress t: Double
  ) -> PatternFill.Paint {
    switch (self, other) {
    case (.color(var a), .color(let b)):
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .color(a)

    case (.linearGradient(var a), .linearGradient(let b)):
      guard a.animatableData.isInterpolable(to: b.animatableData) else {
        return .linearGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .linearGradient(a)

    case (.radialGradient(var a), .radialGradient(let b)):
      guard a.animatableData.isInterpolable(to: b.animatableData) else {
        return .radialGradient(b)
      }
      var delta = b.animatableData
      delta -= a.animatableData
      delta.scale(by: t)
      var data = a.animatableData
      data += delta
      a.animatableData = data
      return .radialGradient(a)

    default:
      // Cross-variant: snap to target.
      return other
    }
  }
}

extension AnimatablePair where First == Gradient.AnimatableData, Second == AnimatablePair<
  UnitPoint.AnimatableData, UnitPoint.AnimatableData
> {
  // Namespace hook for LinearGradient.AnimatableData interpolability
  // checks.  Gradient count mismatch is the only non-interpolable
  // case.
  func isInterpolable(to other: Self) -> Bool {
    first.isInterpolable(to: other.first)
  }
}

extension PatternFill {
  /// Returns `true` when both `foreground` and `background` can
  /// be interpolated to their counterparts in `other` (same
  /// variants, compatible gradient stop counts, and matching
  /// background presence).
  public func isInterpolable(to other: PatternFill) -> Bool {
    guard glyph == other.glyph else { return false }
    guard foreground.isInterpolable(to: other.foreground) else { return false }
    switch (background, other.background) {
    case (nil, nil):
      return true
    case (let a?, let b?):
      return a.isInterpolable(to: b)
    default:
      return false
    }
  }

  /// Returns the pattern fill at `progress` from `self` to `other`.
  /// Glyph changes snap (glyph identity is not interpolable).
  /// Background presence must match or the entire pattern snaps.
  public func interpolated(
    to other: PatternFill,
    progress t: Double
  ) -> PatternFill {
    guard isInterpolable(to: other) else { return other }
    let newForeground = foreground.interpolated(to: other.foreground, progress: t)
    let newBackground: PatternFill.Paint?
    switch (background, other.background) {
    case (nil, nil):
      newBackground = nil
    case (let a?, let b?):
      newBackground = a.interpolated(to: b, progress: t)
    default:
      newBackground = other.background
    }
    return PatternFill(
      glyph: glyph,
      foreground: newForeground,
      background: newBackground
    )
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "patternFillPaint|patternFillAnimatable"
```

Expected: all 4 tests pass.

- [ ] **Step 5: Run the full suite**

```bash
swift test
```

Expected: all tests pass.

### Task 2.3: Commit Phase 2

- [ ] **Step 1: Stage and commit**

```bash
git add \
  Sources/Core/GradientAnimatable.swift \
  Sources/Core/PatternFillAnimatable.swift \
  Tests/CoreTests/GradientAnimatableTests.swift \
  Tests/CoreTests/PatternFillAnimatableTests.swift

git commit -m "$(cat <<'EOF'
Add Animatable conformances for Gradient, LinearGradient, RadialGradient, PatternFill

Phase 2 of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Builds on Phase 0's
primitives (AnimatableArray, UnitPoint, Color: Animatable) and Phase
1's UnitPoint-valued gradient endpoints.

Conformances:

Gradient.Stop: Animatable
  AnimatableData = AnimatablePair<Color.AnimatableData, Double>.

Gradient: Animatable
  AnimatableData = AnimatableArray<Gradient.Stop.AnimatableData>.
  Stop-count mismatch snaps via AnimatableArray's isInterpolable(to:).

LinearGradient: Animatable
  AnimatableData composes gradient + (startPoint, endPoint) pairs.

RadialGradient: Animatable
  AnimatableData composes gradient + (center, (startRadius,
  endRadius)) pairs.

PatternFill.Paint: isInterpolable + interpolated helpers
  Same-variant (color↔color, linearGradient↔linearGradient,
  radialGradient↔radialGradient) interpolates.  Cross-variant snaps
  to target.  Glyph changes snap.

PatternFill: isInterpolable + interpolated helpers
  Delegates to foreground/background Paint interpolation, requires
  matching glyph and matching background presence.

None of these are wired into AnimationController yet — Phase 3 does
that.  They're standalone helpers with per-conformance unit tests.
EOF
)"
```

---

## Phase 3 — AnimationController Value-Interpolation Rewrite

**Goal:** Replace the enum-dispatch model (`AnimatableProperty` + `AnimatableValue` + 15 hardcoded slots) with a slot-keyed, type-erased model built on `AnimatableSlot` + `AnyAnimatable`. Every existing animation behavior continues to work. The controller stores heterogeneous animatable values per slot; diffing, interpolation, and writeback dispatch uniformly through `AnyAnimatable` except for the `applyValue` writeback which remains slot-specific (because writeback destinations on `DrawMetadata` / `LayoutBehavior` are structurally different per slot).

**Files:**
- Modify: `Sources/SwiftTUI/AnimationController.swift` (substantial rewrite — ~420 LOC replaced)
- Create: `Sources/SwiftTUI/AnyAnimatable.swift`
- Modify: `Tests/SwiftTUITests/AnimationControllerTests.swift` (update tests that reference `AnimatableProperty` / `AnimatableValue`)

### Task 3.1: `AnyAnimatable` type-erased wrapper

- [ ] **Step 1: Write the failing tests**

Extend `Tests/SwiftTUITests/AnimationControllerTests.swift` with a new test block (place it after the `FireCounter` helper, inside the same test file):

```swift
// MARK: - AnyAnimatable type erasure

@MainActor
@Suite("AnyAnimatable type erasure")
struct AnyAnimatableTests {

  @Test("Wraps a Double and round-trips the value")
  func wrapsDouble() {
    let wrapped = AnyAnimatable(Double(1.5))
    #expect(wrapped.unwrap(as: Double.self) == 1.5)
  }

  @Test("Equality holds when wrapped types and values match")
  func equalitySameTypeSameValue() {
    #expect(AnyAnimatable(Double(1.0)) == AnyAnimatable(Double(1.0)))
    #expect(AnyAnimatable(Color.red) == AnyAnimatable(Color.red))
  }

  @Test("Equality is false when wrapped types differ")
  func equalityDifferentTypes() {
    #expect(AnyAnimatable(Double(1.0)) != AnyAnimatable(Int(1)))
  }

  @Test("Equality is false when values differ")
  func equalityDifferentValues() {
    #expect(AnyAnimatable(Double(1.0)) != AnyAnimatable(Double(2.0)))
  }

  @Test("interpolated between same-type values produces intermediate value")
  func interpolateSameType() {
    let from = AnyAnimatable(Double(0.0))
    let to = AnyAnimatable(Double(10.0))
    let halfway = from.interpolated(to: to, progress: 0.5)
    #expect(halfway?.unwrap(as: Double.self) == 5.0)
  }

  @Test("interpolated returns nil when wrapped types mismatch")
  func interpolateTypeMismatch() {
    let from = AnyAnimatable(Double(0.0))
    let to = AnyAnimatable(Int(10))
    let halfway = from.interpolated(to: to, progress: 0.5)
    #expect(halfway == nil)
  }

  @Test("Wraps a Color and interpolation uses OKLab perceptual path")
  func colorInterpolation() {
    let from = AnyAnimatable(Color.red)
    let to = AnyAnimatable(Color.blue)
    let halfway = from.interpolated(to: to, progress: 0.5)
    let unwrapped = halfway?.unwrap(as: Color.self)
    #expect(unwrapped != nil)
    let expected = Color.red.interpolated(to: .blue, progress: 0.5)
    if let c = unwrapped {
      #expect(abs(c.red - expected.red) < 0.001)
      #expect(abs(c.green - expected.green) < 0.001)
      #expect(abs(c.blue - expected.blue) < 0.001)
    }
  }

  @Test("Wraps a LinearGradient and interpolates endpoints + stops")
  func linearGradientInterpolation() {
    let from = AnyAnimatable(
      LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
    let to = AnyAnimatable(
      LinearGradient(colors: [.blue, .red], startPoint: .topTrailing, endPoint: .bottomLeading)
    )
    let halfway = from.interpolated(to: to, progress: 0.5)
    let g = halfway?.unwrap(as: LinearGradient.self)
    #expect(g != nil)
    if let g {
      #expect(abs(g.startPoint.x - 0.5) < 0.001)
    }
  }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter "AnyAnimatable"
```

Expected: compilation failure — `AnyAnimatable` is not defined.

- [ ] **Step 3: Implement `AnyAnimatable`**

Create `Sources/SwiftTUI/AnyAnimatable.swift`:

```swift
package import Core

/// Type-erased wrapper around a value conforming to ``Animatable``.
///
/// The animation controller stores heterogeneous animatable values
/// per ``AnimatableSlot`` — opacity is a `Double`, foreground style
/// is a `LinearGradient` or a `Color` or a `PatternFill`, padding is
/// an `EdgeInsets`, and so on — and needs a uniform storage
/// representation that supports equality, same-type interpolation,
/// and unwrapping back to the original type at apply time.  This is
/// that representation.
///
/// ## Semantics
///
/// - **Equality:** two ``AnyAnimatable`` are equal iff they wrap the
///   same concrete type and the wrapped values are equal by that
///   type's own ``Equatable`` conformance.  Different wrapped types
///   compare as not-equal even if their ``animatableData`` happen to
///   coincide.
/// - **Interpolation:** ``interpolated(to:progress:)`` returns `nil`
///   when the wrapped types don't match.  The controller treats
///   `nil` as a snap signal and writes the target value directly
///   without interpolating.  Same-type interpolation uses the
///   wrapped type's ``animatableData`` arithmetic: `a + (b - a) * t`.
/// - **Thread safety:** the wrapped value must be `Sendable`, which
///   is enforced by the `Equatable & Sendable & Animatable` bound on
///   ``init(_:)``.
package struct AnyAnimatable: Equatable, @unchecked Sendable {
  private let box: any _AnyAnimatableBox

  package init<T: Animatable & Equatable & Sendable>(_ value: T) {
    self.box = _AnimatableBox(value)
  }

  package func unwrap<T: Animatable & Equatable & Sendable>(as _: T.Type) -> T? {
    box.unwrap(as: T.self)
  }

  package func interpolated(
    to other: AnyAnimatable,
    progress: Double
  ) -> AnyAnimatable? {
    box.interpolated(to: other.box, progress: progress)
  }

  package static func == (lhs: AnyAnimatable, rhs: AnyAnimatable) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }
}

private protocol _AnyAnimatableBox: Sendable {
  func isEqual(to other: any _AnyAnimatableBox) -> Bool
  func unwrap<T>(as _: T.Type) -> T?
  func interpolated(
    to other: any _AnyAnimatableBox,
    progress: Double
  ) -> AnyAnimatable?
}

private struct _AnimatableBox<T: Animatable & Equatable & Sendable>: _AnyAnimatableBox {
  let value: T

  init(_ value: T) {
    self.value = value
  }

  func isEqual(to other: any _AnyAnimatableBox) -> Bool {
    guard let other = other as? _AnimatableBox<T> else { return false }
    return value == other.value
  }

  func unwrap<U>(as _: U.Type) -> U? {
    value as? U
  }

  func interpolated(
    to other: any _AnyAnimatableBox,
    progress t: Double
  ) -> AnyAnimatable? {
    guard let other = other as? _AnimatableBox<T> else { return nil }
    // Generic interpolation via animatableData arithmetic.
    var fromData = value.animatableData
    var delta = other.value.animatableData
    delta -= fromData
    delta.scale(by: t)
    fromData += delta
    var result = value
    result.animatableData = fromData
    return AnyAnimatable(result)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter "AnyAnimatable"
```

Expected: all 8 tests pass.

### Task 3.2: `AnimatableSlot` enum and slot-keyed `AnimatableSnapshot`

- [ ] **Step 1: Define the slot enum and new snapshot shape**

In `Sources/SwiftTUI/AnimationController.swift`, *replace* the existing `AnimatableProperty` enum (`:12-28`) and `AnimatableValue` enum (`:32-36`) with:

```swift
/// Identifies a logical animatable slot on a ``ResolvedNode``.  Each
/// slot maps to a specific writeback destination in ``applyValue``.
///
/// Compound slots (``foregroundShapeStyle``, ``backgroundShapeStyle``,
/// ``borderShapeStyle``) carry heterogeneous animatable values — the
/// slot identifies the destination but the wrapped ``AnyAnimatable``
/// determines the concrete type (Color, LinearGradient, RadialGradient,
/// PatternFill).
package enum AnimatableSlot: Hashable, Sendable {
  case opacity
  case foregroundShapeStyle
  case backgroundShapeStyle
  case borderShapeStyle
  case borderBlendPhase
  case padding
  case offset
  case position
  case frameWidth
  case frameHeight
}

/// Keyed identifier for a single active animation: the view
/// ``Identity`` plus the ``AnimatableSlot`` being animated.  Every
/// slot on a given identity can be in flight independently.
package struct AnimationKey: Hashable, Sendable {
  package var identity: Identity
  package var slot: AnimatableSlot
}
```

Remove the old `AnimationKey` at `:5-8` (the one tied to `AnimatableProperty`) — the new definition supersedes it with `slot: AnimatableSlot`.

- [ ] **Step 2: Redefine `AnimatableSnapshot` as a slot-keyed dict**

Still in `Sources/SwiftTUI/AnimationController.swift`, replace the `AnimatableSnapshot` struct (`:39-144`) with:

```swift
/// Snapshot of every tracked animatable slot's value for one view
/// ``Identity`` after a resolve pass.  Stored per-identity in
/// ``AnimationController/previousSnapshots`` and diffed against the
/// next frame's snapshot to detect changes.
package struct AnimatableSnapshot: Sendable {
  package var values: [AnimatableSlot: AnyAnimatable]

  package init(values: [AnimatableSlot: AnyAnimatable] = [:]) {
    self.values = values
  }

  package subscript(slot: AnimatableSlot) -> AnyAnimatable? {
    get { values[slot] }
    set { values[slot] = newValue }
  }

  /// Extracts every animatable slot from the given resolved node.
  /// Slots whose source value is missing or not-Animatable are
  /// simply absent from the result dictionary.
  package static func extract(from node: ResolvedNode) -> AnimatableSnapshot {
    var snapshot = AnimatableSnapshot()

    // Opacity (Double)
    if let opacity = node.drawMetadata.baseStyle.explicitOpacity {
      snapshot[.opacity] = AnyAnimatable(opacity)
    }

    // Shape styles (Color / LinearGradient / RadialGradient /
    // PatternFill are all Animatable-conforming after Phase 2).
    if let fgStyle = node.drawMetadata.baseStyle.foregroundStyle,
      let fg = extractAnimatableShapeStyle(from: fgStyle)
    {
      snapshot[.foregroundShapeStyle] = fg
    } else if let envFg = extractAnimatableShapeStyle(
      from: node.environmentSnapshot.style.foregroundStyle
    ) {
      snapshot[.foregroundShapeStyle] = envFg
    }

    if let bgStyle = node.drawMetadata.baseStyle.backgroundStyle,
      let bg = extractAnimatableShapeStyle(from: bgStyle)
    {
      snapshot[.backgroundShapeStyle] = bg
    }

    if let borderStyle = node.drawMetadata.borderShapeStyle,
      let border = extractAnimatableShapeStyle(from: borderStyle)
    {
      snapshot[.borderShapeStyle] = border
    }

    // Layout-derived slots.
    switch node.layoutBehavior {
    case .padding(let insets):
      snapshot[.padding] = AnyAnimatable(insets)
    case .offset(let x, let y):
      snapshot[.offset] = AnyAnimatable(
        AnimatablePair(x, y)
      )
    case .position(let x, let y):
      snapshot[.position] = AnyAnimatable(
        AnimatablePair(x, y)
      )
    case .frame(let width, let height, _):
      snapshot[.frameWidth] = AnyAnimatable(width)
      snapshot[.frameHeight] = AnyAnimatable(height)
    case .border(_, _, _, let blend, let blendPhase, _):
      if blend != nil {
        snapshot[.borderBlendPhase] = AnyAnimatable(blendPhase)
      }
    case .flexibleFrame(
      let minWidth, let idealWidth, let maxWidth,
      let minHeight, let idealHeight, let maxHeight,
      _):
      if let w = firstFiniteValue(of: [maxWidth, idealWidth, minWidth]) {
        snapshot[.frameWidth] = AnyAnimatable(w)
      }
      if let h = firstFiniteValue(of: [maxHeight, idealHeight, minHeight]) {
        snapshot[.frameHeight] = AnyAnimatable(h)
      }
    default:
      break
    }

    return snapshot
  }

  /// Unwraps an ``AnyShapeStyle`` to a concrete animatable value
  /// the controller can interpolate.  Returns `nil` for shape
  /// styles that can't be reduced to a single animatable
  /// conformance (semantic tokens, terminal chrome, etc.).
  private static func extractAnimatableShapeStyle(
    from style: AnyShapeStyle?
  ) -> AnyAnimatable? {
    guard let style else { return nil }
    switch style {
    case .color(let color):
      return AnyAnimatable(color)
    case .linearGradient(let gradient):
      return AnyAnimatable(gradient)
    case .radialGradient(let gradient):
      return AnyAnimatable(gradient)
    case .patternFill(let pattern):
      return AnyAnimatable(pattern)
    case .opacity(let inner, _):
      return extractAnimatableShapeStyle(from: inner)
    case .terminalChrome, .semantic:
      return nil
    }
  }

  private static func firstFiniteValue(of dimensions: [ProposedDimension?]) -> Int? {
    for dimension in dimensions {
      if case .finite(let value) = dimension {
        return value
      }
    }
    return nil
  }
}
```

- [ ] **Step 2: Rewrite `diffAndEnqueue`**

Replace `diffAndEnqueue(identity:previous:current:request:batchID:timestamp:)` and the old `enqueueIfChanged` generic helper with a single slot-iterating diff:

```swift
private func diffAndEnqueue(
  identity: Identity,
  previous: AnimatableSnapshot,
  current: AnimatableSnapshot,
  request: AnimationRequest,
  batchID: AnimationBatchID?,
  timestamp: MonotonicInstant
) {
  // Union of slot keys from both snapshots — a slot that appears
  // in only one snapshot is a "one side nil" change and snaps.
  var slots = Set(previous.values.keys)
  slots.formUnion(current.values.keys)

  for slot in slots {
    enqueueSlotChangeIfNeeded(
      identity: identity,
      slot: slot,
      previous: previous[slot],
      current: current[slot],
      request: request,
      batchID: batchID,
      timestamp: timestamp
    )
  }
}

private func enqueueSlotChangeIfNeeded(
  identity: Identity,
  slot: AnimatableSlot,
  previous: AnyAnimatable?,
  current: AnyAnimatable?,
  request: AnimationRequest,
  batchID: AnimationBatchID?,
  timestamp: MonotonicInstant
) {
  // No change → nothing to do.
  guard previous != current else { return }

  let key = AnimationKey(identity: identity, slot: slot)

  switch request {
  case .inherit, .disabled:
    if let superseded = activeAnimations.removeValue(forKey: key) {
      releaseBatch(superseded.batchID)
    }

  case .animate(let box):
    guard let previous, let current else {
      // One side nil — cannot interpolate, snap.
      if let superseded = activeAnimations.removeValue(forKey: key) {
        releaseBatch(superseded.batchID)
      }
      return
    }

    // Retarget: if an animation already exists, sample its current
    // value and use it as the new `from` — matches the existing
    // mid-flight retarget behavior.
    let effectiveFrom: AnyAnimatable
    if let existing = activeAnimations[key],
      let sampled = sample(existing, at: timestamp)
    {
      effectiveFrom = sampled
      releaseBatch(existing.batchID)
    } else {
      effectiveFrom = previous
    }

    retainBatch(batchID)
    activeAnimations[key] = ActiveAnimation(
      from: effectiveFrom,
      to: current,
      animationBox: box,
      startTime: timestamp,
      batchID: batchID
    )
  }
}
```

- [ ] **Step 3: Rewrite `ActiveAnimation`, `interpolate`, and `sample`**

Change `ActiveAnimation`'s `from` / `to` fields from `AnimatableValue` to `AnyAnimatable`:

```swift
package struct ActiveAnimation: Sendable {
  package var from: AnyAnimatable
  package var to: AnyAnimatable
  package var animationBox: AnimationBox
  package var startTime: MonotonicInstant
  package var customState: AnimationState = .init()
  package var batchID: AnimationBatchID?
}
```

Replace the old `interpolate(from:to:progress:)` helper with a one-liner that delegates to `AnyAnimatable.interpolated`:

```swift
private func interpolate(
  from: AnyAnimatable,
  to: AnyAnimatable,
  progress: Double
) -> AnyAnimatable {
  // Snap to target on type mismatch — the controller should never
  // produce a slot animation where the types differ (diffAndEnqueue
  // doesn't enqueue in that case), but belt-and-suspenders here.
  from.interpolated(to: to, progress: progress) ?? to
}
```

Update `sample(_ animation: ActiveAnimation, at:)` to return `AnyAnimatable?` computed via the same generic interpolation:

```swift
private func sample(
  _ animation: ActiveAnimation,
  at timestamp: MonotonicInstant
) -> AnyAnimatable? {
  guard let anim = registeredAnimations[animation.animationBox] else {
    return nil
  }
  let elapsed = animation.startTime.duration(to: timestamp)
  var state = animation.customState
  guard let progress = anim.evaluate(elapsed: elapsed, state: &state) else {
    return animation.to
  }
  return interpolate(
    from: animation.from,
    to: animation.to,
    progress: progress
  )
}
```

- [ ] **Step 4: Rewrite `applyValue`**

Replace the existing `applyValue(_:property:value:)` switch with a slot-keyed version that unwraps `AnyAnimatable` to the expected concrete type per slot:

```swift
private func applyValue(
  _ node: inout ResolvedNode,
  slot: AnimatableSlot,
  value: AnyAnimatable
) {
  switch slot {
  case .opacity:
    guard let opacity = value.unwrap(as: Double.self) else { return }
    var drawMetadata = node.drawMetadata
    drawMetadata.baseStyle.explicitOpacity = opacity
    node.drawMetadata = drawMetadata

  case .foregroundShapeStyle:
    guard let style = unwrapShapeStyle(value) else { return }
    var drawMetadata = node.drawMetadata
    drawMetadata.baseStyle.foregroundStyle = style
    node.drawMetadata = drawMetadata

  case .backgroundShapeStyle:
    guard let style = unwrapShapeStyle(value) else { return }
    var drawMetadata = node.drawMetadata
    drawMetadata.baseStyle.backgroundStyle = style
    node.drawMetadata = drawMetadata

  case .borderShapeStyle:
    guard let style = unwrapShapeStyle(value) else { return }
    var drawMetadata = node.drawMetadata
    drawMetadata.borderShapeStyle = style
    node.drawMetadata = drawMetadata

  case .borderBlendPhase:
    guard let phase = value.unwrap(as: Double.self) else { return }
    if case .border(
      let set,
      let foreground,
      let background,
      let blend,
      _,
      let sides
    ) = node.layoutBehavior {
      node.setLayoutBehaviorPreservingDerivedState(
        .border(
          set,
          foreground: foreground,
          background: background,
          blend: blend,
          blendPhase: phase,
          sides: sides
        )
      )
    }

  case .padding:
    guard let insets = value.unwrap(as: EdgeInsets.self) else { return }
    node.setLayoutBehaviorPreservingDerivedState(.padding(insets))

  case .offset:
    guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self) else {
      return
    }
    if case .offset = node.layoutBehavior {
      node.setLayoutBehaviorPreservingDerivedState(
        .offset(x: pair.first, y: pair.second)
      )
    }

  case .position:
    guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self) else {
      return
    }
    if case .position = node.layoutBehavior {
      node.setLayoutBehaviorPreservingDerivedState(
        .position(x: pair.first, y: pair.second)
      )
    }

  case .frameWidth:
    guard let width = value.unwrap(as: Int.self) else { return }
    applyFrameWidth(width, to: &node)

  case .frameHeight:
    guard let height = value.unwrap(as: Int.self) else { return }
    applyFrameHeight(height, to: &node)
  }
}

private func unwrapShapeStyle(_ value: AnyAnimatable) -> AnyShapeStyle? {
  if let color = value.unwrap(as: Color.self) {
    return .color(color)
  }
  if let linear = value.unwrap(as: LinearGradient.self) {
    return .linearGradient(linear)
  }
  if let radial = value.unwrap(as: RadialGradient.self) {
    return .radialGradient(radial)
  }
  if let pattern = value.unwrap(as: PatternFill.self) {
    return .patternFill(pattern)
  }
  return nil
}

private func applyFrameWidth(_ width: Int, to node: inout ResolvedNode) {
  switch node.layoutBehavior {
  case .frame(_, let height, let alignment):
    node.setLayoutBehaviorPreservingDerivedState(
      .frame(width: width, height: height, alignment: alignment)
    )
  case .flexibleFrame(
    let minWidth, let idealWidth, let maxWidth,
    let minHeight, let idealHeight, let maxHeight,
    let alignment):
    let (newMax, newIdeal, newMin) = Self.replaceFirstFinite(
      width: width,
      dimensions: (maxWidth, idealWidth, minWidth)
    )
    node.setLayoutBehaviorPreservingDerivedState(
      .flexibleFrame(
        minWidth: newMin,
        idealWidth: newIdeal,
        maxWidth: newMax,
        minHeight: minHeight,
        idealHeight: idealHeight,
        maxHeight: maxHeight,
        alignment: alignment
      ))
  default:
    break
  }
}

private func applyFrameHeight(_ height: Int, to node: inout ResolvedNode) {
  switch node.layoutBehavior {
  case .frame(let width, _, let alignment):
    node.setLayoutBehaviorPreservingDerivedState(
      .frame(width: width, height: height, alignment: alignment)
    )
  case .flexibleFrame(
    let minWidth, let idealWidth, let maxWidth,
    let minHeight, let idealHeight, let maxHeight,
    let alignment):
    let (newMax, newIdeal, newMin) = Self.replaceFirstFinite(
      width: height,
      dimensions: (maxHeight, idealHeight, minHeight)
    )
    node.setLayoutBehaviorPreservingDerivedState(
      .flexibleFrame(
        minWidth: minWidth,
        idealWidth: idealWidth,
        maxWidth: maxWidth,
        minHeight: newMin,
        idealHeight: newIdeal,
        maxHeight: newMax,
        alignment: alignment
      ))
  default:
    break
  }
}
```

Note: the old per-edge padding slot cases (`paddingTop`, `paddingLeading`, etc.) collapse into a single `.padding` slot carrying an `EdgeInsets`. Per-edge animation still works because `EdgeInsets.animatableData` composes the four edges in a single `AnimatablePair`, and `a + (b - a) * t` is element-wise. The behavioral parity test is in Task 3.3.

- [ ] **Step 5: Update `applyInterpolations` to use the new `applyValue` signature**

At `applyInterpolations`, change `interpolated[key.identity]` from `[AnimatableProperty: AnimatableValue]` to `[AnimatableSlot: AnyAnimatable]`:

```swift
var interpolated: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]

// ... in the loop ...
interpolated[key.identity, default: [:]][key.slot] = value
```

And in `applyInterpolatedValues`:

```swift
private func applyInterpolatedValues(
  tree: ResolvedNode,
  interpolated: [Identity: [AnimatableSlot: AnyAnimatable]]
) -> ResolvedNode {
  var node = tree
  if let values = interpolated[node.identity] {
    for (slot, value) in values {
      applyValue(&node, slot: slot, value: value)
    }
  }
  let interpolatedChildren = node.children.map { child in
    applyInterpolatedValues(tree: child, interpolated: interpolated)
  }
  node.setChildrenPreservingDerivedState(interpolatedChildren)
  return node
}
```

- [ ] **Step 6: Update call-site helpers**

Any remaining references to `AnimatableProperty` or `AnimatableValue` elsewhere in `AnimationController.swift` get replaced. Search:

```bash
grep -n "AnimatableProperty\|AnimatableValue" Sources/SwiftTUI/AnimationController.swift
```

Expected output after the rewrite: only the deleted definitions (which are now gone) and zero remaining references. If any call sites show up, they need to be migrated to `AnimatableSlot` / `AnyAnimatable`.

### Task 3.3: Update `AnimationControllerTests.swift`

- [ ] **Step 1: Locate tests that reference the deleted types**

```bash
grep -n "AnimatableProperty\|AnimatableValue" Tests/SwiftTUITests/AnimationControllerTests.swift
```

Expected output: several references. Each needs a source-level migration to `AnimatableSlot` / `AnyAnimatable`.

- [ ] **Step 2: Migrate existing tests to the new types**

For each test that asserts on a specific `AnimatableProperty` case or `AnimatableValue` variant, rewrite the assertion to use the new slot-keyed snapshot model. Example migration:

```swift
// Before:
let snapshot = AnimatableSnapshot.extract(from: node)
#expect(snapshot.foregroundColor == Color.red)

// After:
let snapshot = AnimatableSnapshot.extract(from: node)
#expect(snapshot[.foregroundShapeStyle]?.unwrap(as: Color.self) == Color.red)
```

And:

```swift
// Before:
#expect(interpolated[.opacity] == .double(0.5))

// After:
#expect(interpolated[.opacity]?.unwrap(as: Double.self) == 0.5)
```

Walk through each test and apply these mechanical migrations. Do not change test semantics — every test that was green before must be green after.

- [ ] **Step 3: Add a parity test pinning old-model behavior**

Append a new test suite that runs the same opacity / color / padding / offset animation scenarios the old enum-dispatch model covered, using the new slot-keyed model, and asserts they produce identical interpolated results:

```swift
@Test(
  "Phase 3 parity: opacity animation produces the same interpolated "
    + "values as the pre-rewrite enum-dispatch model"
)
func phase3OpacityParity() throws {
  let controller = AnimationController()
  let animation = Animation.linear(duration: .milliseconds(200))
  controller.register(animation)

  let leafIdentity = Identity(components: [.named("parity-leaf")])
  var frame1Metadata = DrawMetadata()
  frame1Metadata.baseStyle.explicitOpacity = 1.0
  let frame1 = ResolvedNode(
    identity: leafIdentity,
    kind: .view("Leaf"),
    drawMetadata: frame1Metadata
  )
  let t0 = MonotonicInstant.now()
  controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

  var frame2Metadata = DrawMetadata()
  frame2Metadata.baseStyle.explicitOpacity = 0.0
  var frame2 = ResolvedNode(
    identity: leafIdentity,
    kind: .view("Leaf"),
    drawMetadata: frame2Metadata
  )
  var transaction = TransactionSnapshot()
  transaction.animationRequest = .animate(animation.animationBox)
  controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

  let halfway = t0.advanced(by: .milliseconds(100))
  _ = controller.applyInterpolations(to: &frame2, at: halfway)
  let opacity = frame2.drawMetadata.baseStyle.explicitOpacity
  #expect(opacity != nil)
  if let opacity {
    #expect(abs(opacity - 0.5) < 0.05)
  }
}
```

Repeat the parity test structure for color, padding, offset, frame, border color, and border blend phase. The test bodies are near-identical to the pre-Phase-3 tests — only the setup and assertion forms change.

- [ ] **Step 4: Build and run**

```bash
swift build
```

Expected: clean build. Any compile error means there's a call site referencing the deleted enums; search and migrate.

```bash
swift test
```

Expected: all 895+ tests pass, plus the new Phase 3 parity tests.

### Task 3.4: Commit Phase 3

- [ ] **Step 1: Stage and commit**

```bash
git add \
  Sources/SwiftTUI/AnimationController.swift \
  Sources/SwiftTUI/AnyAnimatable.swift \
  Tests/SwiftTUITests/AnimationControllerTests.swift

git commit -m "$(cat <<'EOF'
Rewrite AnimationController value-interpolation path around AnyAnimatable

Phase 3 of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Replaces the
enum-dispatch model (AnimatableProperty + AnimatableValue + 15
hardcoded slots with hand-written per-slot switches in diffAndEnqueue,
interpolate, and applyValue) with a SwiftUI-shaped AnyAnimatable +
AnimatableSlot model.

Deleted:
- AnimatableProperty enum (15 cases)
- AnimatableValue enum (.double / .integer / .color)
- AnimatableSnapshot's 15 optional fields
- diffAndEnqueue's 15 enqueueIfChanged calls
- interpolate's 3-arm type-switch
- applyValue's per-(property, value) pattern match for value cases

Added:
- AnyAnimatable type-erased wrapper with same-type equality, same-
  type interpolation via animatableData arithmetic, and unwrap(as:)
  for slot-specific writeback.
- AnimatableSlot enum identifying writeback destinations.
- AnimationKey now carries AnimatableSlot instead of
  AnimatableProperty.
- AnimatableSnapshot as [AnimatableSlot: AnyAnimatable] dictionary.
- AnimatableSnapshot.extract(from:) walks node metadata and wraps
  each slot's value as AnyAnimatable(Color/LinearGradient/
  RadialGradient/PatternFill/Double/Int/EdgeInsets/...).
- diffAndEnqueue now iterates the union of slot keys between
  previous and current snapshots.
- interpolate is a one-liner delegating to AnyAnimatable.interpolated.
- applyValue switches on AnimatableSlot and unwraps AnyAnimatable to
  the expected concrete type per slot.

EdgeInsets now animates as a single slot (.padding) instead of four
(.paddingTop/.paddingLeading/.paddingBottom/.paddingTrailing).  The
four-edge animation still works because EdgeInsets.animatableData
composes all four edges in a single AnimatablePair and arithmetic is
element-wise.  Parity tests pin per-edge behavior.

Foreground/background/border color slots become shape-style slots:
.foregroundShapeStyle etc. can now carry any animatable shape style
(Color, LinearGradient, RadialGradient, PatternFill).  This is the
Phase-3 enabler for Phase 5's smooth gradient rotation demo.

Pre-existing animations (opacity, color, padding, offset, position,
frame, border color, border blend phase) pinned by parity tests and
continue to produce identical interpolated values.
EOF
)"
```

---

## Phase 4 — Controller Polish

**Goal:** Unify the three parallel side-channel maps, fix the `AnimationTickResult.affectedIdentities` overload that was papered over in commit `9d6a87d`, and delete the `dominantActiveRequest()` re-injection hack from `RunLoop+Rendering.swift`. These cleanups are thematically aligned with Phase 3 — all three are about the controller's output being well-typed and the RunLoop not needing to paper over ambiguities.

**Files:**
- Modify: `Sources/SwiftTUI/AnimationController.swift`
- Modify: `Sources/SwiftTUI/RunLoop+Rendering.swift`
- Modify: `Tests/SwiftTUITests/AnimationControllerTests.swift` (new unit tests for the unified map; delete tests pinning the old separate-maps behavior)

### Task 4.1: Unify `activeAnimations`, `insertionOffsetAnimations`, `matchedGeometryAnimations`

- [ ] **Step 1: Define a unified `ActiveAnimation` discriminator**

In `Sources/SwiftTUI/AnimationController.swift`, replace the three parallel structs (`ActiveAnimation`, `InsertionOffsetAnimation`, `MatchedGeometryAnimation`) with a single struct that carries a kind discriminator:

```swift
package enum AnimationKind: Sendable {
  /// A property animation on a specific ``AnimatableSlot``.
  case property(from: AnyAnimatable, to: AnyAnimatable)
  /// A transition-driven insertion offset animation applied at
  /// placed level (cannot route through the slot path because it
  /// operates on intrinsic-layout leaves).
  case insertionOffset(from: (x: Int, y: Int))
  /// A matched-geometry translation animation between two placed
  /// bounds.
  case matchedGeometry(fromBounds: Rect)
}

package struct ActiveAnimation: Sendable {
  package var kind: AnimationKind
  package var animationBox: AnimationBox
  package var startTime: MonotonicInstant
  package var customState: AnimationState = .init()
  package var batchID: AnimationBatchID?
}
```

Update `AnimationKey` to carry a discriminator too:

```swift
package struct AnimationKey: Hashable, Sendable {
  package enum Scope: Hashable, Sendable {
    case property(AnimatableSlot)
    case insertionOffset
    case matchedGeometry
  }
  package var identity: Identity
  package var scope: Scope
}
```

- [ ] **Step 2: Replace the three parallel maps with one**

In `AnimationController`:

```swift
// Before:
private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]
private var insertionOffsetAnimations: [Identity: InsertionOffsetAnimation] = [:]
private var matchedGeometryAnimations: [Identity: MatchedGeometryAnimation] = [:]

// After:
private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]
```

- [ ] **Step 3: Migrate call sites**

Every place that reads or writes `insertionOffsetAnimations[identity]` or `matchedGeometryAnimations[identity]` now uses `activeAnimations[AnimationKey(identity: identity, scope: .insertionOffset)]` (or `.matchedGeometry`) instead. Migrate each call site. For each kind, the stored struct is now `ActiveAnimation` with `kind: .insertionOffset(from:)` or `.matchedGeometry(fromBounds:)`.

Key functions to migrate:
- `enqueueInsertionAnimation` — writes `.insertionOffset` entries.
- `processResolvedTree`'s matched-geometry detection — writes `.matchedGeometry` entries.
- `applyInterpolations` — reads all three, now reads one.
- `applyPlacedOverlays` — reads `.insertionOffset` and `.matchedGeometry` entries.
- `reset()` — clears the unified map.

- [ ] **Step 4: Update `applyInterpolations` tick loop**

The tick loop now walks a single map but branches on `animation.kind` to compute progress and interpolate:

```swift
for (key, animation) in activeAnimations {
  guard let anim = registeredAnimations[animation.animationBox] else {
    keysToRemove.append(key)
    if let batchID = animation.batchID { completedBatches.append(batchID) }
    continue
  }
  let elapsed = animation.startTime.duration(to: timestamp)
  var state = animation.customState
  let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
  activeAnimations[key]?.customState = state

  switch animation.kind {
  case .property(let from, let to):
    guard let progress = evaluated else {
      interpolated[key.identity, default: [:]][propertySlot(key: key)] = to
      keysToRemove.append(key)
      if let batchID = animation.batchID { completedBatches.append(batchID) }
      affectedIdentities.insert(key.identity)
      continue
    }
    let value = interpolate(from: from, to: to, progress: progress)
    interpolated[key.identity, default: [:]][propertySlot(key: key)] = value
    affectedIdentities.insert(key.identity)
    latestDeadline = timestamp.advanced(by: frameInterval)
    hasPendingWork = true

  case .insertionOffset:
    // Insertion offsets apply at placed level via
    // applyPlacedOverlays — tick bookkeeping here is just to keep
    // the run loop ticking.
    if evaluated == nil {
      keysToRemove.append(key)
      if let batchID = animation.batchID { completedBatches.append(batchID) }
    } else {
      hasPendingWork = true
      latestDeadline = timestamp.advanced(by: frameInterval)
      affectedIdentities.insert(key.identity)
    }

  case .matchedGeometry:
    // Same as insertionOffset — placed-level, tick-keeping only.
    if evaluated == nil {
      keysToRemove.append(key)
      if let batchID = animation.batchID { completedBatches.append(batchID) }
    } else {
      hasPendingWork = true
      latestDeadline = timestamp.advanced(by: frameInterval)
      affectedIdentities.insert(key.identity)
    }
  }
}

private func propertySlot(key: AnimationKey) -> AnimatableSlot {
  guard case .property(let slot) = key.scope else {
    preconditionFailure("propertySlot called on non-property key")
  }
  return slot
}
```

Verify that every `retainBatch(batchID)` call has a matching `releaseBatch(batchID)` on removal.

- [ ] **Step 5: Update `sample()` for the new `ActiveAnimation.kind` layout**

The existing `sample()` helper reads `animation.from` / `animation.to` directly — both fields are gone after Step 1. Rewrite `sample()` to extract the property-kind payload:

```swift
private func sample(
  _ animation: ActiveAnimation,
  at timestamp: MonotonicInstant
) -> AnyAnimatable? {
  // Only property animations have a sampleable animatable value.
  // Insertion-offset and matched-geometry animations are placed-
  // level and don't participate in the AnyAnimatable sample path.
  guard case .property(let from, let to) = animation.kind else {
    return nil
  }
  guard let anim = registeredAnimations[animation.animationBox] else {
    return nil
  }
  let elapsed = animation.startTime.duration(to: timestamp)
  var state = animation.customState
  guard let progress = anim.evaluate(elapsed: elapsed, state: &state) else {
    return to
  }
  return interpolate(from: from, to: to, progress: progress)
}
```

Every `sample(existing, at:)` caller (currently: `enqueueSlotChangeIfNeeded` for retargeting, and `applyInterpolations` if it still samples) already handles the `nil` return as "no current value, use the stored `from`" — so the new "non-property kind returns nil" behavior folds into the existing nil-handling.

- [ ] **Step 6: Update `AnimationControllerTests.swift` for the new `AnimationKey` shape**

Every test that constructs an `AnimationKey` directly uses the new `scope` field instead of `slot`. Example migration:

```swift
// Before (Phase 3 shape):
let key = AnimationKey(
  identity: leafIdentity,
  slot: .opacity
)

// After (Phase 4 shape):
let key = AnimationKey(
  identity: leafIdentity,
  scope: .property(.opacity)
)
```

And tests that directly wrote to `insertionOffsetAnimations[identity]` or `matchedGeometryAnimations[identity]` now write to `activeAnimations[AnimationKey(identity: identity, scope: .insertionOffset)]` (or `.matchedGeometry`). Walk through the test file:

```bash
grep -n "slot: \.\|insertionOffsetAnimations\|matchedGeometryAnimations" \
  Tests/SwiftTUITests/AnimationControllerTests.swift
```

For each match, apply the mechanical migration. Do not change test semantics.

- [ ] **Step 7: Run the suite and confirm parity**

```bash
swift test
```

Expected: all tests pass. Matched-geometry tests, insertion-transition tests, and property-animation tests all continue to work.

### Task 4.2: Clean up `AnimationTickResult.affectedIdentities` overload

- [ ] **Step 1: Split the tick-result signaling**

In `Sources/SwiftTUI/AnimationController.swift`, change `AnimationTickResult`:

```swift
package struct AnimationTickResult: Sendable {
  /// `true` when the tick produced pending work and the scheduler
  /// should wake up again before `nextDeadline`.
  package var hasPendingWork: Bool
  /// The absolute time by which the scheduler must wake for the
  /// next tick.
  package var nextDeadline: MonotonicInstant?
  /// Identities whose rendered cells need to be redrawn this frame.
  /// Used by the RunLoop viewport gate to decide whether a tick's
  /// work affects visible content.
  package var redrawIdentities: Set<Identity>

  package init(
    hasPendingWork: Bool = false,
    nextDeadline: MonotonicInstant? = nil,
    redrawIdentities: Set<Identity> = []
  ) {
    self.hasPendingWork = hasPendingWork
    self.nextDeadline = nextDeadline
    self.redrawIdentities = redrawIdentities
  }
}
```

Rename `hasActiveAnimations` → `hasPendingWork` (the old name overloaded two concepts). Rename `affectedIdentities` → `redrawIdentities` — now unambiguously "which identities need redraw" rather than "is anything pending."

- [ ] **Step 2: Update `applyInterpolations` to populate the new fields**

In the tick loop, `redrawIdentities` is populated only from property-animation and placed-level cases where a visible cell is affected. Stranded-batch drains don't populate `redrawIdentities` — they set `hasPendingWork = true` with `redrawIdentities.isEmpty` intact.

- [ ] **Step 3: Simplify `RunLoop+Rendering.swift` wake-up gate**

In `Sources/SwiftTUI/RunLoop+Rendering.swift` at the animation-tick wake-up block (`:171-198`), replace the hacky `isIdentityAgnosticTick` bypass (added by commit `9d6a87d`) with the clean semantics:

```swift
let animationTick = renderer.internalAnimationController.lastTickResult
if animationTick.hasPendingWork, let nextDeadline = animationTick.nextDeadline {
  // Schedule the next animation tick.  Any pending work
  // schedules a wake-up regardless of which identities need
  // redrawing — the viewport gate applied to redrawIdentities is
  // only used to decide whether the current frame's rendered
  // output needs to be diffed against the previous frame, not
  // whether a wake-up should be requested.
  let now = MonotonicInstant.now()
  let scheduledDeadline =
    if nextDeadline > now {
      nextDeadline
    } else {
      now.advanced(by: AnimationWakeTiming.minimumLeadTime)
    }
  scheduler.requestDeadline(scheduledDeadline)
}
```

The `isIdentityAgnosticTick` helper and the `isDisjoint(with:)` viewport check get deleted. `redrawIdentities` is consulted elsewhere in the render pipeline (incremental presentation diff) but not in the wake-up decision.

- [ ] **Step 4: Update tests referencing `affectedIdentities` / `hasActiveAnimations`**

```bash
grep -rn "affectedIdentities\|hasActiveAnimations" Tests/
```

For each match, rename to `redrawIdentities` / `hasPendingWork`. The semantics are identical for test cases that pin "this tick has N affected identities"; they become "this tick marks N identities for redraw".

- [ ] **Step 5: Run the suite**

```bash
swift test
```

Expected: all tests pass, including the four drain tests from commit `9d6a87d` (`completionClosureFires...` / `strandedBatchDrainSurfaces...`).

### Task 4.3: Delete `dominantActiveRequest()` re-injection

- [ ] **Step 1: Locate the hack**

```bash
grep -n "dominantActiveRequest" Sources/SwiftTUI/
```

Expected: one call site in `RunLoop+Rendering.swift:288-291` (the re-injection at `resolveContext(for:)` construction) and the implementation in `AnimationController`.

- [ ] **Step 2: Verify the retarget path is clean**

The reason `dominantActiveRequest()` exists is that older versions of the controller didn't retarget mid-flight animations when a new resolve frame arrived with no animation intent. The new `diffAndEnqueue` in Phase 3 handles this correctly: if an active animation exists for a slot and a new frame arrives with `.inherit`, the old animation continues until the next explicit change. Confirm by re-reading `enqueueSlotChangeIfNeeded` — the `.inherit` branch doesn't touch active animations.

- [ ] **Step 3: Delete the re-injection at the call site**

In `Sources/SwiftTUI/RunLoop+Rendering.swift`, at `:288-291`:

```swift
// Before:
if transactionSnapshot.animationRequest == .inherit,
  let active = renderer.internalAnimationController.dominantActiveRequest()
{
  transactionSnapshot.animationRequest = active
}

// After: delete the entire block.
```

- [ ] **Step 4: Delete the controller-side helper**

In `Sources/SwiftTUI/AnimationController.swift`, remove `dominantActiveRequest()` and any supporting state it used.

- [ ] **Step 5: Run the suite**

```bash
swift test
```

Expected: all tests pass. If any test fails, the retarget path has a gap — add a test that pins the pre-deletion behavior, fix the retarget path in `diffAndEnqueue`, and re-run.

### Task 4.4: Commit Phase 4

- [ ] **Step 1: Stage and commit**

```bash
git add \
  Sources/SwiftTUI/AnimationController.swift \
  Sources/SwiftTUI/RunLoop+Rendering.swift \
  Tests/SwiftTUITests/AnimationControllerTests.swift

git commit -m "$(cat <<'EOF'
Unify animation side-channels and clean up tick-result semantics

Phase 4 of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Three bundled
cleanups that are thematically aligned — all about the controller's
output being well-typed and the RunLoop not needing to paper over
ambiguities introduced by the old enum-dispatch model.

1. Side-channel map unification.  activeAnimations,
   insertionOffsetAnimations, and matchedGeometryAnimations become
   one map keyed on AnimationKey(identity, scope) where scope
   discriminates property / insertionOffset / matchedGeometry.
   ActiveAnimation gets a kind enum that carries the per-scope
   state.  One retain/release code path instead of three.

2. AnimationTickResult cleanup.  hasActiveAnimations was overloaded
   to mean both "is there pending work" and "is the run loop
   supposed to wake again"; affectedIdentities was overloaded to
   mean both "which identities need redraw" and "is there anything
   worth scheduling a tick for" — and the empty-set case bit us in
   commit 9d6a87d.  Split into hasPendingWork (wake-up signaling)
   and redrawIdentities (viewport diff input).  The
   isIdentityAgnosticTick bypass in RunLoop+Rendering.swift is
   deleted.

3. dominantActiveRequest deletion.  The inject-animation-into-tick-
   frames hack in RunLoop+Rendering.swift was a workaround for the
   controller not retargeting cleanly when a new frame arrived mid-
   animation.  The rewritten diffAndEnqueue in Phase 3 handles
   retargeting correctly (via sample(existing, at:) + effectiveFrom
   branch), so the hack is no longer needed.  Both call site and
   controller-side helper removed.

Drain tests from commit 9d6a87d still pass — the stranded-batch
safety net is orthogonal to these cleanups.
EOF
)"
```

---

## Phase 5 — Gallery Demo + Docs + Validation

**Goal:** Rework the `BordersAndShapesTab` `PhaseAnimator` demo to show smooth gradient rotation. Add a new "animated gradient" section demonstrating direct `withAnimation`-driven gradient interpolation. Update `docs/proposals/SHAPE_AND_BORDER_APIS.md` and `docs/proposals/ANIMATION_PLAN.md` to reflect the new architecture. Full regression sweep.

**Files:**
- Modify: `Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift`
- Modify: `docs/proposals/SHAPE_AND_BORDER_APIS.md`
- Modify: `docs/proposals/ANIMATION_PLAN.md` (add "superseded in part" marker pointing to this plan)
- Modify: `docs/PUBLIC_API_INVENTORY.md` (new public types: `UnitPoint`, `AnimatableArray`, `AnimatableSlot`, `AnyAnimatable`)
- Create: `Tests/SwiftTUITests/GradientAnimationIntegrationTests.swift`

### Task 5.1: Update the `PhaseAnimator` demo for smooth rotation

- [ ] **Step 1: Replace the in-progress demo code**

In `Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift`, replace the currently-unstaged `PhaseAnimator` + `PhaseBackgroundFill` enum demo with a cleaner version that uses `UnitPoint` directly:

```swift
HStack(spacing: 2) {
  Rectangle()
    .fill(PatternFill(glyph: "/", foreground: .yellow))
    .frame(width: 5, height: 5)
  PhaseAnimator(GradientRotationPhase.allCases) { phase in
    Rectangle()
      .fill(
        PatternFill(
          glyph: "/",
          foreground: .linearGradient(
            LinearGradient(
              colors: [.white, .red],
              startPoint: phase.startPoint,
              endPoint: phase.endPoint
            )
          )
        )
      )
      .frame(width: 5, height: 5)
  } animation: { _ in
    .linear(duration: .milliseconds(500))
  }
  Rectangle()
    .fill(PatternFill.dots)
    .frame(width: 5, height: 5)
}
```

And the phase enum:

```swift
private enum GradientRotationPhase: Hashable, CaseIterable {
  case topLeading
  case topTrailing
  case bottomTrailing
  case bottomLeading

  var startPoint: UnitPoint {
    switch self {
    case .topLeading: return .topLeading
    case .topTrailing: return .topTrailing
    case .bottomTrailing: return .bottomTrailing
    case .bottomLeading: return .bottomLeading
    }
  }

  var endPoint: UnitPoint {
    switch self {
    case .topLeading: return .bottomTrailing
    case .topTrailing: return .bottomLeading
    case .bottomTrailing: return .topLeading
    case .bottomLeading: return .topTrailing
    }
  }
}
```

- [ ] **Step 2: Build the gallery**

```bash
cd Examples/gallery && swift build && cd ../..
```

Expected: clean build.

- [ ] **Step 3: Visual verification**

```bash
cd Examples/gallery && swift run && cd ../..
```

Expected: navigate to the Borders and Shapes tab and confirm the gradient rotates smoothly over 500 ms instead of snapping between phases. The gradient should be visually continuous — a user watching the demo should not be able to identify discrete "phase" moments.

### Task 5.2: Add a direct `withAnimation` gradient demo section

- [ ] **Step 1: New demo section**

Append a new section to `BordersAndShapesTab.swift`:

```swift
private struct BordersAndShapesAnimatedGradientsSection: View {
  @State private var gradientDirection: GradientDirection = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("6. Direct withAnimation — tap to rotate gradient")
        .foregroundStyle(.muted)
      Button("rotate") {
        withAnimation(.easeInOut(duration: .milliseconds(800))) {
          gradientDirection = gradientDirection.next
        }
      }
      Rectangle()
        .fill(
          LinearGradient(
            colors: [.red, .yellow, .green, .blue],
            startPoint: gradientDirection.startPoint,
            endPoint: gradientDirection.endPoint
          )
        )
        .frame(width: 30, height: 5)
    }
  }
}

private enum GradientDirection: Hashable, CaseIterable {
  case horizontal
  case diagonal
  case vertical
  case antidiagonal

  var next: GradientDirection {
    switch self {
    case .horizontal: return .diagonal
    case .diagonal: return .vertical
    case .vertical: return .antidiagonal
    case .antidiagonal: return .horizontal
    }
  }

  var startPoint: UnitPoint {
    switch self {
    case .horizontal: return .leading
    case .diagonal: return .topLeading
    case .vertical: return .top
    case .antidiagonal: return .topTrailing
    }
  }

  var endPoint: UnitPoint {
    switch self {
    case .horizontal: return .trailing
    case .diagonal: return .bottomTrailing
    case .vertical: return .bottom
    case .antidiagonal: return .bottomLeading
    }
  }
}
```

And wire it into the tab's body alongside the existing sections.

- [ ] **Step 2: Build and visually verify**

```bash
cd Examples/gallery && swift build && swift run && cd ../..
```

Expected: tapping "rotate" smoothly animates the gradient direction over 800 ms.

### Task 5.3: Integration test for gradient animation

- [ ] **Step 1: Write a RunLoop-driven integration test**

Create `Tests/SwiftTUITests/GradientAnimationIntegrationTests.swift`:

```swift
import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite("Gradient animation end-to-end through RunLoop")
struct GradientAnimationIntegrationTests {

  @Test("LinearGradient direction animates through withAnimation")
  func linearGradientDirectionAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("gradient-leaf")])

    // Frame 1: gradient going top-leading to bottom-trailing.
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.foregroundStyle = .linearGradient(
      LinearGradient(
        colors: [.red, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Gradient"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    // Frame 2: gradient rotated 90° (top-trailing to bottom-leading).
    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .linearGradient(
      LinearGradient(
        colors: [.red, .blue],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
      )
    )
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Gradient"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    // Halfway through the animation.
    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    // Extract the interpolated gradient and assert the start point
    // is halfway between (0,0) and (1,0).
    guard
      let style = frame2.drawMetadata.baseStyle.foregroundStyle,
      case .linearGradient(let interpolated) = style
    else {
      Issue.record("expected interpolated linear gradient")
      return
    }
    #expect(abs(interpolated.startPoint.x - 0.5) < 0.05)
    #expect(abs(interpolated.startPoint.y - 0) < 0.05)
    #expect(abs(interpolated.endPoint.x - 0.5) < 0.05)
    #expect(abs(interpolated.endPoint.y - 1) < 0.05)
  }

  @Test("PatternFill gradient foreground animates end-to-end")
  func patternFillGradientForegroundAnimates() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    controller.register(animation)

    let leafIdentity = Identity(components: [.named("pattern-leaf")])

    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.foregroundStyle = .patternFill(
      PatternFill(
        glyph: "░",
        foreground: .linearGradient(
          LinearGradient(
            colors: [.red, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      )
    )
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Pattern"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.foregroundStyle = .patternFill(
      PatternFill(
        glyph: "░",
        foreground: .linearGradient(
          LinearGradient(
            colors: [.red, .blue],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
          )
        )
      )
    )
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Pattern"),
      drawMetadata: frame2Metadata
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)

    let halfway = t0.advanced(by: .milliseconds(100))
    _ = controller.applyInterpolations(to: &frame2, at: halfway)

    guard
      let style = frame2.drawMetadata.baseStyle.foregroundStyle,
      case .patternFill(let pattern) = style,
      case .linearGradient(let gradient) = pattern.foreground
    else {
      Issue.record("expected interpolated pattern fill with gradient foreground")
      return
    }
    #expect(abs(gradient.startPoint.x - 0.5) < 0.05)
  }
}
```

- [ ] **Step 2: Run the integration tests**

```bash
swift test --filter "GradientAnimationIntegration"
```

Expected: both tests pass.

### Task 5.4: Update docs

- [ ] **Step 1: Update `SHAPE_AND_BORDER_APIS.md`**

Locate references to `Alignment` on `LinearGradient` / `RadialGradient` and replace with `UnitPoint`. Add a subsection explaining the type change and why: gradients need continuous unit coordinates, alignment is a named-slot system. Cite this plan.

- [ ] **Step 2: Update `ANIMATION_PLAN.md`**

At the top of the file, add a "Supersedes" section that points to this plan for the value-interpolation half:

```markdown
## Superseding plan

The enum-dispatch value-interpolation model this document describes
(AnimatableProperty + AnimatableValue + AnimatableSnapshot fields) is
superseded by the SwiftUI-shaped Animatable protocol pipeline
documented in ANIMATABLE_PROTOCOL_MIGRATION.md, shipped in Phases 0-5
during April 2026.  The rest of this document — transaction/batch
bookkeeping, completion sinks, transition insertion/removal, matched
geometry, spring/bezier curves — remains accurate.
```

- [ ] **Step 3: Update `PUBLIC_API_INVENTORY.md`**

Add entries for the new public types: `UnitPoint`, `AnimatableArray`, and any newly-public conformances (`LinearGradient: Animatable`, `RadialGradient: Animatable`, `Color: Animatable`, etc.). Follow the existing inventory format.

### Task 5.5: Final validation sweep

- [ ] **Step 1: Clean build**

```bash
swift package clean
swift build
```

Expected: clean build, no warnings.

- [ ] **Step 2: Full test suite, three runs**

```bash
swift test && swift test && swift test
```

Expected: three consecutive clean runs of ~915+ tests. Any flake is pre-existing (see commit `9d6a87d` notes about the `HostedSceneSessionTests` / scroll-burst tests being timing-sensitive) and unrelated to this migration.

- [ ] **Step 3: Gallery visual verification**

```bash
cd Examples/gallery && swift run && cd ../..
```

Expected: every tab renders, the `BordersAndShapesTab` shows smooth gradient rotation, the new direct-withAnimation gradient demo responds to the rotate button.

### Task 5.6: Commit Phase 5

- [ ] **Step 1: Stage and commit**

```bash
git add \
  Examples/gallery/Sources/GalleryDemoViews/BordersAndShapesTab.swift \
  docs/proposals/SHAPE_AND_BORDER_APIS.md \
  docs/proposals/ANIMATION_PLAN.md \
  docs/PUBLIC_API_INVENTORY.md \
  Tests/SwiftTUITests/GradientAnimationIntegrationTests.swift

git commit -m "$(cat <<'EOF'
Gallery: smooth gradient rotation via PhaseAnimator

Phase 5 — and final — of the animatable-protocol migration
(docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).  Pays off the
previous four phases with a visible end-to-end demo.

- BordersAndShapesTab's PhaseAnimator demo now rotates its gradient
  foreground smoothly over 500 ms between the four orientations
  instead of snapping between discrete phases.  The PhaseAnimator
  still freezes-and-advances per commit 9d6a87d's drain fix, but
  the visual transitions are now continuous because the Phase 3
  rewrite teaches the controller to interpolate gradient interior
  via Animatable conformance.

- New "animated gradients" demo section shows direct withAnimation-
  driven gradient rotation on tap, exercising Phase 2's
  LinearGradient: Animatable conformance through a real run loop.

- New GradientAnimationIntegrationTests pin the end-to-end
  controller behavior: LinearGradient direction interpolates
  correctly at halfway, PatternFill with gradient foreground
  interpolates correctly at halfway.

- SHAPE_AND_BORDER_APIS.md updated for the Alignment → UnitPoint
  change on gradients.  ANIMATION_PLAN.md marked as superseded-in-
  part by this migration.  PUBLIC_API_INVENTORY.md updated with new
  public types (UnitPoint, AnimatableArray, etc.).

Full test suite: 915+ tests, three consecutive clean runs.  Gallery
builds clean; visual verification passed.
EOF
)"
```

---

## Risks and Mitigations

### R1: OKLab round-trip drift

**Risk:** `Color.animatableData` getter → setter is a lossy conversion (sRGB → OKLab → sRGB with gamut compression). Tight animations on colors near the sRGB gamut boundary may accumulate drift across many frames.

**Likelihood:** Low.

**Mitigation:** The round-trip is bounded and small — existing `Color.interpolated(to:progress:method:.perceptual)` users are exposed to the same drift, and no user-visible bug has been reported against that path. The Phase 0 `colorAnimatableRoundTrip` test pins the drift to < 0.001 relative RGB error. If a regression appears, the fix is to widen the test tolerance or switch to linear-RGB space for near-gamut colors — both are narrowly scoped.

### R2: `AnimatableArray` count mismatch snapping is surprising

**Risk:** A user adds a stop to a gradient inside a `withAnimation` block, expects smooth animation, and gets a snap instead. The SwiftUI semantics match but aren't obviously discoverable.

**Likelihood:** Medium.

**Mitigation:** Documented in the `Gradient: Animatable` conformance's doc comment. A future enhancement could bridge count mismatches by padding the shorter array with "hidden" stops at the endpoints' colors, but that's out of scope for this plan — it's a product decision, not a correctness one.

### R3: Phase 3 rewrite breaks a niche existing animation

**Risk:** The 15-case enum-dispatch model may have subtle behavior for a slot that the parity tests don't catch, and the new slot-keyed model may produce slightly different interpolated values under some edge case.

**Likelihood:** Low-Medium.

**Mitigation:** Phase 3 adds a dedicated parity test suite that exercises every pre-existing slot (opacity, foreground color, background color, border color, border blend phase, padding — all four edges, offset, position, frame width/height) with the same `from`/`to` values the pre-rewrite tests used, and pins the interpolated result at the halfway point. Any divergence is a test failure and must be resolved before the phase lands.

### R4: Side-channel unification breaks matched-geometry timing

**Risk:** Matched-geometry animations rely on their own retain/release path, and folding them into the unified `activeAnimations` map may change the timing of `releaseBatch` in subtle ways that cause completion closures to fire early or late.

**Likelihood:** Medium.

**Mitigation:** Phase 4 preserves the retain/release semantics exactly — `ActiveAnimation` now carries the `batchID`, `retainBatch` is called at enqueue, `releaseBatch` is called on removal, the completion-closure mapping in `completionClosures[batchID]` is unchanged. Existing matched-geometry tests (`AnimationControllerPropertyTests.matchedGeometryTriggersTranslationAnimation` and friends) pin the behavior and must stay green.

### R5: `dominantActiveRequest()` deletion exposes a retarget gap

**Risk:** The re-injection hack in `RunLoop+Rendering.swift` existed for a reason. Deleting it may expose a case where a mid-flight animation doesn't retarget when a new resolve frame arrives, causing a visible snap in the middle of an animation.

**Likelihood:** Medium.

**Mitigation:** Phase 4 Task 4.3 Step 2 explicitly verifies the retarget path in `enqueueSlotChangeIfNeeded` before deleting the hack. If a test fails after deletion, re-read the retarget path and add the missing branch. If the retarget path turns out to be fundamentally incompatible with `.inherit` semantics, keep the hack and document why — but this is expected to be an easy cleanup.

### R6: Compound `AnimatableData` types become unwieldy

**Risk:** `LinearGradient.AnimatableData` is already `AnimatablePair<AnimatableArray<AnimatablePair<AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>, Double>>, AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>>`. Reading compiler errors in this type becomes painful.

**Likelihood:** High (it's already true).

**Mitigation:** Use typealiases in each `Animatable` extension to name intermediate types. Example: `public typealias GradientAnimatableData = AnimatableArray<Gradient.Stop.AnimatableData>`. This doesn't change semantics but makes diagnostics readable. Apply typealiases to every compound conformance in Phase 2.

### R7: `@unchecked Sendable` on `AnyAnimatable`

**Risk:** `AnyAnimatable` uses `@unchecked Sendable` because the `any _AnyAnimatableBox` protocol existential doesn't synthesize `Sendable` conformance automatically. If the wrapped value's `Animatable` conformance is itself not truly sendable, we'd have a data race.

**Likelihood:** Low.

**Mitigation:** The `init<T: Animatable & Equatable & Sendable>` constraint requires `Sendable` at wrap time. The `@unchecked` marker is only there to paper over the Swift compiler's inability to infer `Sendable` through the existential — the actual safety is enforced at the `init` boundary. Document this in the `AnyAnimatable` doc comment.

---

## Rollback Strategy

Each phase commits independently, so rollback is `git revert <commit-hash>` for that phase's commit. Because each phase leaves the build and tests green, reverting any single phase leaves the remaining phases (those that landed before the reverted one) in a working state.

**Phase 0 rollback:** Reverts primitives; subsequent phases can't build. Only useful if a foundational problem emerges (e.g., the OKLab round-trip test fails in a way that can't be fixed by widening tolerance).

**Phase 1 rollback:** Reverts `Alignment` → `UnitPoint` on gradients. Gallery demo needs follow-up revert. Useful if `UnitPoint` turns out to have ergonomic problems and we want to retreat to an `Alignment`-based model.

**Phase 2 rollback:** Reverts compound conformances. Controller still uses enum-dispatch from Phase 3's original baseline if Phase 3 hasn't shipped, or is left in an inconsistent half-migrated state if Phase 3 has shipped. In the latter case, roll back Phases 2+3 together.

**Phase 3 rollback:** Reverts the controller rewrite. Phase 2 conformances become dead code (still exist, still compile, just not consumed). Gallery demo no longer animates smoothly but doesn't break.

**Phase 4 rollback:** Reverts side-channel unification. Controller retains clean value-interpolation from Phase 3.

**Phase 5 rollback:** Reverts gallery demo + doc updates. Controller stays rewritten; demo reverts to step-function behavior.

**Multi-phase rollback:** `git revert <oldest-hash>..<newest-hash>` in reverse order, or `git reset --hard <before-phase-0-hash>` in extremis.

---

## Execution Handoff

**Plan complete and saved to `docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per phase, review between phases, fast iteration. Each phase is one agent invocation with a narrowly scoped prompt pointing at its Task section. Review between phases catches problems early.

2. **Inline Execution** — Execute phases in this session using the `superpowers:executing-plans` skill. Batch execution with checkpoints for review at each phase boundary. Context gets used up faster but there's no handoff overhead.

Which approach would you like?
