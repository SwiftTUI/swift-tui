# Architecture Refactor Plan

**Date:** 2026-03-26
**Ref:** [ARCHITECTURE_AUDIT.md](./ARCHITECTURE_AUDIT.md)
**Scope:** All HIGH and MEDIUM priority issues

## Phase 1: Type Safety (No Structural Changes)

### 1.1 Replace Legacy Semantic Tokens With Closed Types [H3]

**Problem:** The old semantic/token surface relied on open-ended strings for roles, routes, and compatibility mappers. Typos silently broke routing and styling, and the action-route layer duplicated the local action registry.

**Approach:**
1. Define closed semantic enums and structured routing in `Core/SemanticRoleTypes.swift`:
   ```swift
   public enum ScrollRole: Hashable, Sendable { ... }
   public enum SectionRole: Hashable, Sendable { ... }
   public enum PresentationRole: Hashable, Sendable { ... }
   public enum RouteKind: Hashable, Sendable { case primary }
   public struct RouteID: Hashable, Sendable {
     public var identity: Identity
     public var kind: RouteKind
   }
   ```
2. Remove the string-based styling compatibility entry points and token mappers
3. Replace pointer hit-policy tokens with boolean participation flags on `SemanticMetadata`
4. Remove the action-route pipeline entirely so activation flows only through typed identities and local registries

**Files touched:** ~14 files across Core and View

### 1.2 Audit @unchecked Sendable [M2]

**Problem:** 24 `@unchecked Sendable` instances. Some are justified (closure storage), others could use `Mutex`.

**Approach:**
1. Categorize each instance:
   - **Can fix:** Replace with `Mutex` or `nonisolated(unsafe)` where appropriate
   - **Justified:** Add `// SAFETY:` comment documenting thread-access invariant
2. Priority targets:
   - `MeasurementCache` — add `Mutex` or make non-`Sendable`
   - `DynamicStateStore` — evaluate actor conversion
   - `LocalActionRegistry` and siblings — document single-thread resolve-phase invariant
3. Do NOT break existing API signatures

**Files touched:** ~20 files across Core, View, TerminalUI

## Phase 2: File Decomposition

### 2.1 Decompose LayoutEngine.swift [H1]

**Problem:** 1,922 lines, 60+ private methods covering all layout behaviors.

**Approach:** Extract into files by functional group. Keep `LayoutEngine` as the public entry point that dispatches to extracted helpers.

**New files in `Sources/Core/`:**

| New File | Methods Extracted | Approx Lines |
|----------|-------------------|-------------|
| `LayoutEngine+Stack.swift` | `measureStackChildren`, `resolvedStackSpacings`, `preferredSpacingDistance`, `stackCrossMetrics`, `distributeExtraSpaceToSpacers`, `compressStackChildren`, `minimumMainSize`, `stackProposal`, `mainDimension`, `crossDimension`, `settingMainDimension`, `isSpacer`, `isFixedSize`, `minimumMainDimension`, `derivedMinimumMainSize` | ~500 |
| `LayoutEngine+Placement.swift` | `childPlacements` (all cases), `placedNode`, `combinedContentBounds`, `union`, `resolvedContentBounds`, `semanticRole` | ~350 |
| `LayoutEngine+Alignment.swift` | `alignedOrigin` (all overloads), `simpleAlignedOrigin`, `simpleAlignedCoordinate`, `overlayAlignmentMetrics`, `viewDimensions`, `propagatedViewDimensions` | ~300 |
| `LayoutEngine+List.swift` | `measuredListSize`, `measuredListIdealSize`, `resolvedListDimension`, `resolvedExpandingListDimension`, `listSectionSeparatorIsVisible`, `listRowSeparatorIsVisible` | ~200 |
| `LayoutEngine+Table.swift` | `measuredTableSize`, `measuredTableIdealSize`, `showsTableRowSeparator` | ~100 |
| `LayoutEngine+Utility.swift` | `clampedSize`, `clamp`, `finiteDimension`, `proposalApplyingFixedSizeMetadata`, `clampingProposal`, `proposalByRelaxingAxes`, `fits`, `selectedChildIndex`, `containerAllocationSnapshot` | ~250 |

**Remaining in `LayoutEngine.swift`:** `MeasurementCache`, `LayoutEngine` struct, `measure()`, `place()` public API, `measureChildren`, `measuredSize`, `overlaySize`, `measuredTextSize`, `measuredRuleSize`, `measuredShapeSize`, retained-layout helpers (~450 lines).

**Strategy:** Use Swift extensions (`extension LayoutEngine { ... }`) in each new file. All extracted methods stay `private` or `package` — no public API changes.

### 2.2 Decompose RunLoop.swift [H2]

**Problem:** 1,136 lines mixing event dispatch, pointer handling, focus, rendering, and lifecycle.

**Approach:** Extract logical groups into separate types/files.

**New files in `Sources/TerminalUI/`:**

| New File | What It Contains | Approx Lines |
|----------|-----------------|-------------|
| `EventDispatcher.swift` | `handle(_:)`, `handleKeyEvent(_:)`, `signalDisposition(for:)`, `localKeyEvent(for:)` — top-level event routing | ~120 |
| `PointerEventHandler.swift` | `handleMouseEvent`, `handleMouseDown`, `handleMouseUp`, `handleMouseMove`, `handleMouseDrag`, `handleMouseScroll`, `hitTarget`, `interactionRegion`, `focusIdentity`, `scrollContext`, `dispatchPointerEvent`, `fallbackPrimaryRouteIDs`, `isActivationIdentity`, `shouldCapturePointer`, `updateArmedPointerState`, `setPressedIdentity` | ~350 |
| `EventPump.swift` | `EventPump`, `EventPumpBuffer`, `EventPumpCompletion`, `makeEventPump`, `drainPendingEvents`, `isCoalesciblePointerRuntimeEvent` | ~180 |
| `RunLoopRendering.swift` | `renderPendingFrames`, `resolveContext`, `proposal`, `applyDesiredFocusRequest` | ~120 |

**Remaining in `RunLoop.swift`:** Type definition, stored properties, `init`, `run()`, `attachDynamicStateStore` (~120 lines).

**Strategy:** Use extensions on `RunLoop<State>` in each file. Move nested types (`RuntimeEvent`, `HitTarget`) to appropriate files. Internal access only — no public API changes.

## Phase 3: Structural Improvements

### 3.1 Split ResolvedNode Metadata [M1]

**Problem:** `ResolvedNode` has 12 fields. Every pipeline phase receives all fields. `MeasurementCache` compares all fields even for measurement.

**Approach:**
1. Create focused metadata structs (keep existing types, just group):
   ```swift
   public struct NodeLayoutInfo: Equatable, Sendable {
     public var layoutBehavior: LayoutBehavior
     public var layoutMetadata: LayoutMetadata
     public var intrinsicSize: Size?
   }

   public struct NodeDrawInfo: Equatable, Sendable {
     public var drawMetadata: DrawMetadata
     public var drawPayload: DrawPayload
   }

   public struct NodeSemanticInfo: Equatable, Sendable {
     public var semanticMetadata: SemanticMetadata
   }

   public struct NodeLifecycleInfo: Equatable, Sendable {
     public var lifecycleMetadata: LifecycleMetadata
   }
   ```
2. Add these as properties on `ResolvedNode`, preserving the flat accessors as computed properties for backward compatibility
3. Update `MeasurementInput` to only compare `NodeLayoutInfo` + environment (the fields that actually affect measurement)

**Files touched:** `RenderTreeAndSemanticsTypes.swift`, `LayoutEngine.swift`, `DrawExtractor.swift`, `Semantics.swift`, `CommitPlanner.swift`

### 3.2 Add CoreTests and ViewTests Targets [M3]

**Problem:** All tests in `TerminalUITests`. Can't test Core or View independently.

**Approach:**
1. Add to `Package.swift`:
   ```swift
   .testTarget(name: "CoreTests", dependencies: ["Core"]),
   .testTarget(name: "ViewTests", dependencies: ["Core", "View"]),
   ```
2. Create `Tests/CoreTests/` and `Tests/ViewTests/` directories
3. Move applicable tests from `TerminalUITests` that only depend on Core or View
4. Add initial test files for untested core components (LayoutEngine, Rasterizer, FocusTracker)

### 3.3 Implement Incremental Resolve [M4]

**Problem:** Resolve phase walks entire View tree every frame, O(n) even for single-leaf changes.

**Approach:**
1. Add `RetainedResolveCache` to `Core/`:
   ```swift
   package final class RetainedResolveCache {
     private var subtrees: [Identity: CachedSubtree]

     struct CachedSubtree {
       let resolved: ResolvedNode
       let environmentSnapshot: EnvironmentSnapshot
     }

     func lookup(
       identity: Identity,
       currentEnvironment: EnvironmentSnapshot,
       invalidatedIdentities: Set<Identity>
     ) -> ResolvedNode?

     func store(_ node: ResolvedNode)
   }
   ```
2. Integrate into `Resolver` — before resolving a subtree, check cache
3. Cache hit conditions: identity NOT in `invalidatedIdentities` AND environment unchanged
4. Wire through `ResolveContext` so the resolver has access

**Files touched:** New `RetainedResolveCache.swift`, `Resolver.swift` or equivalent, `ResolveContext`

## Execution Order

```
Phase 1 (independent, no dependencies):
  1.1 String-typed roles  ──┐
  1.2 @unchecked Sendable ──┤
                             ├── Phase 2 (independent, after Phase 1):
Phase 2:                     │     2.1 LayoutEngine decomposition
  2.1 LayoutEngine ──────────┤     2.2 RunLoop decomposition
  2.2 RunLoop ───────────────┤
                             ├── Phase 3 (sequential, after Phase 2):
Phase 3:                     │     3.1 ResolvedNode split
  3.1 ResolvedNode ──────────┤     3.2 Test targets
  3.2 Test targets ──────────┤     3.3 Incremental resolve
  3.3 Incremental resolve ───┘

Build verification after each phase.
```

## Risk Mitigation

- **All changes use extensions** — no public API signatures change
- **No string-compatibility shim remains**. The cleanup is intentionally breaking so the typed model stays closed.
- **Computed property forwarding** on `ResolvedNode` preserves all existing access patterns
- **Build after each phase** to catch regressions early
