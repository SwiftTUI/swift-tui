# Layout Engine Fix Plan

Fixes for all issues identified in `LAYOUT_KNOWN_ISSUES.md`. Code fixes first, tests last.

---

## Fix 1: Word-Wrap Overflow with Wide Characters (Bug)

**File:** `Sources/Core/TextLayout.swift`

**Problem:** `wrapWordLikeClusters` uses `remaining.prefix(N)` to take N clusters by count, not by cell width. CJK and emoji characters occupy 2 cells each, so a prefix of N clusters can produce up to 2N cells of content, overflowing the target line width.

**Approach:**

1. Add a `prefixByCellWidth` helper that accumulates clusters until a cell-width budget is exhausted:

    ```swift
    private func prefixByCellWidth(
        _ clusters: ArraySlice<TextCluster>,
        maxWidth: Int
    ) -> [TextCluster] {
        var result: [TextCluster] = []
        var usedWidth = 0
        for cluster in clusters {
            guard usedWidth + cluster.cellWidth <= maxWidth else { break }
            result.append(cluster)
            usedWidth += cluster.cellWidth
        }
        return result
    }
    ```

2. Add a `sliceCellWidth` helper for measuring remaining content:

    ```swift
    private func sliceCellWidth(_ clusters: ArraySlice<TextCluster>) -> Int {
        clusters.reduce(0) { $0 + $1.cellWidth }
    }
    ```

3. Replace three call sites in `wrapWordLikeClusters`:

    | Line | Before | After |
    |------|--------|-------|
    | ~574 | `Array(remaining.prefix(firstLineContentWidth))` | `prefixByCellWidth(remaining, maxWidth: firstLineContentWidth)` |
    | ~586 | `remaining.count + continuationMarker.cellWidth <= width` | `sliceCellWidth(remaining) + continuationMarker.cellWidth <= width` |
    | ~594 | `Array(remaining.prefix(middleLineContentWidth))` | `prefixByCellWidth(remaining, maxWidth: middleLineContentWidth)` |

---

## Fix 2: Custom Layout Cache Recreated Per Call (Design Issue)

**File:** `Sources/View/Layout.swift`

**Problem:** `LayoutProxyBox.measureContainer` and `LayoutProxyBox.placeSubviews` both call `makeCache` + `updateCache` from scratch. The `Layout.Cache` associated type exists to let layouts precompute expensive data once, but that contract is broken because the cache is discarded between calls.

**Approach:**

Store the cache as a mutable property on `LayoutProxyBox`. Since `LayoutProxyBox` is stored inside `CustomLayoutHandle` (which persists in the resolved tree across frames), the cache naturally persists. The `updateCache` call before each use handles staleness -- and the default `updateCache` implementation calls `makeCache`, so layouts that don't implement custom update logic still work correctly.

1. Add `private var cachedState: Any?` to `LayoutProxyBox`.

2. Add an `ensureCache` method:

    ```swift
    private func ensureCache(subviews: [LayoutSubview]) -> Any {
        if var existing = cachedState {
            box.updateCache(&existing, subviews: subviews)
            cachedState = existing
            return existing
        }
        let fresh = box.makeCache(subviews: subviews)
        cachedState = fresh
        return fresh
    }
    ```

3. Update `measureContainer` and `placeSubviews` to use `ensureCache` instead of `makeCache` + `updateCache`, and write the cache back after each use:

    ```swift
    // In measureContainer:
    var cache = ensureCache(subviews: subviews)
    let result = box.sizeThatFits(...)
    cachedState = cache
    return result

    // In placeSubviews:
    var cache = ensureCache(subviews: subviews)
    box.placeSubviews(...)
    cachedState = cache
    ```

---

## Fix 3: Minimal Test Coverage (Critical Gap)

**File:** `Tests/CoreTests/LayoutEngineTests.swift`

**Problem:** Only 4 tests cover a ~1500-line layout engine. Critical paths are untested.

**Approach:** Add tests for each major layout behavior. Each test constructs a `ResolvedNode` tree directly and verifies `measuredSize` and placement `bounds` through `LayoutEngine`.

| Test | What it covers |
|------|----------------|
| Stack with spacers | Extra space distributed evenly across spacers |
| Stack compression with priorities | Low-priority children compressed first |
| Flexible frame min/max/ideal | Correct resolution under `.unspecified`, `.finite`, `.infinity` |
| Overlay sizing | Container sizes to alignment-projected union of children |
| ViewThatFits selection | First child that fits the proposal is chosen |
| Padding inset propagation | Child proposal reduced by insets, child placed at inset origin |
| Wide-char word wrapping | CJK clusters wrapped by cell width, not cluster count (validates Fix 1) |
| Zero and negative proposals | No crashes, sizes clamped to zero |

---

## Fix 4: Integer Remainder Distribution Left-Bias (Minor)

**File:** `Sources/Core/LayoutEngine+Stack.swift`

**Problem:** When distributing remainder pixels (from integer division), the extra pixels always go to the first N items in document order, creating a visible left/top bias.

**Approach:** Use stride-based distribution to spread remainder pixels evenly across the index range.

1. In `distributeExtraSpaceToSpacers` (~line 141):

    ```swift
    let baseShare = extraSpace / spacerIndices.count
    let remainder = extraSpace % spacerIndices.count

    for index in spacerIndices {
        allocatedMainSizes[index] += baseShare
    }
    for i in 0..<remainder {
        let offset = i * spacerIndices.count / remainder
        allocatedMainSizes[spacerIndices[offset]] += 1
    }
    ```

2. In `compressStackChildren` (~line 196):

    ```swift
    var remainder = remainingOverflow - distributed
    if remainder > 0 {
        let eligible = indices.indices.filter { reductions[$0] < compressibles[$0] }
        for i in 0..<min(remainder, eligible.count) {
            let offset = i * eligible.count / min(remainder, eligible.count)
            reductions[eligible[offset]] += 1
        }
    }
    ```

---

## Fix 5: Recursive `supportsRetainedLayoutReuse` O(N) Walk (Minor)

**Files:** `Sources/Core/RenderTreeAndSemanticsTypes.swift`, `Sources/Core/LayoutEngine.swift`

**Problem:** `supportsRetainedLayoutReuse` recursively walks the entire subtree on every call. For deep trees this is O(N) per node checked.

**Approach:** Precompute the flag once during `ResolvedNode` construction. Since children are constructed bottom-up, each node's flag is O(1) to compute from its children's cached flags.

1. Add to `ResolvedNode` (RenderTreeAndSemanticsTypes.swift):

    ```swift
    public var supportsRetainedReuse: Bool
    ```

    Compute in `init` after existing assignments:

    ```swift
    self.supportsRetainedReuse = Self.computeSupportsRetainedReuse(
        layoutBehavior: layoutBehavior,
        children: children
    )

    private static func computeSupportsRetainedReuse(
        layoutBehavior: LayoutBehavior,
        children: [ResolvedNode]
    ) -> Bool {
        switch layoutBehavior {
        case .viewThatFits, .custom:
            return false
        default:
            return children.allSatisfy(\.supportsRetainedReuse)
        }
    }
    ```

    Note: `ResolvedNode` uses synthesized `Equatable`. Adding a derived `Bool` is safe -- two nodes equal on existing fields will always produce the same `supportsRetainedReuse` value.

2. Simplify `LayoutEngine.swift` (~line 763):

    ```swift
    private func supportsRetainedLayoutReuse(for resolved: ResolvedNode) -> Bool {
        resolved.supportsRetainedReuse
    }
    ```

---

## Fix 6: Missing VS16 Handling in Cell Width (Cosmetic)

**File:** `Sources/Core/TextLayout.swift`

**Problem:** Variation Selector 16 (U+FE0F) forces emoji presentation on characters that would otherwise render as text (1 cell). The current `cellWidth` function doesn't account for this.

**Approach:** After the existing emoji-presentation and emoji-cluster checks in `cellWidth(of:)`, add:

```swift
let containsVS16 = scalars.contains { $0.value == 0xFE0F }
if containsVS16 && scalars.contains(where: { $0.properties.isEmoji }) {
    return 2
}
```

---

## Execution Order

```
Phase 1 (parallel):
  Agent A: Fix 1 + Fix 6  (Sources/Core/TextLayout.swift)
  Agent B: Fix 4           (Sources/Core/LayoutEngine+Stack.swift)
  Agent C: Fix 5           (Sources/Core/RenderTreeAndSemanticsTypes.swift + LayoutEngine.swift)

Phase 2 (sequential):
  Fix 2                    (Sources/View/Layout.swift)

Phase 3 (sequential):
  Fix 3                    (Tests/CoreTests/LayoutEngineTests.swift)
```

## Verification

1. `swift build` after each phase to catch compile errors early.
2. `swift test` after all fixes to run existing and new tests.
3. New test for wide-char wrapping validates Fix 1 end-to-end.
