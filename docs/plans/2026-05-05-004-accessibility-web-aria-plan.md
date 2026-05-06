---
title: "feat: accessibility web and WASM ARIA bridge"
type: feat
status: proposed
date: 2026-05-05
depends_on:
  - "2026-05-05-002-accessibility-remaining-work-plan.md"
  - "2026-05-05-003-accessibility-cli-runtime-plan.md"
  - "../proposals/ACCESSIBILITY.md"
  - "../proposals/SUBSTRATE_AUDIT.md"
  - "../proposals/EMBEDDED_WEB_HOST.md"
  - "../decisions/0012-accessibility-node-shape.md"
  - "../decisions/0014-accessibility-web-aria-wire-policy.md"
---

# Accessibility Web ARIA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Stage 1 resolved the ARIA timing and wire-format decisions in
> ADR-0014; later stages must match that policy.

**Goal:** Carry `SemanticSnapshot.accessibilityNodes` through the shared
`web-surface` protocol and mount a browser-side accessibility tree with ARIA
roles, labels, hints, focus state, and live regions.

**Architecture:** Extend the existing WASI/Web `web-surface` frame instead of
creating a second transport. Swift encodes accessibility data beside raster
rows; TypeScript reconstructs the flat parent-linked tree into DOM nodes that
track the rendered surface. The embedded web host and WASI browser target share
the same encoder and browser mounter.

**Tech Stack:** Swift 6.3, Swift Testing, Bun tests, `WASISurfaceBridge`,
`WebSurfaceFrameEncoder`, `Platforms/Web` TypeScript runtime,
`SemanticSnapshot.accessibilityNodes`, and browser ARIA/live-region APIs.

---

## Open Questions To Resolve First

1. **ARIA timing:** decide whether `accessibilityTree` is required for the first
   usable embedded host or can land immediately after the basic browser
   renderer. Decision: required for the first usable accessibility web bridge.
2. **Wire-format versioning:** decide whether adding `accessibilityTree`
   increments `web-surface` from version 1 to version 2 and how old clients
   ignore the field. Decision: semantic frames use `version: 2`;
   raster-only frames remain accepted, and unknown fields are ignored.
3. **Focus serialization:** decide whether Swift encodes `isFocused` directly
   or the browser computes it from a separate focused identity field.
   Decision: Swift encodes per-node `isFocused`.
4. **Live-region mounting:** decide whether live regions are represented as
   hidden sibling nodes, attributes on visible nodes, or a dedicated announcer
   region. Decision: a dedicated offscreen browser announcer owns
   announcements; tree nodes still carry `liveRegion` for semantics.
5. **Visual-only content policy:** decide the browser behavior for unlabeled
   canvas, images, charts, and braille art. Decision: do not guess labels in
   v1; expose only semantic facts the snapshot carries.

## Files

### Likely Modified

- `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`
- `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceTransportTests.swift`
- `Platforms/Web/src/WebHostSurfaceTransport.ts`
- `Platforms/Web/src/WebHostSurfaceTransport.test.ts`
- `Platforms/Web/src/WebHostSceneRuntime.ts`
- `Platforms/Web/src/WebHostSceneRuntime.test.ts`
- `Platforms/Web/src/browser.ts`
- `Examples/WebExample/src/frontend.ts`
- `docs/proposals/EMBEDDED_WEB_HOST.md`

### Likely Created

- `Platforms/Web/src/AccessibilityTree.ts`
- `Platforms/Web/src/AccessibilityTree.test.ts`
- `Platforms/WASI/Tests/WASISurfaceBridgeTests/WebSurfaceAccessibilityTests.swift`

## Stage 1: Resolve ARIA And Wire Policy

- [x] Create an ADR under `docs/decisions/` that answers every question in
  [Open Questions To Resolve First](#open-questions-to-resolve-first).
- [x] Update `docs/proposals/EMBEDDED_WEB_HOST.md` so Phase 6 references the
  accepted wire-format and ARIA strategy.
- [x] Update this plan's encoding and TypeScript test expectations to match the
  ADR.
- [x] Run `(cd Platforms/Web && bun run test)` and
  `swiftly run swift test --package-path Platforms/WASI`.

## Stage 2: Encode Accessibility In `web-surface`

- [ ] Add Swift tests that encode a raster surface with an accessibility tree
  containing a button, a labeled group, a live region, and a focused node.
- [ ] Extend `WebSurfaceFrameEncoder.encode(...)` with an overload that accepts
  `SemanticSnapshot` and focused identity context.
- [ ] Encode `AccessibilityNode` fields with stable JSON names:
  `id`, `parentId`, `rect`, `role`, `label`, `hint`, `liveRegion`,
  `cursorAnchor`, and `isFocused`.
- [ ] Emit `version: 2` when `accessibilityTree` is present, while accepting
  raster-only v1 frames.
- [ ] Keep the existing raster-only `encode(_ surface:)` overload working for
  callers that do not have semantic data.

## Stage 3: Decode And Mount Browser Accessibility

- [ ] Add TypeScript tests for parsing frames with and without
  `accessibilityTree`.
- [ ] Create `AccessibilityTree.ts` to map Swift role strings to ARIA roles and
  attributes.
- [ ] Use one dedicated offscreen announcer for live-region announcements
  rather than relying on visible raster cells.
- [ ] Mount accessibility DOM nodes beside the rendered surface without changing
  raster cell layout.
- [ ] Preserve parent-child order from the flat array and ignore missing parent
  references defensively.

## Stage 4: Sync Focus And Live Regions

- [ ] Update browser runtime focus state when a new frame identifies a focused
  accessibility node.
- [ ] Apply live-region politeness according to the ADR.
- [ ] Cover focus movement, node removal, first-frame live-region behavior, and
  repeated unchanged announcements.

## Stage 5: Wire Embedded Host And WASI Examples

- [ ] Route committed semantic snapshots to the web-surface encoder in the
  embedded host and WASI runner paths.
- [ ] Update `Examples/WebExample` to mount the browser accessibility tree.
- [ ] Add one end-to-end test fixture that proves a rendered button produces a
  browser-side role and label.

## Final Verification

```bash
swiftly run swift test --package-path Platforms/WASI
(cd Platforms/Web && bun run test)
bun run test
```
