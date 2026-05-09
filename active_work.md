# Active Work

## Rules

- Keep this document up to date whenever active tasks are added, completed, or
  re-scoped.
- Include only work that is not yet completed.
- Use concise task descriptions with links to supporting docs, plans, source
  files, or tests.
- Remove completed work from this document entirely.
- When removing completed work, add a concise self-standing entry to
  [CHANGELOG.md](CHANGELOG.md). Keep long-form details in the supporting docs,
  plans, source, or tests.
- Changelog entries may link to long-lived repo documentation, but every link
  must be prefixed with the short git hash that anchors the referenced material,
  for example: `4ee7a8f9 [docs/STATUS.md](docs/STATUS.md)`.
- Treat this file as additive to the repo documentation structure. It does not
  replace durable docs, proposals, ADRs, plans, or tests.
- Use this file as the first place to check what is next.

## Repo Documentation Hygiene

- [ ] Update the public API inventory for the border/stroke simplification that
  has already landed in source. Supporting docs and source:
  [docs/PUBLIC_API_INVENTORY.md](docs/PUBLIC_API_INVENTORY.md),
  [Sources/SwiftTUICore/Styling/BorderSet.swift](Sources/SwiftTUICore/Styling/BorderSet.swift),
  [Sources/SwiftTUICore/Styling/Styling.swift](Sources/SwiftTUICore/Styling/Styling.swift).
- [ ] Reconcile historical animation proposal status with current transition and
  matched-geometry source. Supporting docs and source:
  [docs/proposals/ANIMATION_PLAN.md](docs/proposals/ANIMATION_PLAN.md),
  [docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md),
  [Sources/SwiftTUI/Lifecycle/AnimationController.swift](Sources/SwiftTUI/Lifecycle/AnimationController.swift),
  [Sources/SwiftTUIViews/Animation/AnyTransition.swift](Sources/SwiftTUIViews/Animation/AnyTransition.swift).
- [ ] Close or re-scope active plan files whose source appears to have moved
  ahead of their unchecked task lists. Supporting plans:
  [docs/plans/2026-04-26-003-border-stroke-simplification-plan.md](docs/plans/2026-04-26-003-border-stroke-simplification-plan.md),
  [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](docs/plans/2026-04-28-001-canvas-adaptation-plan.md),
  [docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md](docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md).

## Runtime And Public Surface Gaps

- [ ] Finish behavior wiring for parsed `RuntimeConfiguration` fields that are
  still documented as follow-up work: `--json`, standalone `--linear`,
  `--debug`, and `--start-in`. Supporting docs and source:
  [README.md](README.md),
  [docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md),
  [Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift](Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift),
  [Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift](Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift),
  [Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift](Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift).
- [ ] Continue the remaining `AnyView` / `[AnyView]` reduction work without
  weakening the public-surface policy. Supporting docs and source:
  [docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md](docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md),
  [docs/ANYVIEW_INTERNALS.md](docs/ANYVIEW_INTERNALS.md),
  [Sources/SwiftTUIViews/Foundation/ViewFoundation.swift](Sources/SwiftTUIViews/Foundation/ViewFoundation.swift),
  [Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift](Sources/SwiftTUIViews/NavigationViews/TabViewStyles.swift).
- [ ] Decide whether to execute or demote the first-class modifier-layer
  migration. Supporting docs and source:
  [docs/proposals/VIEW_MODIFIER_LAYER.md](docs/proposals/VIEW_MODIFIER_LAYER.md),
  [Sources/SwiftTUIViews/Foundation/ViewModifier.swift](Sources/SwiftTUIViews/Foundation/ViewModifier.swift),
  [Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift](Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift).
- [ ] Replace the `.task(id:)` reflection-based descriptor identity with a
  deliberate identity strategy. Supporting source:
  [Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift](Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift).
- [ ] Turn the current constraints in `docs/STATUS.md` into executable plans or
  explicitly defer them: default-focus scopes, `@FocusedObject`, richer
  `TextEditor`, `NavigationStack`, popover-style presentation, terminal
  workspaces, deeper scroll control, and navigation surfaces. Supporting docs:
  [docs/STATUS.md](docs/STATUS.md),
  [docs/VISION.md](docs/VISION.md),
  [docs/FOCUS.md](docs/FOCUS.md).

## Canvas And Pointer Work

- [ ] Finish or close the Canvas pointer-precision tranche. Supporting docs and
  source:
  [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](docs/plans/2026-04-28-001-canvas-adaptation-plan.md),
  [docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md](docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md),
  [Sources/SwiftTUI/Input/InputReader.swift](Sources/SwiftTUI/Input/InputReader.swift),
  [Sources/SwiftTUIViews/Canvas.swift](Sources/SwiftTUIViews/Canvas.swift),
  [Tests/SwiftTUICoreTests/Pointer](Tests/SwiftTUICoreTests/Pointer),
  [Tests/SwiftTUICoreTests/CanvasGridTests.swift](Tests/SwiftTUICoreTests/CanvasGridTests.swift).

## Remaining Accessibility Tasks

Source of truth for shipped accessibility behavior:
[docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).

- [ ] Complete reduced-motion policy and tests across transitions,
  `PhaseAnimator`, `AnimatedImage`, matched geometry, and animated content
  changes. Supporting docs and source:
  [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md),
  [docs/decisions/0013-accessibility-runtime-policy.md](docs/decisions/0013-accessibility-runtime-policy.md),
  [Sources/SwiftTUIViews/Animation/PhaseAnimator.swift](Sources/SwiftTUIViews/Animation/PhaseAnimator.swift),
  [Sources/SwiftTUIAnimatedImage/AnimatedImage.swift](Sources/SwiftTUIAnimatedImage/AnimatedImage.swift).
- [ ] Finish the modal accessibility focus contract for initial focus,
  trap/cycle behavior, dismiss restoration fallback, and target-bridge behavior
  across `sheet`, `alert`, and `confirmationDialog`. Supporting docs and tests:
  [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md),
  [Tests/SwiftTUITests/PresentationSurfaceTests.swift](Tests/SwiftTUITests/PresentationSurfaceTests.swift),
  [Tests/SwiftTUITests/AppRuntimeTests.swift](Tests/SwiftTUITests/AppRuntimeTests.swift).
- [ ] Decide whether SwiftUI host focus should move native VoiceOver focus or
  remain metadata-only. Supporting docs and source:
  [docs/decisions/0015-accessibility-swiftui-host-policy.md](docs/decisions/0015-accessibility-swiftui-host-policy.md),
  [Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift](Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift),
  [Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift](Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift).
- [ ] Clean up stale historical accessibility proposal open questions.
  Supporting docs:
  [docs/proposals/ACCESSIBILITY.md](docs/proposals/ACCESSIBILITY.md),
  [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).
