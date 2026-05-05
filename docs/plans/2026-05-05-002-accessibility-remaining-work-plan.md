---
title: "feat: accessibility semantic substrate and current-state plan"
type: feat
status: completed
date: 2026-05-05
depends_on:
  - "../proposals/ACCESSIBILITY.md"
  - "../proposals/SUBSTRATE_AUDIT.md"
  - "../proposals/ARGUMENT_PARSING.md"
  - "../proposals/EMBEDDED_WEB_HOST.md"
  - "../decisions/0011-accessibility-role-replaces-presentation-role.md"
  - "../decisions/0012-accessibility-node-shape.md"
  - "2026-05-04-002-argument-parsing-plan.md"
---

# Accessibility Remaining Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for
> tracking. Keep commits scoped to stages that reach a green checkpoint. This
> plan touches public semantic surface and shared runtime data, so finish with
> `Scripts/generate_public_api_inventory.sh --check` and `bun run test` before
> calling the implementation complete.

**Goal:** Land the remaining unambiguous accessibility substrate work: one
public accessibility role channel, authoring metadata/modifiers, and
`SemanticSnapshot.accessibilityNodes` records that later CLI, web, WASM, and
SwiftUI host work can consume.

**Architecture:** Build the shared semantic substrate first and leave
target-specific behavior behind explicit follow-up decisions. `SwiftTUICore`
owns the public role enum, metadata fields, `AccessibilityNode`, and extractor
output. `SwiftTUIViews` owns the SwiftUI-shaped modifiers and built-in control
metadata. Runners and hosts consume the resulting snapshot later, after the
open policy questions in this document are resolved.

**Tech Stack:** Swift 6.3 strict concurrency, strict memory safety, Swift
Testing, `SwiftTUICore.SemanticExtractor`, `SwiftTUICore.SemanticMetadata`,
`SwiftTUIViews.SemanticMetadataModifier`, the public API inventory scripts, and
the repo-wide `bun run test` gate.

---

## Current State Snapshot

This plan started from the code as of 2026-05-05, not the first draft of
`ACCESSIBILITY.md`. The shared substrate work is now implemented; target
runtime behavior remains split into follow-up plans.

Already landed before this plan:

- `RuntimeConfiguration` exists in `Sources/SwiftTUI/Configuration/`.
- `RuntimeConfiguration.detect(environment:isStdoutTTY:)` handles
  `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `CI`,
  `SWIFTTUI_ACCESSIBLE`, `SWIFTTUI_ASCII`,
  `SWIFTTUI_REDUCE_MOTION`, `SWIFTTUI_PLAIN`,
  `SWIFTTUI_LINEAR`, `SWIFTTUI_NO_PROGRESS`, `SWIFTTUI_JSON`,
  and `SWIFTTUI_WEB`.
- `Platforms/Arguments/` ships `SwiftTUIOptions` and
  `SwiftTUIOptions.runtimeConfiguration(...)`.
- `--no-color`, `--force-color`, `--ascii`, and `--plain` reach the
  terminal renderer through `TerminalCapabilityProfile.applying(_:)`.
- The parser surface for `--accessible`, `--reduce-motion`, `--linear`,
  `--no-progress`, `--json`, and `--web` exists, but behavior is still
  mostly unwired.

Landed by this plan:

- `PresentationRole` is now `AccessibilityRole`, including the ADR-0011 role
  cases.
- `SemanticMetadata.presentationRole` is now
  `SemanticMetadata.accessibilityRole`.
- `presentationRole(_:)` is now `accessibilityRole(_:)`.
- `SemanticMetadata` stores accessibility label, hint, hidden,
  live-region, and package-only cursor-anchor metadata.
- `SwiftTUIViews` exposes accessibility metadata modifiers for role, label,
  hint, hidden, and live-region authoring.
- `SemanticSnapshot` carries `accessibilityNodes: [AccessibilityNode]`.
- `SemanticExtractor` emits pruned, parent-linked accessibility records.
- Public API baselines include `AccessibilityRole`,
  `AccessibilityPoliteness`, and `AccessibilityNode`, and remove
  `PresentationRole`.

Still follow-up work:

- CLI cursor-as-focus policy, accessible linear rendering, runtime live-region
  announcements, reduce-motion/no-progress behavior, embedded-host ARIA, WASM
  ARIA, and SwiftUI host bridging are not implemented by this plan.
- Follow-up target behavior is split into:
  - `docs/plans/2026-05-05-003-accessibility-cli-runtime-plan.md`
  - `docs/plans/2026-05-05-004-accessibility-web-aria-plan.md`
  - `docs/plans/2026-05-05-005-accessibility-swiftui-host-plan.md`

## Implementation Boundary

This plan deliberately implemented the shared substrate only. It did not
decide or implement:

- whether cursor-as-focus is always on or accessible-mode only;
- whether `--accessible` implies ASCII and reduce-motion;
- exact reduce-motion animation suppression rules;
- exact linear renderer format;
- embedded web host ARIA timing;
- visual-only content lint policy.

Those are listed in [Open Questions](#open-questions). Do not smuggle policy
answers into this substrate patch.

## Files

### Created

- `Tests/SwiftTUICoreTests/AccessibilityRoleTests.swift`
- `Tests/SwiftTUICoreTests/AccessibilityNodeExtractionTests.swift`
- `Tests/SwiftTUIViewsTests/AccessibilityMetadataModifierTests.swift`
- `docs/plans/2026-05-05-003-accessibility-cli-runtime-plan.md`
- `docs/plans/2026-05-05-004-accessibility-web-aria-plan.md`
- `docs/plans/2026-05-05-005-accessibility-swiftui-host-plan.md`

### Modified

- `Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`
- `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
- `Sources/SwiftTUICore/Semantics/SemanticSnapshot.swift`
- `Sources/SwiftTUICore/Semantics/Semantics.swift`
- `Sources/SwiftTUICore/Semantics/FocusPolicy.swift`
- `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`
- Built-in role authors under:
  - `Sources/SwiftTUIViews/Controls/`
  - `Sources/SwiftTUIViews/Input/`
  - `Sources/SwiftTUIViews/NavigationViews/`
  - `Sources/SwiftTUIViews/ScrollView/`
  - `Sources/SwiftTUIViews/Collections/`
  - `Sources/SwiftTUIViews/Presentation/`
- Existing tests that reference `PresentationRole`, `presentationRole`, or
  `presentationRole(_:)`.
- `docs/PUBLIC_API_BASELINE.md`
- `docs/.public-api-baseline.txt`
- `docs/proposals/ACCESSIBILITY.md`
- `docs/proposals/SUBSTRATE_AUDIT.md`
- `Sources/SwiftTUI/SwiftTUI.docc` / `Sources/SwiftTUICore/SwiftTUICore.docc`
  files only if symbol docs need new landing text after implementation.

## Stage 1: Rename And Extend The Role Channel

ADR-0011 is accepted. Implement it before adding new metadata so later stages
do not need to support both names.

### Task 1.1: Add role-surface characterization tests

- [x] Create `Tests/SwiftTUICoreTests/AccessibilityRoleTests.swift`.
- [x] Cover these cases:
  - `AccessibilityRole.button.description == "button"`.
  - `AccessibilityRole.secureField.description == "secureField"`.
  - `AccessibilityRole.heading(level: 2).description == "heading(level: 2)"`.
  - `AccessibilityRole.custom("chart").description == "custom(chart)"`.
  - `SemanticMetadata(accessibilityRole: .button).accessibilityRole == .button`.
- [x] Run:

```bash
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests
```

Expected before implementation: compile failure because `AccessibilityRole`
does not exist.

### Task 1.2: Rename `PresentationRole` to `AccessibilityRole`

- [x] In `Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`, rename
  `PresentationRole` to `AccessibilityRole`.
- [x] Keep the existing cases and add the ADR-0011 cases:
  `secureField`, `checkbox`, `image`, `progressBar`, `timer`,
  `heading(level:)`, `status`, `region`, `separator`, `columnHeader`,
  `rowHeader`, `cell`, `menuItem`, `tab`, `tabPanel`, `group`,
  `custom(String)`.
- [x] In `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`, rename
  `SemanticMetadata.presentationRole` to `accessibilityRole`, including both
  initializers and `merging(_:)`.
- [x] In `Sources/SwiftTUICore/Semantics/FocusPolicy.swift`, rename
  `focusablePresentationRoles` to `focusableAccessibilityRoles` and read
  `metadata.accessibilityRole`.
- [x] In `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`, rename
  `presentationRole(_:)` to `accessibilityRole(_:)`.
- [x] Update all built-in role authors to write `accessibilityRole`.
- [x] Change `SecureField` from `.textField` to `.secureField`.

### Task 1.3: Update role references and run focused tests

- [x] Replace test and doc references that assert source symbols:
  `PresentationRole`, `presentationRole`, and `presentationRole(_:)`.
- [x] Keep historical prose in `SUBSTRATE_AUDIT.md` as historical where it
  describes the pre-ADR audit, but add an implementation-status note when this
  stage lands.
- [x] Run:

```bash
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests
swiftly run swift test --filter SwiftTUITests.MenuSurfaceTests
swiftly run swift test --filter SwiftTUITests.InteractiveRuntimeTests
swiftly run swift test --filter SwiftTUITests.ViewCompositionSurfaceTests
swiftly run swift test --filter SwiftTUITests.TabViewSurfaceTests
```

Expected after implementation: all pass.

### Task 1.4: Refresh public API inventory

- [x] Run:

```bash
Scripts/generate_public_api_inventory.sh
Scripts/generate_public_api_inventory.sh --check
```

- [x] Confirm the baseline removes `SwiftTUICore.PresentationRole` and adds
  `SwiftTUICore.AccessibilityRole`.
- [x] Commit:

```bash
git add Sources Tests docs/PUBLIC_API_BASELINE.md docs/.public-api-baseline.txt docs/proposals
git commit -m "feat: rename presentation roles to accessibility roles"
```

## Stage 2: Add Authoring Metadata And Modifiers

This is ACCESSIBILITY.md Phase 3a minus the public cursor-anchor modifier. The
cursor-anchor node field is in ADR-0012; the exact public modifier argument
type is still an open question.

### Task 2.1: Add metadata storage tests

- [x] Create `Tests/SwiftTUIViewsTests/AccessibilityMetadataModifierTests.swift`.
- [x] Test direct metadata storage and merge precedence:
  - authored label overrides nil;
  - authored hint overrides nil;
  - `accessibilityHidden` merges from `false` to `true`;
  - `accessibilityLiveRegion` merges when set.
- [x] Run:

```bash
swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests
```

Expected before implementation: compile failure because the fields and enum do
not exist.

### Task 2.2: Add metadata fields

- [x] Add `AccessibilityPoliteness` in
  `Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`:
  `off`, `polite`, `assertive`.
- [x] Add these fields to `SemanticMetadata`:
  - `accessibilityLabel: String?`
  - `accessibilityHint: String?`
  - `accessibilityHidden: Bool`
  - `accessibilityLiveRegion: AccessibilityPoliteness?`
- [x] Update `SemanticMetadata` public and package initializers with defaults:
  label nil, hint nil, hidden false, live region nil.
- [x] Update `SemanticMetadata.merging(_:)` so non-nil label/hint/live-region
  values override and hidden merges with logical OR.

### Task 2.3: Add authoring modifiers

- [x] In `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift`, add:
  - `accessibilityLabel(_ label: String) -> some View`
  - `accessibilityHint(_ hint: String) -> some View`
  - `accessibilityHidden(_ hidden: Bool = true) -> some View`
  - `accessibilityLiveRegion(_ politeness: AccessibilityPoliteness) -> some View`
- [x] Implement each modifier through `SemanticMetadataModifier`, matching
  existing metadata modifier patterns.
- [x] Run:

```bash
swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests
swiftly run swift test --filter SwiftTUITests.MenuSurfaceTests
```

Expected after implementation: all pass.

### Task 2.4: Refresh public API inventory

- [x] Run:

```bash
Scripts/generate_public_api_inventory.sh
Scripts/generate_public_api_inventory.sh --check
```

- [x] Commit:

```bash
git add Sources Tests docs/PUBLIC_API_BASELINE.md docs/.public-api-baseline.txt
git commit -m "feat: add accessibility metadata modifiers"
```

## Stage 3: Emit `AccessibilityNode` Records

ADR-0012 is accepted. Implement the structural snapshot without cursor policy
or host-specific consumption.

### Task 3.1: Add extraction tests

- [x] Create `Tests/SwiftTUICoreTests/AccessibilityNodeExtractionTests.swift`.
- [x] Cover these behaviors through `DefaultRenderer` or a directly
  constructed placed tree, whichever matches nearby tests best:
  - button role emits one node with label inferred from rendered text;
  - explicit `accessibilityLabel` wins over inferred text;
  - `accessibilityHidden(true)` skips the node and descendants;
  - a group ancestor is emitted when needed to preserve parent identity for an
    emitted descendant;
  - focus-chain nodes are emitted even when they have no authored label;
  - node order follows layout reading order.
- [x] Run:

```bash
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
```

Expected before implementation: compile failure because `AccessibilityNode`
and `SemanticSnapshot.accessibilityNodes` do not exist.

### Task 3.2: Add the public snapshot types

- [x] In `Sources/SwiftTUICore/Semantics/SemanticSnapshot.swift`, add:
  - `public struct AccessibilityNode: Equatable, Sendable`
  - fields exactly as ADR-0012 specifies:
    `identity`, `parentIdentity`, `rect`, `role`, `label`, `hint`,
    `hidden`, `liveRegion`, `cursorAnchor`.
- [x] Add `public var accessibilityNodes: [AccessibilityNode]` to
  `SemanticSnapshot` with a default empty array.
- [x] Update all explicit `SemanticSnapshot(...)` construction sites to pass
  through the default unless the test specifically inspects accessibility
  records.

### Task 3.3: Extend `SemanticExtractor`

- [x] Keep transient-node skipping exactly as it works today.
- [x] Skip any `accessibilityHidden(true)` subtree.
- [x] Emit nodes when ADR-0012 says they are relevant:
  role, label, hint, live-region, focus-chain participation, cursor anchor, or
  structural ancestor of a relevant descendant.
- [x] Infer roles in this order:
  authored/built-in `accessibilityRole`, then `.group` for structural
  ancestors, otherwise no emitted node.
- [x] Infer labels in this order:
  authored `accessibilityLabel`, then rendered text for button/link/tab/menu
  item/heading roles, then tab item label title for tab-related nodes, otherwise
  nil.
- [x] Keep focus state out of `AccessibilityNode`. Consumers cross-reference
  `FocusTracker.currentFocusIdentity`.

### Task 3.4: Run focused semantic tests

- [x] Run:

```bash
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
swiftly run swift test --filter SwiftTUICoreTests.FocusPresentationTests
swiftly run swift test --filter SwiftTUITests.GestureRunLoopDispatchTests
swiftly run swift test --filter SwiftTUITests.KeyCommandTests
```

Expected after implementation: all pass, with no changes to existing focus,
pointer, scroll, or selection routing behavior.

### Task 3.5: Refresh public API inventory

- [x] Run:

```bash
Scripts/generate_public_api_inventory.sh
Scripts/generate_public_api_inventory.sh --check
```

- [x] Commit:

```bash
git add Sources Tests docs/PUBLIC_API_BASELINE.md docs/.public-api-baseline.txt
git commit -m "feat: emit accessibility nodes from semantic snapshots"
```

## Stage 4: Documentation And Status Cleanup

Update docs after the substrate code lands so the docs describe shipped
behavior rather than planned behavior.

- [x] Update `docs/proposals/ACCESSIBILITY.md`:
  - mark argument parsing/env resolution as landed;
  - mark role rename as implemented;
  - mark metadata modifiers as implemented;
  - mark `SemanticSnapshot.accessibilityNodes` as implemented;
  - keep cursor policy, linear renderer, live announcer, ARIA, WASM, and
    SwiftUI host bridge as follow-up work.
- [x] Update `docs/proposals/SUBSTRATE_AUDIT.md`:
  - preserve the audit as historical truth;
  - add a short implementation-status note pointing to the completed stages.
- [x] Update DocC only if public symbols need discoverability text.
- [x] Run:

```bash
swiftly run swift test
Scripts/generate_public_api_inventory.sh --check
bun run test
```

- [x] Commit:

```bash
git add docs Sources Tests
git commit -m "docs: mark accessibility substrate status"
```

## Stage 5: Follow-Up Plan Split

After Stages 1-4 land, create separate plans for target behavior. Do not add
them to this substrate patch.

- [x] `docs/plans/2026-05-05-003-accessibility-cli-runtime-plan.md`
  - cursor-as-focus policy;
  - accessible linear renderer;
  - reduce-motion/no-progress behavior;
  - live-region announcer for CLI.
- [x] `docs/plans/2026-05-05-004-accessibility-web-aria-plan.md`
  - `web-surface` v2 `accessibilityTree`;
  - browser DOM mounter;
  - focus sync and live regions.
- [x] `docs/plans/2026-05-05-005-accessibility-swiftui-host-plan.md`
  - map `AccessibilityNode` to SwiftUI accessibility modifiers;
  - native focus and announcement integration.

Each follow-up plan must start by resolving the relevant open questions below.

## Open Questions

These questions are intentionally outside the unambiguous substrate plan. They
must be resolved before implementing target-specific behavior.

1. **Output precedence for env vars.** CLI flags currently resolve
   `--accessible` before `--json`, but `RuntimeConfiguration.detect` lets
   `SWIFTTUI_JSON=1` override `SWIFTTUI_ACCESSIBLE=1`. Pick one rule before
   wiring either output mode to behavior.

2. **Does accessible mode imply ASCII and reduce-motion?** Current code sets
   only `output = .accessible`. Decide whether `--accessible` and
   `SWIFTTUI_ACCESSIBLE=1` should also imply ASCII, reduced motion, no
   progress, and linear layout, and decide whether explicit overrides can
   opt back out.

3. **Cursor-as-focus gate.** Decide whether the terminal cursor should always
   be parked at the focused anchor, only in accessible mode, or only when a
   dedicated cursor policy is enabled.

4. **Public cursor-anchor modifier shape.** ADR-0012 locks the node field as
   absolute `CellPoint?`, but the public modifier argument is not fully
   specified. Decide between `CellPoint`, an enum such as
   `AccessibilityCursorAnchor`, or role-specific built-in anchors plus no
   public modifier in v1.

5. **Reduce-motion semantics.** Decide what "reduced" means for
   `Animation`, spinners, progress bars, transitions, and content changes that
   would otherwise animate. The replacement cadence for progress updates must
   be explicit.

6. **Linear renderer format.** Decide whether linear mode follows layout
   reading order or source order, how it represents side-by-side layout, and
   whether it is a renderer, a semantic snapshot serializer, or a separate
   output mode.

7. **Live-region destination in normal TUI mode.** Decide whether live-region
   announcements are dropped, appended to a status region, written to stderr,
   or only enabled under accessible mode.

8. **Embedded web host ARIA timing.** Decide whether `accessibilityTree` is
   required for the first usable embedded host or lands immediately after the
   basic browser renderer. The substrate plan only makes the data available.

9. **Visual-only content policy.** Decide how `Canvas`, images, braille art,
   and `SwiftTUICharts` are exposed when they lack labels or textual
   summaries: hidden, lint error, runtime warning, or fallback text.

10. **Documentation home after implementation.** Decide whether
    `ACCESSIBILITY.md` remains a proposal or whether shipped substrate details
    move into durable reference docs such as `RUNTIME.md`,
    `PUBLIC_API_INVENTORY.md`, and a new `docs/ACCESSIBILITY.md`.

## Final Verification

The complete substrate implementation is not done until all of these pass:

```bash
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityRoleTests
swiftly run swift test --filter SwiftTUIViewsTests.AccessibilityMetadataModifierTests
swiftly run swift test --filter SwiftTUICoreTests.AccessibilityNodeExtractionTests
swiftly run swift test
Scripts/generate_public_api_inventory.sh --check
bun run test
```

Verification result on 2026-05-05:

- `swiftly run swift test` passed after clearing stale SwiftPM build products.
- `Scripts/generate_public_api_inventory.sh --check` passed with 568 top-level
  public symbols.
- `bun run test` passed across root, peer packages, examples, and tooling.
  Full log: `/tmp/swift-tui-test-all-20260505-185319-19154.log`.
