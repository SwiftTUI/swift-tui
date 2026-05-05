---
adr: "0013"
title: "Accessibility runtime policy for CLI output"
status: accepted
date: 2026-05-05
sources:
  - docs/proposals/ACCESSIBILITY.md
  - docs/proposals/SUBSTRATE_AUDIT.md
  - docs/plans/2026-05-05-003-accessibility-cli-runtime-plan.md
  - docs/decisions/0012-accessibility-node-shape.md
  - Sources/SwiftTUI/Configuration/EnvironmentResolver.swift
  - Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions+Resolution.swift
---

# ADR-0013: Accessibility runtime policy for CLI output

## Context

ADR-0011 and ADR-0012 landed the shared accessibility substrate:
roles, authoring metadata, and `SemanticSnapshot.accessibilityNodes`.
The next work is target behavior in the CLI runtime. Several policies
must be stable before implementation: output precedence, what
accessible mode implies, whether cursor-as-focus is gated, how reduced
motion affects controls, what linear output looks like, and where live
regions announce.

The current source is inconsistent in one important place:
`SwiftTUIOptions.runtimeConfiguration(...)` gives `--accessible`
priority over `--json`, while `RuntimeConfiguration.detect(...)` gives
`SWIFTTUI_JSON` priority over `SWIFTTUI_ACCESSIBLE`. The implementation
must converge before behavior is wired.

## Decision

Output modes are mutually exclusive. CLI flags override environment
variables. Within the same layer, JSON wins over accessible:
`--json` > `--accessible` > `SWIFTTUI_JSON=1` >
`SWIFTTUI_ACCESSIBLE=1` > `.tui`. JSON is machine output and must never
be wrapped, linearized, annotated, or affected by screen-reader text
fallbacks.

Accessible CLI mode implies `glyphs = .ascii`, `motion = .reduced`,
`noProgress = true`, and `linear = true`. These implications are not
individually opt-out in v1 because the public flag surface has no
positive `--unicode`, `--motion`, or `--progress` controls. `--json`
is the explicit escape hatch from accessible mode. `CI=true` does not
imply accessible output; it continues to imply reduced motion and no
progress by default.

Cursor-as-focus is enabled for terminal TUI output, not just accessible
mode. After each committed frame, the runtime cross-references
`FocusTracker.currentFocusIdentity` with
`SemanticSnapshot.accessibilityNodes`. If a focused node exists, the
terminal cursor is shown and moved to `cursorAnchor ?? rect.origin`.
If no focused accessibility node exists, the visual TUI may keep the
cursor hidden. JSON and web output do not use terminal cursor policy.
The public cursor-anchor modifier remains deferred; v1 uses built-in
package-only anchors and the node-origin fallback.

Reduced motion suppresses non-essential frame churn. Repeating
animations, spinners, blink, and transition intermediates do not tick
solely for motion. Indeterminate progress renders static status text.
Determinate progress renders stable text or a static bar and updates
only when the represented value materially changes. `noProgress`
removes progress ornament entirely and keeps status text.

The accessible linear renderer consumes `accessibilityNodes` in layout
reading order. It emits plain ASCII, one logical node per line, using
two-space indentation for parent depth. Structural unlabeled groups are
used for depth but skipped as lines. Lines use `role: label`; hints
append as ` - hint`. Nodes without labels may emit the role only.
Side-by-side layout is represented only by reading order, never as a
table.

CLI live-region announcements are emitted only by accessible linear
output in v1. Normal TUI mode does not write live-region text to
stderr or a side channel because that corrupts the terminal surface.
The first frame establishes baseline content; later changes announce
by identity. `.assertive` announcements are ordered before `.polite`;
`.off` suppresses announcements.

## Status

Accepted on 2026-05-05. Stage 1 of
`2026-05-05-003-accessibility-cli-runtime-plan.md` depends on this ADR.

## Consequences

Runtime configuration tests must change so JSON beats accessible in
both CLI and env-var resolution. Accessible mode now has mandatory
ASCII, reduced-motion, no-progress, and linear implications. The CLI
cursor policy becomes useful for all interactive TUI users, while the
linear renderer and live-region announcer remain accessible-mode-only
behavior. Web and SwiftUI host work should follow these semantics when
serializing or bridging focus and live regions, but they remain free to
use native ARIA or platform announcement APIs.
