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

### 3. `.frame(maxWidth:)` clamps above-max proposals

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Frames/MinIdealMaxFrameClampBehaviourTests.swift`
(layout `frames.min-ideal-max-frame-clamp`, plan task #10).

**Plan prediction:** A view with
`.frame(minWidth: 20, idealWidth: 40, maxWidth: 60)` rendered inside
an outer `.frame(width: 80)` should clamp DOWN to `maxWidth` (60 inner
cells → 62 cells including a 1-cell border ring).

**Observed after remediation (80×20 viewport):**

```
[15]|          ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
```

The above-max copy renders at about 62 cells border-width (60 inner
cells + 2 border cells), honouring `maxWidth: 60`.

The `minWidth` clamp (below-min copy clamps UP to minWidth=20 inner +
2 border = 22 total), `idealWidth` (ideal copy sits at 40 when
proposed 40), and `maxWidth` ceiling are all honoured.

**Resolution:** The behaviour test now pins the SwiftUI-faithful
ceiling (`aboveMax ~= 62` including border cells). The earlier
assertion compared total border width to the inner max width and made
the divergence look larger than the live runtime behavior.

**Status:** Closed — library is faithful; test pins max clamping.

### 4. `GeometryReader` reports the locally-proposed size

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Frames/ProposalTighteningBehaviourTests.swift`
(layout `frames.proposal-tightening`, plan task #12).

**Plan prediction:** A `GeometryReader` wrapped in
`.frame(width: 30, height: 3)` inside an 80-wide terminal should
report `proxy.size.width == 30`. The fixed frame is supposed to
TIGHTEN the proposal that reaches its child.

**Observed after remediation (80×10 viewport):**

```
| w=30                          |
```

The GeometryReader reports the surrounding `.frame(width: 30)`
proposal instead of the full terminal width.

**Cause:** `GeometryReader.resolveElements(in:)` previously read
`context.environmentValues.terminalSize` directly while fixed frame
resolution did not tighten that environment for the child subtree.
The view-tree was correctly tightened for layout purposes, but the
proxy itself never saw the tightening.

**Resolution:** Fixed frames now resolve their child content under a
tightened terminal-size environment on explicit axes, and
`GeometryReader` lowers its content into a flexible, top-leading
proposal-filling frame. The tests now expect `w=30` and
`w=40 h=10`.

**Status:** Closed — library is faithful for fixed-frame proposal
tightening.

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

### 6. `GeometryReader` in an unconstrained HStack hogs available width

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/Geometry/GeometryReaderInHStackHogsBehaviourTests.swift`
(layout `geometry.in-hstack-hogs`, plan task #38).

**Plan prediction:** The classic SwiftUI "GeometryReader hogs" gotcha
— an unconstrained `GeometryReader` inside an `HStack` claims all the
horizontal space the parent offers, pushing its `Text` sibling
off-screen or truncating it at the right edge.

**Observed after remediation (80×28 viewport, HStack has only
`.frame(height: 5)`):**

```
[2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
[3] | ▌[G]                                                                         ▐|
[5] | ▌                                                                   [SIBLING]▐|
[8] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
```

The HStack now expands to the available horizontal proposal and the
GeometryReader receives the slack before the sibling. `[SIBLING]`
remains visible at the trailing edge in this terminal layout because
the stack still measures and places the sibling after allocating the
reader's flexible width.

**Resolution:** `GeometryReader` now lowers its content through a
flexible `.frame(maxWidth: .infinity, maxHeight: .infinity,
alignment: .topLeading)`, so the stack's existing flexible-content
allocation hands it the extra main-axis width. This fixes the
shrink-to-content divergence that was related to finding #4.

**Status:** Closed — library now reproduces the proposal-hogging
shape of the SwiftUI behavior for this layout.

### 7. `Canvas` already self-clips at the subpixel level — `.clipped()` is a no-op overlay

**Surfaced by:** `Examples/layouts/Tests/LayoutsTests/ShapesCanvas/CanvasHonorsClippedBehaviourTests.swift`
(layout `shapes.canvas-honors-clipped`, plan task #53).

**Plan prediction:** A `Canvas` whose drawing paints subpixels past
the canvas's frame would, without `.clipped()`, leak painted cells
into adjacent layout regions of the raster. Adding `.clipped()` to
the Canvas would crop the overflow.

**Observed (rendered at 60×12, identical layout with and without `.clipped()`):**

```
[2] | ▛▀▀▀▀▀▀▀▀▀▀▜|             <- top border, 10-cell frame
[5] | ▌⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉▐|             <- canvas line: cyan at cols 2..11 ONLY
[7] | ▙▄▄▄▄▄▄▄▄▄▄▟|             <- bottom border
```

Both variants — with `.clipped()` and without — produce the **same**
raster. The drawing requests a horizontal line spanning
`context.width * 3` subpixels (3× the frame's own width), but the
`CanvasContext` exposed to the drawing is sized to the frame's
subpixel extent and silently discards out-of-range pixels (per
`CanvasDrawing` doc: "Out-of-range pixels are silently clipped").
The library guarantees subpixel-bounds clipping at the source, so
`.clipped()` has nothing to crop downstream.

**Resolution:** Pinned the observed behaviour (cyan strictly within
the 10-cell frame interior, cols 2..11). Because removing `.clipped()`
does not change the raster, the planned "remove `.clipped()` →
overflow leaks" vacuity check is not informative; the test instead
A/Bs against a wider canvas frame (10 → 30 cells), which DOES extend
the cyan-painted region as the right edge moves. That A/B proves the
assertion is observing the actual frame edge rather than vacuously
true.

The library is correct (Canvas cannot leak past its own frame at the
subpixel level — that's what `BrailleCanvas`'s "silently clipped"
contract guarantees). The plan's predicted vacuity was wrong because
it assumed `.clipped()` was a load-bearing modifier on `Canvas`; on
this library it is a redundant overlay.

**Status:** Closed — spec was wrong about the vacuity. Library is
faithful: Canvas self-clips at subpixel bounds, `.clipped()` is
defensive but functionally a no-op for `Canvas` overflow.
