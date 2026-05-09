---
adr: "0015"
title: "Accessibility SwiftUI host policy"
status: accepted
date: 2026-05-06
sources:
  - docs/proposals/ACCESSIBILITY.md
  - docs/proposals/SUBSTRATE_AUDIT.md
  - docs/plans/2026-05-05-005-accessibility-swiftui-host-plan.md
  - docs/decisions/0012-accessibility-node-shape.md
  - docs/decisions/0013-accessibility-runtime-policy.md
  - docs/decisions/0014-accessibility-web-aria-wire-policy.md
  - Platforms/SwiftUI/Sources/SwiftUIHost/SwiftUIHostSceneHost.swift
---

# ADR-0015: Accessibility SwiftUI host policy

## Context

ADR-0012 gives all non-terminal consumers a sparse flat
`AccessibilityNode` list. ADR-0013 and ADR-0014 establish focus and
live-region behavior for CLI and Web/WASI consumers. The SwiftUI host
still needs native Apple-platform policy before implementation because
its visual surface is raster based while VoiceOver needs native
accessibility elements with labels, traits, frames, focus state, and
announcements.

## Decision

The SwiftUI host keeps raster rendering as the visual layer and mounts
a nonvisual SwiftUI accessibility overlay beside it. The overlay exposes
one native accessibility element per `AccessibilityNode`, preserving the
snapshot's layout-reading order and parent-child grouping where possible.
The raster terminal view itself is hidden from assistive technology so
screen readers do not traverse duplicate character-grid content.

SwiftUI host focus moves native accessibility focus by default. The
host cross-references the latest runtime focused identity with the
current `AccessibilityNode` mappings and writes the matching overlay
element ID into a host-owned `AccessibilityFocusState`. If the focused
node is removed, the host clears the native accessibility focus request
for that frame.

This is a one-way runtime-to-native focus bridge in this tranche.
VoiceOver user traversal does not yet mutate SwiftTUI runtime focus
because that requires a separate interaction contract for mapping native
accessibility focus changes back into `FocusTracker` without
synthesizing misleading pointer or keyboard input.

Live regions use a host-owned announcement diff with the same rules as
ADR-0013 and ADR-0014: the first frame establishes baseline text,
changes are compared by node identity, `.off` is ignored, and assertive
announcements are delivered before polite announcements. The production
host posts resulting messages through platform announcement APIs; tests
exercise the platform-independent diff.

Roles map to a small native trait/value model before SwiftUI modifiers
are applied. Activating roles (`button`, `menuItem`, `tab`,
`disclosureGroup`) use button traits; `link` uses link traits;
`heading`, `columnHeader`, and `rowHeader` use header traits; `image`
uses image traits; text-entry roles (`textField`, `secureField`,
`textEditor`) use text-field values where the platform exposes them and
otherwise label/hint only; adjustable roles (`slider`, `stepper`,
`progressBar`) use adjustable/value-style metadata without inventing
values; structural roles (`group`, `region`, `section`, `list`,
`table`, `tableRow`, `cell`, `menu`, `picker`, `tabView`, `tabPanel`,
`scrollView`, `scrollViewWithIndicators`, `sheet`,
`confirmationDialog`, `alert`, `status`, `timer`, `separator`) are
exposed as grouped or static elements with their labels and hints.
`custom(String)` keeps the string as a role description but does not
invent a native trait.

Hit testing and accessibility frames come from cell geometry. Each
node's `CellRect` is converted through the current native host cell
size; zero or invalid rectangles are skipped. The host does not fall
back to order-only elements in v1 because order-only elements would
make touch exploration misleading on Apple platforms.

Visual-only content is not guessed. Unlabeled nodes remain exposed with
their role/trait when they are present in the semantic snapshot; content
absent from `SemanticSnapshot.accessibilityNodes` stays absent from the
native accessibility tree. Future lint can warn about important
unlabeled widgets, images, charts, or braille art, but the host must not
synthesize misleading labels.

## Status

Accepted on 2026-05-06. Stage 1 of
`2026-05-05-005-accessibility-swiftui-host-plan.md` depends on this ADR.

## Consequences

The implementation should first carry `SemanticSnapshot` data beside
`RasterSurface` through `HostedSceneSession` and `SwiftUIHostSceneHost`.
The SwiftUI host then owns pure role mapping, cell-rect frame
conversion, overlay mounting, and live-region announcement diffing.
The existing raster callback remains valid for hosts that only consume
pixels.
