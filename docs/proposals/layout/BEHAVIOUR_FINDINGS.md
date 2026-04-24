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

### 3. `.frame(maxWidth:)` is not enforced — child exceeds max under a large proposal

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Frames/MinIdealMaxFrameClampBehaviourTests.swift`
(layout `frames.min-ideal-max-frame-clamp`, plan task #10).

**Plan prediction:** A view with
`.frame(minWidth: 20, idealWidth: 40, maxWidth: 60)` rendered inside
an outer `.frame(width: 80)` should clamp DOWN to `maxWidth` (60 inner
cells → 62 cells including a 1-cell border ring).

**Observed (80×20 viewport):**

```
[15]|          ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
```

The above-max copy renders at ~70 cells border-width (68 inner
cells), exceeding `maxWidth: 60`.

The `minWidth` clamp (below-min copy clamps UP to minWidth=20 inner +
2 border = 22 total) and `idealWidth` (ideal copy sits at 40 when
proposed 40) are both honoured. Only the `maxWidth` ceiling is
silently exceeded.

**Resolution:** Pinned observed behaviour in the test (`aboveMax >
60`) rather than the SwiftUI-faithful ceiling. SwiftUI's own
`FlexibleFrameModifier` clamps to maxWidth when the proposed width
exceeds it; the library's implementation appears to accept the
parent's proposal directly when it is above minWidth, ignoring
maxWidth. Likely a genuine divergence — candidate remediation work
item for the frame modifier implementation.

**Status:** Open — library divergence; test pins observed behaviour.

### 4. `GeometryReader` reports terminal size, not the locally-proposed size

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Frames/ProposalTighteningBehaviourTests.swift`
(layout `frames.proposal-tightening`, plan task #12).

**Plan prediction:** A `GeometryReader` wrapped in
`.frame(width: 30, height: 3)` inside an 80-wide terminal should
report `proxy.size.width == 30`. The fixed frame is supposed to
TIGHTEN the proposal that reaches its child.

**Observed (80×10 viewport):**

```
| w=80                          |
```

The GeometryReader reports the full terminal width (80) regardless
of the surrounding `.frame(width: 30)`.

**Cause:** `GeometryReader.resolveElements(in:)` reads
`context.environmentValues.terminalSize` directly to populate the
proxy's `size`, ignoring the locally-proposed size that a
SwiftUI-faithful implementation would carry through resolve. The
view-tree is correctly TIGHTENED for layout purposes (the visible
border around the GeometryReader is 30 cells wide), but the proxy
itself never sees the tightening.

**Resolution:** Pinned observed behaviour in the test (`w=80`) with
guidance to flip the assertion when the library is fixed to honour
proposal tightening for GeometryReader proxies. Genuine library
divergence; candidate remediation work item for the GeometryReader
implementation (likely needs to thread the proposed size through
`ResolveContext`).

**Status:** Open — library divergence; test pins observed behaviour.

### 5. `.frame(width: 0, height: 0)` clips intrinsic content out of the raster

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Frames/IntrinsicTextUnderZeroProposalBehaviourTests.swift`
(layout `frames.intrinsic-text-under-zero-proposal`, plan task #13).

**Plan prediction:** Open question — does
`Text("intrinsic content").frame(width: 0, height: 0)` render at the
text's intrinsic size (overflowing the 0×0 frame) or vanish?

**Observed (60×10 viewport):**

```
[3] | plain copy:|
[5] | intrinsic content|       ← one and only "intrinsic content" row
[7] | zero-frame copy:|
```

The plain copy renders normally; the `.frame(width: 0, height: 0)`
copy is clipped out — its layout slot is empty between the
`zero-frame copy:` label and the bottom of the surface.

**Resolution:** Pinned observed behaviour in the test (exactly one
visible "intrinsic content" row). This matches the SwiftUI faithful
model: `.frame(width: 0, height: 0)` reports the explicit 0×0
container size to its parent, so the parent reserves zero space and
the renderer clips the child's intrinsic painting to that empty
region. No follow-up remediation needed.

**Status:** Closed — observed behaviour matches SwiftUI semantics.

### 6. `GeometryReader` in an unconstrained HStack does not hog — HStack shrinks to content

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Geometry/GeometryReaderInHStackHogsBehaviourTests.swift`
(layout `geometry.in-hstack-hogs`, plan task #38).

**Plan prediction:** The classic SwiftUI "GeometryReader hogs" gotcha
— an unconstrained `GeometryReader` inside an `HStack` claims all the
horizontal space the parent offers, pushing its `Text` sibling
off-screen or truncating it at the right edge.

**Observed (80×28 viewport, HStack has only `.frame(height: 5)`):**

```
[2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
[5] | ▌[G] [SIBLING]▐|
[8] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
```

Two library-specific behaviours both depart from SwiftUI:

  1. The `HStack` shrinks to its intrinsic content width (~13 cells)
     rather than expanding to the 80-cell horizontal proposal. In
     SwiftUI an `HStack` takes the proposed width.
  2. The `GeometryReader` contributes its child's intrinsic width
     (3 cells for `[G]`) to the HStack measurement rather than
     claiming the full horizontal proposal.

Even adding `.frame(width: 40)` to the `HStack` (see the exploratory
fixed-width variant) leaves the content centered within the frame at
~13 cells wide, with `[SIBLING]` fully visible. The classic
"eats everything" gotcha does NOT reproduce.

**Resolution:** Pinned the observed behaviour (both `[G]` and
`[SIBLING]` on the same row; HStack border < 40 cells on an 80-cell
viewport). Likely related to finding #4: the reader's proxy reports
`terminalSize` directly rather than flowing through the proposal
pipeline, and the surrounding `HStack` measurement does not see the
reader's "infinite" flex either. Revisit alongside finding #4.

**Status:** Open — likely related to finding #4; test pins observed
behaviour. Candidate remediation is shared with the GeometryReader
proposal-tightening work.
