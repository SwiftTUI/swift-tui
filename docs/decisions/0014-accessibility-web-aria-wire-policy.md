---
adr: "0014"
title: "Accessibility web ARIA wire policy"
status: accepted
date: 2026-05-06
sources:
  - docs/proposals/ACCESSIBILITY.md
  - docs/proposals/EMBEDDED_WEB_HOST.md
  - docs/proposals/SUBSTRATE_AUDIT.md
  - docs/plans/2026-05-05-004-accessibility-web-aria-plan.md
  - docs/decisions/0012-accessibility-node-shape.md
  - docs/decisions/0013-accessibility-runtime-policy.md
  - Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift
  - Platforms/Web/src/WebHostSurfaceTransport.ts
---

# ADR-0014: Accessibility web ARIA wire policy

## Context

ADR-0011 through ADR-0013 established the shared accessibility substrate
and terminal runtime policy. The remaining Web/WASI work needs a stable
wire and browser policy before implementation: whether ARIA is part of
the first usable accessibility web bridge, how the `web-surface`
envelope versions the semantic payload, how focus is serialized, where
live-region announcements are mounted, and what the browser does with
visual-only content.

The existing `web-surface` frame is raster-only. It sends cells,
styles, and image records, but not roles, labels, hints, live regions,
or focus state. Browser accessibility therefore requires an additive
semantic payload beside the raster rows.

## Decision

`accessibilityTree` is required for the first usable Web/WASI
accessibility bridge. A browser surface without ARIA remains a visual
renderer only; it does not satisfy the accessibility goal of the
embedded host or WASM web target.

Adding `accessibilityTree` bumps the `web-surface` frame envelope from
`version: 1` to `version: 2` when semantic data is present. The new
field is backward-additive: older clients ignore unknown fields, and
newer clients continue to accept `version: 1` frames or `version: 2`
frames with no `accessibilityTree` as raster-only frames.

Swift encodes focus directly on each accessibility node as
`isFocused: true` when the node identity matches the focused identity
for that committed frame. The browser does not derive focus from a
separate top-level focused identity. This keeps each frame
self-contained and avoids stale browser-side focus reconstruction when
nodes are removed or reordered.

Live regions are mounted through one dedicated offscreen announcer
region owned by the browser runtime. The accessibility tree still
preserves each node's `liveRegion` value for inspection and native
semantics, but screen-reader announcements are driven by changed labels
by identity, using the same first-frame suppression and assertive-before-polite
ordering as ADR-0013. `.off` suppresses announcements.

Visual-only content is not guessed into labels in v1. If the semantic
snapshot emits an unlabeled visual node, the browser maps the available
role and geometry but does not invent accessible text. If content is
absent from the semantic snapshot, the browser keeps it hidden from the
accessibility tree. Future lint can warn about unlabeled canvas,
images, charts, and braille art, but the transport and browser mounter
must not synthesize misleading labels.

## Status

Accepted on 2026-05-06. Stage 1 of
`2026-05-05-004-accessibility-web-aria-plan.md` depends on this ADR.

## Consequences

`WebSurfaceFrameEncoder` needs an accessibility-aware overload that can
emit `version: 2` frames with stable node JSON fields, while preserving
the existing raster-only overload for callers without semantic data.
The TypeScript transport must parse both versions. The browser runtime
needs an offscreen ARIA tree mounter plus a dedicated live-region
announcer and must keep the visual raster layout unchanged.
