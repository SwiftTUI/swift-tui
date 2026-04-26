# Type Erasure Deferral Plan

## Goal

Move `AnyView` and `[AnyView]` from "default internal storage" to "rare escape hatch".

For this repository, "as far back as possible" means:

- authored `View.body` structure stays typed through builder formation, view storage, and ordinary resolve traversal
- deferred builder closures preserve dynamic-property scope without erasing to `AnyView`
- internal helper composition prefers typed wrapper views or `@ViewBuilder` returns over `AnyView` branch unification
- complex shell views stop bouncing through `ResolvedNode -> AnyView -> ResolvedNode`

The intended end state is not "zero `AnyView` symbols". The intended end state is:

- `AnyView` remains public as an explicit escape hatch
- `buildLimitedAvailability` remains an availability-driven erasure seam
- compatibility shims, if retained, are visibly transitional rather than the main representation

## Executive Summary

This investigation found two different ceilings:

1. A compatibility ceiling
   - Keep the current non-generic public view types such as `Button`, `VStack`, `Section`, `Label`, `ProgressView`, and `WindowGroup`.
   - This can remove a large amount of internal `AnyView` usage, especially in helper functions and deferred closures.
   - It cannot eliminate early erasure from non-generic view types that accept arbitrary builder content, because those types must store heterogeneous authored content somehow.

2. A maximum ceiling
   - Convert builder-taking public types to SwiftUI-shaped generic forms such as `Button<Label>`, `VStack<Content>`, `Section<Content, Header, Footer>`, `Label<Title, Icon>`, `ProgressView<Label, CurrentValueLabel>`, `TabView<SelectionValue, Content>`, and `WindowGroup<Content>`.
   - Replace the current builder-children arrays with a typed structural builder representation.
   - This is the only path that genuinely pushes erasure back as far as the current Swift toolchain allows.

Recommendation:

- Treat the maximum ceiling as the target architecture.
- Treat the compatibility ceiling as a temporary waypoint only if semver or rollout constraints require it.

## Current Runtime And Scene Status

The runtime and scene layer now follow the maximum path:

- `WindowGroup<Content>` is generic
- `SceneBuilder` lowers into typed scene artifacts instead of `SceneGroup`
- `AnyScene` exists only as the explicit scene-erasure seam
- `RunLoop<State, Content>` stores typed deferred builders through scoped generic helpers
- hosted scene selection and manifest generation traverse typed scenes directly instead of collecting `[WindowSceneConfiguration]`

## Investigation Findings

### Toolchain And Language Feasibility

Local checks in this repository's environment show, using the repo-default
`swiftly`-managed Swift 6.3.1 toolchain:

- `swift --version` reports Apple Swift 6.3.1.
- Variadic generic types compile in scratch experiments.
- Pack iteration compiles in scratch experiments.
- A result builder can produce a pack-backed structural container in scratch experiments.
- Public `some View` APIs can hide package-private or private wrapper view types without using `AnyView`.

Relevant language references:

- [SE-0393: Value and Type Parameter Packs](https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0393-parameter-packs.md)
- [SE-0398: Allow Generic Types to Abstract Over Packs](https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0398-variadic-types.md)
- [SE-0408: Pack Iteration](https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0408-pack-iteration.md)

These are sufficient for a pack-backed internal builder representation in Swift 6.3.

### Current Erasure Categories

Current `AnyView` usage falls into four recurring categories.

1. Builder artifact flattening
   - `Sources/View/ViewFoundation.swift`
   - `TupleView`, `ConditionalContent`, and `VariadicView` flatten builder output into `builderChildren: [AnyView]`.
   - `declaredBuilderChildren(...)` converts typed builder content into `[AnyView]` almost immediately.

2. Non-generic public types storing authored content
   - `Sources/View/Button.swift`
   - `Sources/View/ContainerViews.swift`
   - `Sources/View/Collections.swift`
   - `Sources/View/LabeledContainers.swift`
   - `Sources/View/ProgressView.swift`
   - `Sources/View/ValueControls.swift`
   - `Sources/View/AdjustableValueControls.swift`
   - `Sources/View/Menu.swift`
   - `Sources/View/Picker.swift`
   - `Sources/View/NavigationViews.swift`
   - `Sources/TerminalUICharts/*.swift`
   - These types accept typed builder closures at their initializer boundary, but the type itself is not generic over the builder result, so the content must be erased to be stored.

3. Deferred builder closures
   - `Sources/View/ContainerViews.swift` (`ForEach`)
   - `Sources/View/Environment.swift` (`EnvironmentReader`)
   - `Sources/View/Preference.swift`
   - `Sources/View/OutlineViews.swift`
   - `Sources/TerminalUI/App.swift` (`WindowGroup`)
   - These closures usually produce a single concrete `Content: View` type, but are currently stored as closures returning `AnyView` in order to preserve later evaluation plus dynamic-property scope.

4. Local branch unification and convenience composition
   - `Sources/View/Button.swift`
   - `Sources/View/MenuRendering.swift`
   - `Sources/View/PickerRendering.swift`
   - `Sources/View/ValueControls.swift`
   - `Sources/View/AdjustableValueControls.swift`
   - `Sources/View/LabeledContainers.swift`
   - `Sources/View/ProgressView.swift`
   - `Sources/View/SelectionAndValueSupport.swift`
   - `Sources/View/ViewCompositionHelpers.swift`
   - `Sources/TerminalUICharts/ChartSupport.swift`
   - These sites often use `AnyView` only because a helper returns one of several shaped view trees. In most cases, `@ViewBuilder` or a dedicated private wrapper type can replace the erasure.

### Hard Constraints

The investigation found three real constraints.

1. Non-generic public view types force storage erasure
   - A non-generic type like today's `Button` cannot accept `@ViewBuilder label: () -> Label` and later store the typed label without either:
     - becoming generic over `Label`, or
     - introducing some erased storage form.

2. Today's builder artifact types erase too early
   - `ViewBuilder` currently preserves source-level structure only long enough to form `TupleView` and related artifacts, then immediately flattens children into `[AnyView]`.
   - This prevents later pipeline stages from seeing the original structural shape.

3. Some seams are intentionally irreducible
   - public `AnyView`
   - `buildLimitedAvailability`
   - deprecated compatibility facades, if the migration chooses to keep them temporarily

## Recommended End State

### Representation Rules

- Public authoring stays SwiftUI-shaped.
- Internal storage is typed by default.
- Builder structure remains typed until resolve actually needs resolved children.
- `AnyView` is only used when the author explicitly asks for erasure or when availability compatibility forces it.

### Structural Builder Backbone

Introduce a package-private typed builder container in `Sources/View/ViewFoundation.swift` or a new adjacent file:

- `ViewList<each Content: View>`

Responsibilities:

- store a pack-backed tuple of child views
- conform to `View` and `ResolvableView`
- resolve typed children with pack iteration
- provide a structural child traversal primitive for containers

This can be used in one of two ways:

- maximum path: `ViewBuilder.buildBlock` returns `ViewList<repeat each Content>`
- compatibility path: keep the public `TupleView` family, but back it with a typed structural child representation instead of `[AnyView]`

Recommendation:

- Use the maximum path for new internal representation.
- Keep `TupleView`, `ConditionalContent`, and `VariadicView` only as public compatibility artifacts if needed.

### Generic Public Surface

To remove most storage-driven erasure, genericize builder-taking view types.

Container family:

- `Group<Content>`
- `ViewThatFits<Content>`
- `VStack<Content>`
- `HStack<Content>`
- `ZStack<Content>`
- `TabView<SelectionValue, Content>`
- `Section<Content, Header, Footer>`
- `TableRow<Content>`
- `Table<SelectionValue, Rows>`

Control family:

- `Button<Label>`
- `Menu<Label, Content>`
- `Toggle<Label>`
- `TextField<Label>`
- `SecureField<Label>`
- `DisclosureGroup<Label, Content>`
- `Stepper<Label>`
- `Slider<Label>`
- `Picker<SelectionValue, Label, Content>`
- `ProgressView<Label, CurrentValueLabel>`

Labeling family:

- `Label<Title, Icon>`
- `LabeledContent<Label, Content>`
- `ControlGroup<Label, Content>`
- `GroupBox<Label, Content>`

Navigation and scenes:

- `WindowGroup<Content>` should become generic if the project wants maximum deferral across the full stack

Charts:

- `ThresholdGauge<Label, Summary>`
- `ColumnChart<Label, Summary>`
- `ComparisonChart<Label, Summary>`
- `Meter<Label, CurrentValueLabel>`
- `BarChart<Label, Summary>`
- `BulletChart<Label, Summary>`
- `StackedBarChart<Label, Summary>`
- `Legend<Label>`
- `HeatStrip<Label, Summary>`
- `Sparkline<Label, Summary>`

## What This Unlocks

### 1. Stronger Resolve Reuse

Today resolve reuse is conservative and driven by resolved-tree identity plus compatible environment and transaction snapshots.

With typed structural representation kept longer, the resolve phase can additionally capture a structural authoring fingerprint before normalization:

- child count and branch shape before flattening
- active conditional branch shape
- pack-backed container shape
- closure-driven content family shape for deferred builders

Files likely involved:

- `Sources/View/Environment.swift`
- `Sources/Core/CommitAndFrameTypes.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/LayoutEngine.swift`

The immediate opportunity is to make "same identity, same environment, same transaction" reuse safer and more selective for complex structural content.

### 2. Less Dynamic-Property Scope Repair Work

Today the project relies on `scopedAnyView(...)` in many places because authored content is erased and later re-evaluated.

With typed deferred builders:

- fewer scope-restoration wrappers are needed
- fewer bugs can attach `@State` or observation invalidation to the wrong identity owner
- scope preservation becomes a generic helper rather than a repo-wide `AnyView` convention

### 3. Better Diagnostics And Debuggability

Keeping structural typing longer makes it possible to snapshot or inspect:

- declared child shape before flattening
- selected branch shape in conditionals
- typed child family boundaries in containers

That is useful for:

- resolve-reuse debugging
- builder-shape regression tests
- future architectural guardrails that catch accidental early erasure

### 4. Lower Allocation And Closure Overhead

Expected runtime wins:

- fewer `AnyView` boxes
- fewer closure captures returning `AnyView`
- less intermediate array churn for small fixed child groups
- more specialization opportunities in helper composition

These should be treated as secondary gains. The main win is architectural leverage.

## Migration Plan

### Execution Posture

Characterization-first.

This refactor crosses public API shape, builder lowering, identity semantics, observation scope, and resolve reuse. The plan should add or tighten characterization coverage before each migration family rather than relying on broad after-the-fact breakage discovery.

### Phase 0: Baseline Characterization And Guardrails

Create or tighten tests that describe the behavior that must not regress.

Primary files:

- `Tests/ViewTests/ViewResolutionTests.swift`
- `Tests/ViewTests/ActorIsolationSurfaceTests.swift`
- `Tests/TerminalUITests/ViewCompositionSurfaceTests.swift`
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
- `Tests/TerminalUITests/PreferenceSurfaceTests.swift`
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`
- `Tests/TerminalUITests/ResolveReuseIndexingTests.swift`
- `Tests/TerminalUITests/ResolveReuseAncestorInvalidationTests.swift`
- `Tests/TerminalUITests/LayoutReuseAncestorInvalidationTests.swift`
- `Tests/TerminalUITests/DiagnosticsAndCacheTests.swift`
- `Tests/TerminalUITests/TabViewSurfaceTests.swift`
- `Tests/TerminalUITests/OutlineSurfaceTests.swift`
- `Tests/TerminalUITests/MenuSurfaceTests.swift`
- `Tests/TerminalUITests/PresentationSurfaceTests.swift`
- `Tests/TerminalUITests/ProgressViewSurfaceTests.swift`
- `Tests/TerminalUITests/SecureFieldSurfaceTests.swift`
- `Tests/TerminalUITests/TextEditorSurfaceTests.swift`

Add assertions for:

- builder flattening semantics
- conditional/optional branch behavior
- dynamic-property scope ownership in deferred builders
- identity stability under structural containers
- current resolve-reuse hit/miss behavior
- tab/list/table selection behavior

### Phase 1: Remove Easy Internal Erasure Without Public API Changes

Target only helper-return and wrapper-return sites where `AnyView` is convenience, not necessity.

Primary files:

- `Sources/View/ViewModifiers.swift`
- `Sources/View/Button.swift`
- `Sources/View/MenuRendering.swift`
- `Sources/View/PickerRendering.swift`
- `Sources/View/ValueControls.swift`
- `Sources/View/AdjustableValueControls.swift`
- `Sources/View/LabeledContainers.swift`
- `Sources/View/ProgressView.swift`
- `Sources/View/SelectionAndValueSupport.swift`
- `Sources/View/MetricTrackSupport.swift`
- `Sources/TerminalUICharts/ChartSupport.swift`

Actions:

- replace `AnyView` helper returns with `@ViewBuilder` functions where the result is consumed immediately
- replace branch-unifying locals like `let label: AnyView` with private wrapper views or builder methods
- return concrete package-private wrapper types from public `some View` APIs instead of `AnyView(resolving: ...)`

This phase should remove a large amount of erasure with low semantic risk.

### Phase 2: Generic Deferred Builders

Convert stored deferred builder closures from `AnyView` to typed generic outputs plus explicit scope restoration.

Primary files:

- `Sources/View/ContainerViews.swift`
- `Sources/View/Environment.swift`
- `Sources/View/Preference.swift`
- `Sources/View/OutlineViews.swift`
- `Sources/TerminalUI/App.swift`

Introduce package-private helper types such as:

- `ScopedBuilder<Output: View>`
- `ScopedMapper<Input, Output: View>`

Actions:

- `ForEach<Data, ID, Content>`
- `EnvironmentReader<Value, Content>`
- `PreferenceOverlayValueModifier<Base, Key, Overlay>`
- `PreferenceBackgroundValueModifier<Base, Key, Background>`
- `OutlineTree<Element, ID, RowContent>`
- `WindowGroup<Content>` if the scene layer joins the maximum path in this phase

This phase should remove the most subtle scope-preservation erasure sites.

### Phase 3: Builder Backbone Replacement

Replace `[AnyView]` builder plumbing with a typed structural representation.

Primary files:

- `Sources/View/ViewFoundation.swift`
- `Sources/View/ViewCompositionHelpers.swift`
- `Sources/View/ContainerViews.swift`
- `Sources/View/Layout.swift`

Actions:

- add `ViewList<each Content: View>` or equivalent typed structural container
- change `ViewBuilder.buildBlock` to construct the typed structural representation
- remove `BuilderCompositeView.builderChildren: [AnyView]`
- replace `declaredBuilderChildren(...)` and `resolveDeclaredChildren(...)` with typed traversal helpers
- replace `combinedView(from: [AnyView])` and `composedView(from: [AnyView])` with typed equivalents

Decision point:

- If the project requires source compatibility for public builder artifact types, stop here temporarily and keep a compatibility adapter.
- If the project wants the true maximum endpoint, continue into Phase 4 immediately.

### Phase 4: Genericize Builder-Taking Public View Types

This is the phase that crosses the hard architectural wall.

Primary files:

- `Sources/View/ContainerViews.swift`
- `Sources/View/Collections.swift`
- `Sources/View/Button.swift`
- `Sources/View/Menu.swift`
- `Sources/View/Picker.swift`
- `Sources/View/ValueControls.swift`
- `Sources/View/AdjustableValueControls.swift`
- `Sources/View/LabeledContainers.swift`
- `Sources/View/ProgressView.swift`
- `Sources/View/SecureField.swift`
- `Sources/View/NavigationViews.swift`
- `Sources/TerminalUICharts/*.swift`
- `Sources/TerminalUI/App.swift`

Actions:

- make each builder-taking type generic over its authored child content
- keep string convenience initializers and other ergonomic entry points by specializing to `Text`
- convert stored `[AnyView]` fields into typed generic properties
- update doc inventory and any public examples that mention the old non-generic shapes

This phase is source-breaking in type identity, but most call sites should continue to compile through generic inference.

### Phase 5: Rewrite Complex Shell Views To Stay In Resolved Form

Target views that still erase because they mix authored composition with resolved-node inspection.

Primary files:

- `Sources/View/NavigationViews.swift`
- `Sources/View/Collections.swift`
- `Sources/View/PresentationModifiers.swift`

Actions:

- `TabView`: eliminate `ResolvedNode.erasedToAnyView()` and either:
  - resolve selected authored content directly under the final content identity, or
  - construct the tab shell `ResolvedNode` tree directly from the selected resolved subtree
- `List` and `Table`: traverse typed content structure directly instead of first rebuilding grouped `AnyView` composition
- presentation hosts: store typed action/message content and compose resolved nodes directly where that is simpler than reauthoring as views

### Phase 6: Exploit Structural Reuse And Diagnostics

Once the representation is typed, use it.

Primary files:

- `Sources/View/Environment.swift`
- `Sources/Core/CommitAndFrameTypes.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/Snapshots.swift`
- `Tests/TerminalUITests/DiagnosticsAndCacheTests.swift`
- `Tests/TerminalUITests/TimingDiagnosticsTests.swift`
- `Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`

Actions:

- add an explicit structural authoring fingerprint or equivalent diagnostic snapshot
- feed the new structure into resolve-reuse and measurement-reuse validation
- surface typed-structure counts or shape diagnostics in snapshots where useful

This is where the migration begins to pay back more than code cleanliness.

### Phase 7: Policy And Documentation Cleanup

Primary files:

- `docs/PUBLIC_SURFACE_POLICY.md`
- `docs/PUBLIC_API_INVENTORY.md`
- `docs/ARCHITECTURE.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/STATUS.md`
- `Sources/View/View.docc/View.md`
- `Sources/View/View.docc/Authoring-Views.md`
- `README.md`

Actions:

- change the policy from "internal `AnyView` is allowed in these cases" to "internal `AnyView` requires explicit justification and should be exceptional"
- update the canonical public API inventory to reflect genericized public view types, if the maximum path is adopted
- document the new builder backbone and the expected remaining erasure seams

## Compatibility Strategy

If this migration must ship incrementally without immediately breaking type identities, use a two-track rollout.

Track A: internal cleanup first

- complete Phases 1 through 3
- retain compatibility adapters or old public type shapes temporarily
- measure how much `AnyView` remains and where

Track B: maximum path

- land Phase 4 as a deliberate public-surface migration
- update docs and examples in the same change window
- optionally leave deprecated compatibility wrappers in place for one release cycle

Recommendation:

- Do not stop permanently at Track A.
- Track A removes a lot of noise, but it leaves the deepest architectural constraint in place.

## Remaining Irreducible Erasure Sites

Even at the maximum endpoint, expect these to remain:

- public `AnyView`
- `ViewBuilder.buildLimitedAvailability`
- explicit compatibility wrappers kept for migration
- test-support fixtures that intentionally exercise the public erasure API

Everything else should be treated as removable unless a concrete counterexample appears during implementation.

## Verification Plan

For each migration batch:

1. Run focused suites for the touched area.
2. Run the full `swiftly run swift test` suite before considering the batch complete.
3. Compare diagnostics and reuse behavior in:
   - `Tests/TerminalUITests/DiagnosticsAndCacheTests.swift`
   - `Tests/TerminalUITests/ResolveReuseIndexingTests.swift`
   - `Tests/TerminalUITests/ResolveReuseAncestorInvalidationTests.swift`
   - `Tests/TerminalUITests/LayoutReuseAncestorInvalidationTests.swift`
4. Check interactive and surface suites for controls and shells that changed.
5. Update rendered fixtures only when the semantic output genuinely changes.

Repository-required final verification command:

```bash
swiftly run swift test
```

## Recommended First Implementation Slice

Start with the highest-leverage, lowest-risk sequence:

1. Phase 0 characterization
2. Phase 1 helper-return cleanup
3. Phase 2 deferred-builder genericization
4. Phase 3 builder backbone replacement

After those land, reassess whether any public-surface constraints still justify pausing before Phase 4. If the answer is "no", proceed directly into the maximum path.
