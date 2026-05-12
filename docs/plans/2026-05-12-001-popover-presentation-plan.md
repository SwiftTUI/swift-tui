---
title: "feat: anchored popover presentation API"
type: feature
status: shipped
date: 2026-05-12
proposal: "../proposals/POPOVER_PRESENTATION_API.md"
---

# feat: anchored popover presentation API

## Overview

Ship the popover-oriented `docs/TODO.md` item by turning the draft proposal into
stable public API, implementing anchored placement, adding focused runtime tests,
and adding a gallery example once the API is stable.

The API follows SwiftUI's current shape:

- `popover(isPresented:attachmentAnchor:arrowEdge:content:)`
- `popover(item:attachmentAnchor:arrowEdge:content:)`
- `popoverTip(_:isPresented:attachmentAnchor:arrowEdge:action:)`

`popoverTip` is TipKit-inspired only at the call site. It does not add a tip rule
engine, event donation, persistence, or display frequency management.

## Acceptance Criteria

- Boolean and item-driven popovers render as compact source-anchored overlays.
- `PopoverAttachmentAnchor.rect(.bounds)` and `.point(...)` are public and
  source-compatible with SwiftUI-shaped call sites.
- `arrowEdge: nil` selects an edge that fits; explicit edges flip or fall back
  before clamping.
- Popovers are modal by default: base focus/routes are gated and Escape dismisses
  the topmost popover.
- Read-only tips can be non-modal, while tips with actions use the same
  presentation action scope and dismissal path as popovers.
- Public API baseline and docs are refreshed.
- The gallery example has a concrete popover tab.
- `bun run test` passes before the final commit.

## Implementation Stages

1. Stabilize the proposal and public API names around `arrowEdge: Edge?`.
2. Add public unit-rect anchor support and popover/tip public types.
3. Add a popover coordinator family beside alert, sheet, menu, and toast.
4. Host popover content through the existing portal/overlay/dismiss stack, with
   a `GeometryReader`-backed placement layout that resolves the source frame
   after base placement.
5. Add focused tests for source-relative placement, edge fallback, modal gating,
   Escape dismissal, item popovers, and tip eligibility/action dismissal.
6. Add a gallery popover tab and package-local tests.
7. Close the TODO item, record the changelog entry, regenerate public API
   artifacts, run verification, and commit the finished change.

## Shipped Notes

- Public API shipped as SwiftUI-shaped `popover` overloads plus the
  TipKit-inspired `popoverTip` convenience.
- Read-only tips use non-modal popover chrome; popovers and tips with actions
  gate base interaction and participate in Escape dismissal.
- The gallery app includes a `Popovers` tab that demonstrates Boolean, item,
  and tip presentation.
