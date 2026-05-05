---
title: "feat: accessibility CLI runtime behavior"
type: feat
status: proposed
date: 2026-05-05
depends_on:
  - "2026-05-05-002-accessibility-remaining-work-plan.md"
  - "../proposals/ACCESSIBILITY.md"
  - "../proposals/SUBSTRATE_AUDIT.md"
  - "../decisions/0011-accessibility-role-replaces-presentation-role.md"
  - "../decisions/0012-accessibility-node-shape.md"
---

# Accessibility CLI Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Do not implement stages after Stage 1 until the policy decisions
> are written down and this plan is updated to match them.

**Goal:** Make terminal runners consume the shared accessibility substrate for
accessible output mode, cursor-as-focus, reduced motion, no-progress behavior,
and live-region announcements.

**Architecture:** Keep `SwiftTUICore` as the semantic source of truth.
`SwiftTUI` runtime code consumes `FrameArtifacts.semanticSnapshot` and
`FocusTracker.currentFocusIdentity`; `SwiftTUIArguments` and
`RuntimeConfiguration.detect(...)` only choose policy. Terminal presentation
logic stays in terminal-owned files, with no web or SwiftUI-host behavior in
this patch.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing,
`RuntimeConfiguration`, `SwiftTUIOptions`, `TerminalRunner`, `SceneRuntime`,
`RunLoop`, `TerminalHost`, `CommitPlan`, `SemanticSnapshot.accessibilityNodes`,
and `FocusTracker`.

---

## Open Questions To Resolve First

1. **Output precedence:** pick one rule for `--accessible`, `--json`,
   `SWIFTTUI_ACCESSIBLE`, and `SWIFTTUI_JSON`. Current CLI flags prefer
   accessible over JSON; env detection lets JSON override accessible.
2. **Accessible-mode implications:** decide whether accessible mode implies
   ASCII, reduced motion, no progress, and linear layout.
3. **Cursor-as-focus gate:** decide whether cursor parking is always on,
   accessible-mode only, or controlled by a dedicated cursor policy.
4. **Public cursor-anchor modifier shape:** decide whether v1 exposes a
   modifier or only uses built-in anchors.
5. **Reduce-motion semantics:** define behavior for animations, spinners,
   progress views, transitions, and replacement update cadence.
6. **Linear renderer format:** decide layout reading order versus source order,
   side-by-side representation, and whether the implementation is a renderer or
   a semantic serializer.
7. **Live-region destination:** decide whether normal TUI drops live regions,
   writes stderr/status output, or only announces in accessible mode.

## Files

### Likely Modified

- `Sources/SwiftTUI/Configuration/RuntimeConfiguration.swift`
- `Sources/SwiftTUI/Configuration/EnvironmentResolver.swift`
- `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift`
- `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift`
- `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift`
- `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift`
- `Sources/SwiftTUI/Runtime/RunLoop.swift`
- `Sources/SwiftTUI/Runtime/RunLoop+Rendering.swift`
- `Sources/SwiftTUI/Terminal/TerminalHost.swift`
- `Sources/SwiftTUI/Terminal/TerminalPresentation.swift`
- `Sources/SwiftTUIViews/Controls/ProgressView.swift`
- `Sources/SwiftTUIViews/Controls/Spinner.swift`

### Likely Created

- `Sources/SwiftTUI/Accessibility/AccessibilityRuntimePolicy.swift`
- `Sources/SwiftTUI/Accessibility/LinearAccessibilityRenderer.swift`
- `Sources/SwiftTUI/Accessibility/LiveRegionAnnouncer.swift`
- `Tests/SwiftTUITests/AccessibilityRuntimePolicyTests.swift`
- `Tests/SwiftTUITests/LinearAccessibilityRendererTests.swift`
- `Tests/SwiftTUITests/LiveRegionAnnouncerTests.swift`

## Stage 1: Resolve Runtime Policy

- [ ] Create an ADR under `docs/decisions/` that answers every question in
  [Open Questions To Resolve First](#open-questions-to-resolve-first).
- [ ] Update this plan's later stages so each test expectation matches the ADR.
- [ ] Update `docs/proposals/ACCESSIBILITY.md` and
  `docs/proposals/SUBSTRATE_AUDIT.md` with a short policy-status note.
- [ ] Run `swiftly run swift test --filter SwiftTUITests.RuntimeConfigurationTests`
  and `swiftly run swift test --package-path Platforms/Arguments`.

## Stage 2: Normalize Runtime Configuration

- [ ] Add or update tests for env-var and CLI precedence in
  `Tests/SwiftTUITests/Configuration/EnvironmentResolverTests.swift` and
  `Platforms/Arguments/Tests/SwiftTUIArgumentsTests/SwiftTUIOptionsResolutionTests.swift`.
- [ ] Implement the ADR's precedence and implication rules in
  `RuntimeConfiguration.detect(...)` and `SwiftTUIOptions.runtimeConfiguration(...)`.
- [ ] Add focused tests for explicit opt-in and explicit opt-out cases.
- [ ] Run the configuration and arguments test suites.

## Stage 3: Add Cursor-As-Focus

- [ ] Add a runtime policy value that turns `AccessibilityNode.cursorAnchor`
  plus `FocusTracker.currentFocusIdentity` into an optional `CellPoint`.
- [ ] Keep the cursor point absolute in surface coordinates.
- [ ] Wire the point into terminal presentation after a committed frame, without
  changing pointer, key, or focus routing.
- [ ] Cover focused controls, missing anchors, hidden nodes, and unfocused
  frames with Swift tests.
- [ ] Run `swiftly run swift test --filter SwiftTUITests.FocusTransitionTests`
  and the new cursor policy tests.

## Stage 4: Add Linear Accessible Output

- [ ] Add a renderer that turns `SemanticSnapshot.accessibilityNodes` into the
  ADR-approved linear text format.
- [ ] Use authored labels first, then inferred labels already stored on
  `AccessibilityNode`, then role-only fallback text only if the ADR allows it.
- [ ] Route `RuntimeConfiguration.output == .accessible` through the linear
  renderer instead of the raster terminal renderer.
- [ ] Cover reading order, nested groups, controls without labels, and hidden
  subtrees.

## Stage 5: Add Motion And Progress Policy

- [ ] Apply `configuration.motion == .reduced` and `configuration.noProgress`
  at the lowest shared runtime/control boundary that satisfies the ADR.
- [ ] Keep normal-mode output unchanged.
- [ ] Cover progress views, spinners, repeated animations, and static controls
  with focused tests.

## Stage 6: Add Live-Region Announcements

- [ ] Track prior live-region content by accessibility identity across committed
  frames.
- [ ] Emit announcements only for changed live-region labels according to the
  ADR's destination and politeness rules.
- [ ] Cover first-frame suppression, polite/assertive ordering, removed nodes,
  and normal TUI behavior.

## Final Verification

```bash
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.LinearAccessibilityRendererTests
swiftly run swift test --filter SwiftTUITests.LiveRegionAnnouncerTests
swiftly run swift test
Scripts/generate_public_api_inventory.sh --check
bun run test
```
