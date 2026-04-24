# Layouts Example — Behaviour Findings

This doc accumulates observations where a layout behaviour-test pinned
runtime behaviour different from the plan's prediction. Each entry:
observation → context → resolution.

Surfaced from the Layouts example app (see `Examples/layouts/`).
Entries are filed when a behaviour test fails on its first run and the
assertion is adjusted to pin the OBSERVED runtime behaviour rather than
the plan's predicted behaviour. The entry should make the discrepancy
explicit so future readers can resolve whether the gap is:

  - a faithful-SwiftUI behaviour the plan predicted incorrectly
    (close as "spec was wrong; library is faithful"), or
  - an actual library divergence (open as a remediation work item).

This is the general catch-all for "spec said X, library does Y"
observations across all 56 layouts in the example.

## Findings

### 1. `.alignmentGuide(.leading) { _ in N }` shifts the child OPPOSITE to N

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Stacks/VStackLeadingGuideShiftBehaviourTests.swift`
(layout `stacks.vstack-leading-guide-shift`, plan task #5).

**Plan prediction:** Setting `.alignmentGuide(.leading) { _ in 4 }`
on a child of a `VStack(alignment: .leading)` should shift that
child's leading edge **4 cells to the RIGHT** of the stack's default
leading edge.

**Observed (40×10 viewport, `.padding(1)` outer):**

```
[1] |     VStack leading guide shift|   (col 5)
[2] |     plain above|                  (col 5)
[3] | shifted|                          (col 1)
[4] |     plain below|                  (col 5)
```

The shifted child appears 4 cells to the **LEFT** of the unshifted
siblings, not the right.

**Resolution:** This is the faithful SwiftUI behaviour. Per Apple's
documentation: "If you increase the value of an alignment guide, the
view shifts in the opposite direction along the alignment axis." The
returned value (`4`) is the offset *inside* the child where the
stack's alignment anchor sits; pulling the anchor right by 4 inside
the child moves the child's own leading edge left by 4 in the stack.

The library is correct. The plan's directional prediction was
backwards. The behaviour test pins the OBSERVED (and SwiftUI-faithful)
behaviour: shifted col == plain col − 4.

**Status:** Closed — spec was wrong; library is faithful.

### 2. Framework-reserved keys silently drop consumer-bound single-key commands

**Surfaced by:** `Examples/layouts/Sources/LayoutsApp/LayoutDetailHost.swift`.
The host originally attempted to bind Esc as "back to catalog."

**Plan prediction:** A consumer-registered `.keyCommand(key: .escape,
...)` on a screen would receive Esc key presses as an ordinary
key-command dispatch.

**Observed:** The framework reserves Esc (and other unmodified
navigation keys) for presentation dismissal in `KeyCommandModifier`.
Consumer-bound single-key commands on those reserved keys are silently
dropped: no error, no log, the press is swallowed by the presentation
dismiss path (or no-ops when no presentation is active).

**Workaround in use:** The Layouts example binds ⌃B instead of Esc for
"back to catalog." ⌃B is the nearest idiomatic "back" chord in
terminal UIs and is not in the reserved set.

**Resolution:** Design question — is silent drop the correct default
for consumer bindings that collide with reserved keys, or should the
framework surface an escape hatch (warn on registration, provide a
`.consumeEvenWhenReserved` override, or narrow the reserved set)?
Tracking as an open design question; no library change required for
the Layouts example to ship.

**Status:** Open — design question. Current workaround is adequate.
