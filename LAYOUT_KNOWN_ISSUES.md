# Layout Engine Known Issues

Audit of the layout algorithm in `Sources/Core/LayoutEngine*.swift`, `Sources/Core/TextLayout.swift`, and `Sources/View/Layout.swift`.

## Architecture Overview

The layout system follows a SwiftUI-inspired three-phase pipeline: Resolve, Measure, Place. It operates in integer terminal-cell coordinates.

### Core Files

| File | Purpose |
|------|---------|
| `LayoutEngine.swift` | Central measure/place entry points, measurement cache, flexible frame resolution |
| `LayoutEngine+Stack.swift` | Stack child measurement, space distribution, compression |
| `LayoutEngine+Placement.swift` | Child placement dispatch for all layout behaviors |
| `LayoutEngine+Alignment.swift` | Alignment guide resolution, ViewDimensions propagation |
| `LayoutEngine+Utility.swift` | Clamping, fixedSize, ViewThatFits selection |
| `LayoutTypes.swift` | LayoutBehavior enum, LayoutMetadata, MeasuredNode, CustomLayoutProxy |
| `GeometryTypes.swift` | Point/Size/Rect/ProposedSize/Alignment/ViewDimensions |
| `TextLayout.swift` | Word-boundary wrapping, truncation, cell-width calculation |
| `View/Layout.swift` | Custom Layout protocol, HStackLayout/VStackLayout/ZStackLayout, AnyLayout |

---

## Bug: Word-Wrap Continuation Markers Count Clusters, Not Cell Widths

**Location:** `TextLayout.swift:574`

`wrapWordLikeClusters` uses `remaining.prefix(firstLineContentWidth)` which counts clusters, not cell widths. Since most terminal characters are 1 cell wide this usually works, but wide characters (CJK, emoji = 2 cells) can overflow a line because the prefix takes N clusters regardless of their individual widths.

Example: a CJK word that is 5 wide-characters long (10 cells) being wrapped into a width-8 column: `firstLineContentWidth = 7`, takes 7 clusters = 14 cells, overflowing the line.

Fix: accumulate clusters by cell width rather than count.

---

## Design Issue: Custom Layout Cache is Recreated Per Call

**Location:** `View/Layout.swift:578-579`

In `LayoutProxyBox`, both `measureContainer` and `placeSubviews` call:

```swift
var cache = box.makeCache(subviews: subviews)
box.updateCache(&cache, subviews: subviews)
```

The cache is created fresh each time rather than being retained across calls. This defeats the purpose of the `Cache` associated type for expensive computations. Custom layouts that rely on cached precomputation (e.g., a grid computing column widths once) will recompute every time.

Fix: store the cache on the `CustomLayoutHandle` or pass it through the measurement pipeline.

---

## Critical Gap: Minimal Test Coverage

**Location:** `Tests/CoreTests/LayoutEngineTests.swift`

Only 4 tests for a ~1500-line layout engine:

- Leaf measurement with intrinsic size
- Proposal clamping
- Placement at origin
- Cache hit

Missing coverage for:

- Stack space distribution (spacers, compression, priorities)
- Flexible frame min/max/ideal resolution
- Overlay sizing with alignment guides
- ViewThatFits selection
- Padding inset propagation
- Custom layout protocol integration
- Text wrapping edge cases (CJK, emoji)
- Negative/zero proposals
- Deep tree performance

---

## Minor: Integer Remainder Distribution is Left-Biased

**Location:** `LayoutEngine+Stack.swift:144-149`

When distributing extra space to spacers or compressing children, remainder pixels go to the first N items in document order. In an HStack with 3 spacers and 2px of extra space, spacers 0 and 1 each get an extra pixel, but spacer 2 does not. Same left-bias applies during compression remainder distribution (lines 197-200).

SwiftUI has the same behavior. Could be improved by distributing remainder pixels more evenly (e.g., round-robin from alternating ends), but this is cosmetic in integer cell coordinates.

---

## Minor: Recursive `supportsRetainedLayoutReuse` Walk

**Location:** `LayoutEngine.swift:763-772`

```swift
private func supportsRetainedLayoutReuse(for resolved: ResolvedNode) -> Bool {
    switch resolved.layoutBehavior {
    case .viewThatFits, .custom:
        return false
    default:
        return resolved.children.allSatisfy { supportsRetainedLayoutReuse(for: $0) }
    }
}
```

This recursively walks the entire subtree to check if any descendant is `.viewThatFits` or `.custom`. On deep trees this is O(N) per node.

Fix: cache this flag on the `ResolvedNode` during the resolve phase.

---

## Cosmetic: Missing VS16 Handling in Cell Width Calculation

**Location:** `TextLayout.swift:805-860`

The `cellWidth` function handles emoji (2 cells), CJK ranges (2 cells), zero-width marks, and standard characters (1 cell). Missing: Variation Selector 16 (U+FE0F) which can force emoji presentation on otherwise text-presentation characters, changing their width from 1 to 2 cells.

---

## Notes on Correct-but-Noteworthy Behavior

### Stack Children are Measured Twice

`LayoutEngine+Stack.swift:8-67` -- every stack child is measured once with `.unspecified` main axis (ideal pass), then again with the allocated size (final pass). This is the correct SwiftUI algorithm. The `MeasurementCache` partially mitigates the cost but cache hits between passes are unlikely since the proposals differ.

### Container Types are Never Clamped by Parent Proposal

`LayoutEngine+Utility.swift:42-67` -- stacks, overlays, padding, decorations, ViewThatFits, and custom layouts all return `.unspecified` as their clamping proposal, meaning their measured size is never clamped by the parent's proposal. Parents propose, children respond, but children can exceed proposals. Clipping happens at the draw/raster phase.

### ViewThatFits Measures Children Three Times

`LayoutEngine+Utility.swift:105-128` and `LayoutEngine.swift:490-501` -- children are measured in `measureChildren`, then `selectedChildIndex` measures them again with a relaxed proposal for fit-testing. Could be optimized by combining the selection and measurement passes.

### FlexibleFrame `.infinity` Proposal Resolution

`LayoutEngine.swift:563-587` -- when the parent proposes `.infinity`, the flexible frame resolves to max if available, then ideal, then min, then 0. This matches expected behavior since `maxVal` is checked first.

---

## Summary Table

| Severity | Finding | Location |
|----------|---------|----------|
| Bug | Word-wrap continuation markers count clusters, not cell widths | `TextLayout.swift:574` |
| Design Issue | Custom Layout cache recreated per call | `View/Layout.swift:578-579` |
| Critical Gap | Only 4 layout tests for ~1500-line engine | `LayoutEngineTests.swift` |
| Minor | Integer remainder distribution is left-biased | `LayoutEngine+Stack.swift:144-149` |
| Minor | Recursive retained-layout check is O(N) per node | `LayoutEngine.swift:763-772` |
| Cosmetic | Missing VS16 handling in cell width calculation | `TextLayout.swift:805-860` |
