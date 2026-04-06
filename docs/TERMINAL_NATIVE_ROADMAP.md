# Terminal Native Roadmap

**Date:** March 30, 2026  
**Depth:** Deep  
**Primary references:** [VISION.md](VISION.md), [STATUS.md](STATUS.md),
[PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md),
[TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md)

## Summary

This roadmap turns the terminal-native doctrine into a concrete framework plan.

The primary goal remains unchanged:

> TerminalUI should be a faithful and idiomatic, but not API-exact, subset of
> SwiftUI that is genuinely useful for TUIs.

This roadmap treats that as a product decision, not just an implementation
detail. From this point forward, default behavior should optimize for
terminal-native navigation, layout, and ergonomics even when that means
reinterpreting SwiftUI concepts instead of copying desktop assumptions.

## Implementation Status

As of March 29, 2026, the roadmap’s primary execution phases are landed:

- Phase 0: governance and public-surface positioning updated across the docs
- Phase 1: automatic chrome reset shipped across the default component set
- Phase 2: `TabView`, `NavigationSplitView`, `alert`, and
  `confirmationDialog` are canonical public surface
- Phase 3: `TextEditor`, indeterminate `ProgressView`, and prototype help or
  command surfaces are in place
- Phase 4: collection defaults and pane-local examples have been reworked
- Phase 5: Gallery and Todoist now teach full-screen terminal workspaces
- Phase 6: README, status docs, module docs, and example READMEs have been
  updated to describe the terminal-native direction

What remains intentionally open is not the roadmap itself, but the next layer
of refinement: richer editor behaviors, deeper scroll control, and the eventual
graduation or replacement of the prototype help and command surfaces.

## Problem Frame

The core pipeline is already implemented and well-tested. The current gap is no
longer foundational rendering. The gap is that parts of the public surface,
default styles, and example apps still read like GUI ideas translated into a
terminal instead of software designed for the terminal first.

The doctrine identified the highest-value changes:

- workspace-first layout instead of page-first layout
- pane-local scrolling instead of root-page scrolling
- visible focus, mode, selection, and async state
- restrained default chrome that respects the host terminal background
- app shells built around panes, tabs, previews, and help surfaces
- deliberate addition of missing workflow primitives such as `TextEditor`,
  `TabView`, indeterminate progress, confirmation flows, and command/help
  surfaces

## Scope

This roadmap covers:

- default visual reinterpretation of `.automatic` behaviors
- canonical public API additions that fit the SwiftUI-shaped surface
- terminal-native deviations that deserve prototype incubation first
- demo and documentation redesign
- regression and fixture strategy for the breaking visual reset

This roadmap does not cover:

- accessibility-tree expansion beyond the current semantic tree
- media formats beyond the current PNG image story
- replacing the SwiftUI-shaped authoring model with MVU or another runtime API
- rebuilding the runtime pipeline from scratch

## Product Decisions

### 1. Reinterpretation Is Now Official Policy

When SwiftUI precedent conflicts with strong terminal-native practice, the
framework should preserve the SwiftUI-shaped authoring story but choose the
terminal-native behavior.

### 2. Default Apps Should Resemble Modern Terminal Software

The default mental model is:

- full-screen shell
- one primary active region
- optional preview or secondary panes
- visible help or status affordance
- pane-local scrolling
- focus and selection as the dominant visual signals

### 3. Terminal-Native Deviations Need Two Tracks

We should add missing SwiftUI-shaped primitives directly to `View` when they
clearly belong there.

We should incubate terminal-specific interaction surfaces in
`PrototypeUIComponents` first when the API would otherwise drift too far from
SwiftUI too early.

## Public Surface Direction

### Promote Into Canonical `View`

These should become first-class public framework surface:

- `TextEditor`
- `TabView`
- indeterminate `ProgressView`
- `alert`
- `confirmationDialog`
- `NavigationSplitView`

### Keep Deferred Until The Shell Model Is Stable

- `NavigationStack`
- popover-style presentation beyond the current sheet support

### Incubate In `PrototypeUIComponents` First

These are valuable, but they should prove themselves before graduating into the
canonical `View` story:

- keybinding/help models
- launcher-style searchable action surfaces beyond the shipped command palette
- terminal-specific status/help bars
- richer launcher or workspace-switcher surfaces

## Execution Posture

This work is a deliberate breaking redesign.

- `.automatic` should become terminal-native with no compatibility mode as the
  default
- existing visually heavy defaults may survive only as explicit opt-in styles
- fixture churn is expected and should be explained as doctrine-driven, not as
  incidental rendering drift
- examples are part of the product surface and must be treated as first-class
  implementation work, not follow-up polish

## Phase 0: Governance And API Policy

### Goal

Make the reinterpretation policy explicit in the docs that define the public
surface and future API decisions.

### Implementation units

- Update [VISION.md](VISION.md) to explicitly say that terminal-native
  reinterpretation is now a first-class design rule, not only a narrow exception
- Update [STATUS.md](STATUS.md) to reflect the new terminal-native direction and
  reorder deferred work around shell and workflow primitives
- Update [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) to classify
  prototype-only terminal-native surfaces separately from canonical `View`
  additions
- Update [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md) so
  it frames Lip Gloss as evidence for restraint and composition, not decoration
- Keep [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md) and this
  roadmap cross-linked

### Decisions

- `PrototypeUIComponents` remains the staging area for terminal-native
  deviations that are not yet settled enough for the core public surface
- future API proposals should cite either doctrine alignment or a reason they
  deliberately diverge from it

### Verification

- doc link integrity and consistency review
- ensure [STATUS.md](STATUS.md), [VISION.md](VISION.md), and
  [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) agree on what is canonical,
  deferred, and prototype-only

## Phase 1: Reset Automatic Chrome And App Defaults

### Goal

Make `.automatic` read as terminal-native by default.

### Scope

- remove page-like and card-like default styling
- make focus, selection, and accent more important than background fill
- make light and dark mode foregrounds explicitly legible
- propagate `.tint(...)` and host-owned theme variants through automatic chrome
  consistently

### Primary files

- [Appearance.swift](../Sources/Core/Appearance.swift)
- [Styling.swift](../Sources/Core/Styling.swift)
- [TerminalChromeStyle.swift](../Sources/Core/TerminalChromeStyle.swift)
- [Environment.swift](../Sources/View/Environment.swift)
- [StyleEnvironment.swift](../Sources/View/StyleEnvironment.swift)
- [StyleModifiers.swift](../Sources/View/StyleModifiers.swift)
- [StylePrimitives.swift](../Sources/View/StylePrimitives.swift)
- [Button.swift](../Sources/View/Button.swift)
- [ValueControls.swift](../Sources/View/ValueControls.swift)
- [AdjustableValueControls.swift](../Sources/View/AdjustableValueControls.swift)
- [SecureField.swift](../Sources/View/SecureField.swift)
- [LabeledContainers.swift](../Sources/View/LabeledContainers.swift)
- [Collections.swift](../Sources/View/Collections.swift)
- [PickerRendering.swift](../Sources/View/PickerRendering.swift)
- [MenuRendering.swift](../Sources/View/MenuRendering.swift)
- [OutlineViews.swift](../Sources/View/OutlineViews.swift)
- [MetricTrackSupport.swift](../Sources/View/MetricTrackSupport.swift)
- [ChartChromeSupport.swift](../Sources/TerminalUICharts/ChartChromeSupport.swift)
- [ChartSupport.swift](../Sources/TerminalUICharts/ChartSupport.swift)

### Decisions

- the terminal background is the default container background
- filled surfaces are for emphasis, not baseline structure
- gradients become opt-in accents, not the default border language
- default buttons can use fill without mandatory border chrome
- full-width and pane-oriented composition should be favored in examples and
  docs

### Verification

- [SwiftUISurfaceTests.swift](../Tests/TerminalUITests/SwiftUISurfaceTests.swift)
- [MenuSurfaceTests.swift](../Tests/TerminalUITests/MenuSurfaceTests.swift)
- [OutlineSurfaceTests.swift](../Tests/TerminalUITests/OutlineSurfaceTests.swift)
- [SecureFieldSurfaceTests.swift](../Tests/TerminalUITests/SecureFieldSurfaceTests.swift)
- [InteractiveRuntimeTests.swift](../Tests/TerminalUITests/InteractiveRuntimeTests.swift)
- fixture refresh under [Fixtures](../Tests/TerminalUITests/Fixtures)

## Phase 2: Ship The Shell Navigation Primitives

### Goal

Add the missing canonical primitives that let apps be terminal workspaces
instead of scrolled forms.

### Scope

- `TabView`
- `NavigationSplitView`
- `alert`
- `confirmationDialog`

### Primary files

- [NavigationViews.swift](../Sources/View/NavigationViews.swift) (hosts both `TabView` and `NavigationSplitView`)
- New [PresentationModifiers.swift](../Sources/View/PresentationModifiers.swift)
- [Environment.swift](../Sources/View/Environment.swift)
- [StyleEnvironment.swift](../Sources/View/StyleEnvironment.swift)
- [FocusState.swift](../Sources/View/FocusState.swift)
- [DefaultFocus.swift](../Sources/View/DefaultFocus.swift)
- [Semantics.swift](../Sources/Core/Semantics.swift)
- [RenderTreeAndSemanticsTypes.swift](../Sources/Core/RenderTreeAndSemanticsTypes.swift)
- [DrawExtractor.swift](../Sources/Core/DrawExtractor.swift)
- [RunLoop.swift](../Sources/TerminalUI/RunLoop.swift)

### Decisions

- `NavigationSplitView` should land before `NavigationStack`
- tabs should be rendered as terminal-native mode switches, not desktop chrome
- alerts and confirmations should feel like focused terminal overlays or action
  prompts, not floating dialog cards
- navigation primitives should participate cleanly in focus traversal and
  pointer support without becoming pointer-first

### Verification

- New `Tests/TerminalUITests/TabViewSurfaceTests.swift`
- New `Tests/TerminalUITests/NavigationSurfaceTests.swift`
- New `Tests/TerminalUITests/PresentationSurfaceTests.swift`
- [InteractiveRuntimeTests.swift](../Tests/TerminalUITests/InteractiveRuntimeTests.swift)
- targeted additions to [AppRuntimeTests.swift](../Tests/TerminalUITests/AppRuntimeTests.swift)

## Phase 3: Add Editing, Loading, And Help Workflow Primitives

### Goal

Cover the workflow surfaces that modern terminal apps rely on for real work.

### Scope

- `TextEditor`
- indeterminate `ProgressView`
- prototype help and keybinding surface
- prototype command palette or searchable action surface

### Primary files

- New [TextEditor.swift](../Sources/View/TextEditor.swift)
- [ProgressView.swift](../Sources/View/ProgressView.swift)
- [ScrollViewSupport.swift](../Sources/View/ScrollViewSupport.swift)
- [SelectionAndValueSupport.swift](../Sources/View/SelectionAndValueSupport.swift)
- [InputReader.swift](../Sources/TerminalUI/InputReader.swift)
- [RunLoop.swift](../Sources/TerminalUI/RunLoop.swift)
- New prototype files under
  [PrototypeUIComponents](../Sources/PrototypeUIComponents)

### Decisions

- `TextEditor` belongs in the canonical `View` surface because multiline entry
  is fundamental
- indeterminate progress should extend `ProgressView`, not introduce a separate
  spinner-first public API
- help and command surfaces should start in `PrototypeUIComponents` until the
  terminal-native authoring shape proves stable in real apps
- while `PrototypeUIComponents` remains target-only, the examples should mirror
  the same help and command patterns through local composition rather than by
  importing the prototype target directly

### Verification

- New `Tests/TerminalUITests/TextEditorSurfaceTests.swift`
- extend [SwiftUISurfaceTests.swift](../Tests/TerminalUITests/SwiftUISurfaceTests.swift)
- extend [InteractiveRuntimeTests.swift](../Tests/TerminalUITests/InteractiveRuntimeTests.swift)
- add runtime coverage for multiline editing, overlay focus, and command/help
  dismissal behavior

## Phase 4: Rework Collections Around Selection, Preview, And Pane Locality

### Goal

Make the collection and scrolling model support the dominant terminal-native
workflow: browse, preview, act, stay oriented.

### Scope

- strengthen list, table, outline, picker, and menu defaults for pane use
- keep scrolling local to the active pane
- improve focus and selection visibility
- add the minimal scroll-control or preview affordances needed by examples

### Primary files

- [Collections.swift](../Sources/View/Collections.swift)
- [CollectionSupport.swift](../Sources/View/CollectionSupport.swift)
- [OutlineViews.swift](../Sources/View/OutlineViews.swift)
- [Picker.swift](../Sources/View/Picker.swift)
- [PickerRendering.swift](../Sources/View/PickerRendering.swift)
- [Menu.swift](../Sources/View/Menu.swift)
- [MenuRendering.swift](../Sources/View/MenuRendering.swift)
- [ContainerViews.swift](../Sources/View/ContainerViews.swift)
- [ScrollViewSupport.swift](../Sources/View/ScrollViewSupport.swift)
- [DrawExtractor+Lists.swift](../Sources/Core/DrawExtractor+Lists.swift)
- [DrawExtractor+Tables.swift](../Sources/Core/DrawExtractor+Tables.swift)
- [TableDrawSupport.swift](../Sources/Core/TableDrawSupport.swift)
- [FocusPolicy.swift](../Sources/Core/FocusPolicy.swift)
- [FocusTracker.swift](../Sources/Core/FocusTracker.swift)

### Decisions

- `ScrollView` remains a pane primitive, not a whole-page default
- list and table affordances should bias toward active selection and keyboard
  movement, not passive presentation
- preview-driven examples should be possible without inventing a monolithic
  higher-level browser widget in core
- only add richer scroll APIs when a real app flow requires them

### Verification

- [CollectionSupportTests.swift](../Tests/TerminalUITests/CollectionSupportTests.swift)
- [SwiftUISurfaceTests.swift](../Tests/TerminalUITests/SwiftUISurfaceTests.swift)
- [OutlineSurfaceTests.swift](../Tests/TerminalUITests/OutlineSurfaceTests.swift)
- [InteractiveRuntimeTests.swift](../Tests/TerminalUITests/InteractiveRuntimeTests.swift)
- fixture refresh for list, table, picker, menu, and outline surfaces

## Phase 5: Redesign The Example Apps As Real Terminal Workspaces

### Goal

Make the examples prove the new philosophy.

### Scope

- rework Todoist into a full-screen, pane-oriented task app
- rework Gallery into a component workbench instead of a scrolled component page
- ensure both examples exercise canonical workflow surfaces directly and mirror
  prototype help or command patterns while those remain target-only

### Primary files

- [TodoistViews.swift](../Examples/todoist/Sources/TodoistDemo/TodoistViews.swift)
- [TodoistAppModel.swift](../Examples/todoist/Sources/TodoistDemo/TodoistAppModel.swift)
- [TodoistDemoLauncher.swift](../Examples/todoist/Sources/TodoistDemo/TodoistDemoLauncher.swift)
- [GalleryDemoViews.swift](../Examples/gallery/Sources/GalleryDemo/GalleryDemoViews.swift)
- [GalleryDemoModel.swift](../Examples/gallery/Sources/GalleryDemo/GalleryDemoModel.swift)
- example READMEs under [Examples/todoist](../Examples/todoist/README.md) and
  [Examples/gallery](../Examples/gallery/README.md)

### Decisions

- no root-page scroll in either example
- both examples should own the full terminal width
- the gallery should function as a component workbench with navigation, focus,
  and preview, not as a static catalog
- the Todoist example should feel like a real TUI app, not a decorated demo
- examples should adopt prototype workflow surfaces directly only after those
  surfaces graduate from the target-only staging area

### Verification

- [TodoistViewsSurfaceTests.swift](../Examples/todoist/Tests/TodoistDemoTests/TodoistViewsSurfaceTests.swift)
- [GallerySurfaceTests.swift](../Examples/gallery/Tests/GalleryDemoTests/GallerySurfaceTests.swift)
- `swiftly run swift test`
- `swiftly run swift test --package-path Examples/todoist`
- `swiftly run swift test --package-path Examples/gallery`

## Phase 6: Documentation And Public Positioning

### Goal

Make the repo explain itself in the new terms.

### Scope

- rewrite README examples and screenshots to show shell-level composition
- update module docs to reflect the terminal-native direction
- document which surfaces are canonical, prototype-only, or still deferred

### Primary files

- [README.md](../README.md)
- [STATUS.md](STATUS.md)
- [VISION.md](VISION.md)
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md)
- module docs under `Sources/*/*.docc`

### Decisions

- examples in docs should stop using scrolled showcase composition as the
  default teaching pattern
- screenshots should show full-screen terminal-native layouts
- prototype-only surfaces must be labeled clearly so readers do not mistake them
  for settled public API

### Verification

- doc review for internal consistency
- ensure code examples and screenshots match the actual example apps

## Sequencing

Recommended order:

1. Phase 0: Governance and API policy
2. Phase 1: Reset automatic chrome and app defaults
3. Phase 2: Ship the shell navigation primitives
4. Phase 3: Add editing, loading, and help workflow primitives
5. Phase 4: Rework collections around selection, preview, and pane locality
6. Phase 5: Redesign the example apps as real terminal workspaces
7. Phase 6: Documentation and public positioning

Dependency notes:

- Phase 1 should happen before example redesign so the demos are built on the
  new default visual language
- Phase 2 should happen before final example redesign because the examples need
  stable shell primitives
- Phase 3 can partially overlap with Phase 4, but the first prototype help and
  command surfaces should exist before the examples are finalized
- Phase 6 should trail the feature work so docs describe the actual settled
  surface, not an aspirational one

## Risks And Tradeoffs

### 1. Overcorrecting Into Non-SwiftUI APIs

Risk:

- terminal-native ambition could cause the public surface to drift into an
  unrelated framework

Mitigation:

- keep canonical additions recognizably SwiftUI-shaped
- use `PrototypeUIComponents` for experimental terminal-native surfaces first

### 2. Shipping Visual Changes Without Better Navigation

Risk:

- a chrome-only reset would make the framework look flatter without solving the
  deeper app-shell problem

Mitigation:

- treat Phase 2 and Phase 3 as part of the same product story, not optional
  follow-up work

### 3. Too Much Fixture Churn At Once

Risk:

- broad visual changes can obscure behavior regressions

Mitigation:

- land the work in phase-sized chunks
- keep fixture updates grouped by subsystem
- expand focused surface tests alongside each fixture refresh

### 4. Prototype Surfaces Becoming Permanent By Accident

Risk:

- help and command APIs could leak into docs and examples before they are ready

Mitigation:

- classify prototype-only surfaces explicitly in docs
- gate graduation on real example usage and test coverage

## Exit Criteria

This roadmap is complete when:

- a new TerminalUI app naturally composes into a terminal-native workspace
- `.automatic` styling looks at home in the terminal without extra decoration
- the core public surface includes the missing workflow primitives required by
  real TUIs
- examples teach pane-oriented, keyboard-first composition by default
- the docs clearly explain which APIs are canonical, terminal-native
  deviations, and future work

## Suggested First Implementation Slice

The highest-leverage first slice is:

1. Phase 0 governance updates
2. Phase 1 automatic chrome reset
3. the smallest viable `TabView` and `NavigationSplitView` from Phase 2
4. gallery and Todoist structural redesign on top of those primitives

That slice changes the visual language, the shell model, and the teaching
surface together, which is the minimum needed for the framework to stop
presenting itself as page-like GUI-in-a-terminal software.
