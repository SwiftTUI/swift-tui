# Framework Reserved-Key & Consumer Escape Hatch — Findings

This document tracks framework gaps, surprises, and reserved-key
collisions surfaced by the Layouts example app (see
`Examples/layouts/`). Each entry is filed when a behaviour test in
the layouts example fails on its first run and the assertion is
adjusted to pin the OBSERVED runtime behaviour rather than the plan's
predicted behaviour. The entry should make the discrepancy explicit
so future readers can resolve whether the gap is:

  - a faithful-SwiftUI behaviour the plan predicted incorrectly
    (close as "spec was wrong; library is faithful"), or
  - an actual library divergence (open as a remediation work item).

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
[2] |     normal|                        (col 5)
[3] | shifted|                           (col 1)
[4] |     normal again|                  (col 5)
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
behaviour: shifted col == normal col − 4.

**Status:** Closed — spec was wrong; library is faithful.
