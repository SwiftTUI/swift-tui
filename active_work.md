# Active Work

## Rules

- Keep this document up to date whenever active tasks are added, completed, or
  re-scoped.
- Include only work that is not yet completed.
- Use concise task descriptions with links to supporting docs, plans, source
  files, or tests.
- Remove completed work from this document entirely. Document completed work in
  its supporting documentation instead.
- Treat this file as additive to the repo documentation structure. It does not
  replace durable docs, proposals, ADRs, plans, or tests.
- Use this file as the first place to check what is next.

## Remaining Accessibility Tasks

Source of truth for shipped accessibility behavior:
[`docs/ACCESSIBILITY.md`](docs/ACCESSIBILITY.md).

- [ ] Complete reduced-motion semantics across all motion-producing surfaces.
  - Current state: `EnvironmentValues.accessibilityReduceMotion` exists, and
    `Spinner`, indeterminate `ProgressView`, and scoped animation modifiers
    already honor it.
  - Remaining work: define and test policy for transitions, `PhaseAnimator`,
    `AnimatedImage`, matched geometry, and animated content changes.
  - Evidence:
    - `docs/ACCESSIBILITY.md`
    - `Sources/SwiftTUIViews/Animation/PhaseAnimator.swift`
    - `Sources/SwiftTUIAnimatedImage/AnimatedImage.swift`

- [ ] Finish the modal accessibility focus contract.
  - Current state: modal base suppression and one sheet focus-restoration path
    are covered.
  - Remaining work: make the cross-presentation contract explicit for initial
    focus, trap/cycle behavior, dismiss restoration fallback, and target-bridge
    behavior for `sheet`, `alert`, and `confirmationDialog`.
  - Evidence:
    - `docs/ACCESSIBILITY.md`
    - `Tests/SwiftTUITests/PresentationSurfaceTests.swift`
    - `Tests/SwiftTUITests/AppRuntimeTests.swift`

- [ ] Decide whether SwiftUI host focus should move native VoiceOver focus.
  - Current state: SwiftUI host focus is metadata-only in v1; the host records
    `focusedAccessibilityIdentity` and mounts accessibility overlay elements,
    but does not programmatically move global VoiceOver focus.
  - Remaining work: either implement native focus movement with
    `AccessibilityFocusState` or explicitly reaffirm metadata-only focus as the
    intended policy.
  - Evidence:
    - `docs/decisions/0015-accessibility-swiftui-host-policy.md`
    - `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift`
    - `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift`

- [ ] Clean up stale historical proposal open questions.
  - Current state: `docs/ACCESSIBILITY.md` is current, but the long proposal
    still contains old open-question text around detection hints, spinner
    replacement granularity, and chart representation.
  - Remaining work: mark resolved items as resolved, fold still-relevant items
    into the durable docs or active plans, and demote true out-of-scope notes.
  - Evidence:
    - `docs/proposals/ACCESSIBILITY.md`
