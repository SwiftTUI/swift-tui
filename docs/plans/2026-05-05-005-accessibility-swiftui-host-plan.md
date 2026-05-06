---
title: "feat: accessibility SwiftUI host bridge"
type: feature
status: shipped
date: 2026-05-05
depends_on:
  - "2026-05-05-002-accessibility-remaining-work-plan.md"
  - "2026-05-05-003-accessibility-cli-runtime-plan.md"
  - "../proposals/ACCESSIBILITY.md"
  - "../proposals/SUBSTRATE_AUDIT.md"
  - "../decisions/0012-accessibility-node-shape.md"
  - "../decisions/0015-accessibility-swiftui-host-policy.md"
---

# Accessibility SwiftUI Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Do not implement stages after Stage 1 until the native-focus and
> announcement decisions are written down.

**Goal:** Make `Platforms/SwiftUI` expose hosted SwiftTUI content to native
Apple accessibility APIs by translating `AccessibilityNode` records into
SwiftUI accessibility modifiers, semantic focus metadata, and announcements.

**Architecture:** Keep hosted rendering raster-based, but carry semantic data
beside `RasterSurface` through `HostedSceneSession` into `SwiftUIHostSceneHost`.
The SwiftUI host owns platform translation; core semantics remain platform
agnostic, and terminal runtime cursor policy is not reused directly.

**Tech Stack:** Swift 6.3 strict concurrency, SwiftUI, Observation, Swift
Testing, `HostedSceneSession`, `SwiftUIHostSceneHost`,
`NativeTerminalSurfaceView`, `SemanticSnapshot.accessibilityNodes`, and
`FocusTracker.currentFocusIdentity`.

---

## Resolved Native Host Policy

[`ADR-0015`](../decisions/0015-accessibility-swiftui-host-policy.md)
answers the initial open questions for this tranche:

1. **Native focus mapping:** v1 marks the matching accessibility node as
   the focused semantic target, but does not programmatically move global
   VoiceOver focus.
2. **Announcement mapping:** the host uses the same identity-based
   live-region diff as CLI and Web/WASI: first-frame suppression,
   assertive before polite, `.off` ignored, then platform announcements.
3. **Role mapping:** map every `AccessibilityRole` into a host-owned
   trait/value model before applying SwiftUI modifiers; custom roles keep
   their string as a role description without invented native traits.
4. **Hit testing:** native accessibility frames come from `CellRect`
   converted through the current native cell size; zero or invalid rects
   are skipped.
5. **Visual-only content policy:** expose unlabeled nodes with their
   role/trait when they exist in the semantic snapshot, but do not guess
   labels for content absent from `SemanticSnapshot.accessibilityNodes`.

## Original Open Questions

1. **Native focus mapping:** decide whether the host exposes a single focused
   accessibility element, per-node focus bindings, or only labels/traits in v1.
2. **Announcement mapping:** decide how `AccessibilityPoliteness` maps to
   Apple-platform announcements and whether first-frame live regions announce.
3. **Role mapping:** decide exact SwiftUI traits/modifiers for every
   `AccessibilityRole`, including custom roles.
4. **Hit testing:** decide whether accessibility elements use cell rects
   converted through pixel metrics or expose order-only elements in v1.
5. **Visual-only content policy:** decide whether unlabeled visual nodes are
   hidden, warned about, or exposed as role-only elements.

## Files

### Likely Modified

- `Sources/SwiftTUI/Scenes/HostedSceneSession.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/NativeSceneBridge.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/NativeTerminalSurfaceView.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/`
- `docs/proposals/ACCESSIBILITY.md`
- `docs/proposals/SUBSTRATE_AUDIT.md`

### Likely Created

- `Platforms/SwiftUI/Sources/SwiftUIHost/AccessibilityNodeMapping.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift`
- `Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityAnnouncer.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/AccessibilityNodeMappingTests.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityAnnouncerTests.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/HostedAccessibilityOverlayTests.swift`
- `Platforms/SwiftUI/Tests/SwiftUIHostTests/SwiftUIHostAccessibilityTests.swift`

## Stage 1: Resolve Native Host Policy

- [x] Create an ADR under `docs/decisions/` that answers every question in
  [Original Open Questions](#original-open-questions).
- [x] Update this plan's role, focus, hit-testing, and live-region expectations
  to match the ADR.
- [x] Update `docs/proposals/ACCESSIBILITY.md` with a SwiftUI-host status note.
- [x] Run `swiftly run swift test --package-path Platforms/SwiftUI`.

## Stage 2: Carry Semantic Snapshots Into The Host

- [x] Extend `HostedSceneSession` callbacks so host packages receive committed
  `SemanticSnapshot` data beside the raster surface.
- [x] Preserve the existing `onSurface` callback for callers that only need
  raster output.
- [x] Add tests that prove `SwiftUIHostSceneHost` stores the latest semantic
  snapshot and updates it when new frames commit.

## Stage 3: Map Roles, Labels, Hints, And Hidden State

- [x] Create `AccessibilityNodeMapping.swift` with pure mapping functions from
  `AccessibilityNode` to SwiftUI-host accessibility values.
- [x] Cover every `AccessibilityRole` case with tests.
- [x] Ensure `accessibilityHidden(true)` subtrees remain absent because the
  extractor already prunes them.

## Stage 4: Build The Hosted Accessibility Overlay

- [x] Create an overlay view that positions native accessibility elements over
  the raster terminal view using cell rects and current cell-pixel metrics.
- [x] Keep visual rendering unchanged.
- [x] Cover resize, node removal, group nesting, and empty trees.

## Stage 5: Sync Native Focus And Announcements

- [x] Cross-reference the host's focused identity with the latest accessibility
  nodes according to the ADR's native-focus rule.
- [x] Add live-region announcement handling using the ADR-approved mapping.
- [x] Cover focus movement, removed focused nodes, polite/assertive live
  regions, and unchanged live-region labels.

## Final Verification

```bash
swiftly run swift test --package-path Platforms/SwiftUI
swiftly run swift test
bun run test --skip-bun-install
```
