# Substrate Audit

**Status:** Findings document, 2026-05-04. Captures what the codebase
*actually* contains relative to the assumptions baked into the
[`ACCESSIBILITY.md`](./ACCESSIBILITY.md),
[`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md), and
[`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md) proposals. Read this
before believing claims in those proposals about "what already
exists." Findings here override those claims; the proposals have
been updated with corrections that point back here.

**Owner:** unassigned. Tracking branch: `accessibility-investigation`.

---

## Why this exists

The first three proposals on this branch were written before the
substrate was audited. They make claims about what's already there
("the `semantics` phase captures role data," "the
`WASISurfaceBridge` encoder carries semantic information") that turn
out to be **partly right and partly wrong**. This document fixes the
record, with file paths and line references so future readers can
verify everything.

The findings below changed the design. Specifically:

- The accessibility role data is *already in `SemanticMetadata`* — we
  don't need to invent it; we need to **expose** what the built-ins
  already populate. **Significantly accelerates Phase 3.**
- The `SemanticSnapshot` produced by `SemanticExtractor` does **not**
  carry presentation-role data today; the extractor needs to be
  extended. **Small but real new work.**
- The `WebSurfaceFrameEncoder` is a **raster-level** encoder, not a
  semantic one. The wire format carries `[x, character, spanWidth,
  styleIndex]` per cell, no roles or labels. **Embedded-host ARIA
  story needs a wire-format extension, not just a transport reuse.**
- Some env-var detection (`NO_COLOR`, `LANG`/`LC_*`, `TERM=dumb`,
  `COLORTERM=truecolor`/`24bit`, `TERM=*256color`) is already wired
  into `TerminalCapabilityProfile.detect()`; the framework already
  picks ASCII glyphs when locale is non-UTF-8. **Phase 1 is much
  smaller than it looked.**
- `TerminalHost` already exposes `moveCursor(to:)`, `hideCursor`,
  `showCursor`. The cursor-placement *mechanism* exists; the
  cursor-as-focus *policy* is what's new. **Phase 2 is a policy
  patch, not new infrastructure.**

---

## Methodology

Files read in full:

- [`Sources/SwiftTUICore/Semantics/Semantics.swift`](../../Sources/SwiftTUICore/Semantics/Semantics.swift)
- [`Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift`](../../Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift)
- [`Sources/SwiftTUICore/Resolve/ResolvedNode.swift`](../../Sources/SwiftTUICore/Resolve/ResolvedNode.swift)
- [`Sources/SwiftTUICore/Semantics/FocusTracker.swift`](../../Sources/SwiftTUICore/Semantics/FocusTracker.swift)
- [`Sources/SwiftTUI/Terminal/TerminalAppearanceDetection.swift`](../../Sources/SwiftTUI/Terminal/TerminalAppearanceDetection.swift)
- [`Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)

Files spot-checked via `grep`:

- `Sources/SwiftTUI/Terminal/TerminalHost.swift` (cursor positioning, env reads)
- `Sources/SwiftTUI/Terminal/TerminalPresentation.swift` (capability detection,
  `NO_COLOR` handling)
- `Sources/SwiftTUIViews/Controls/`, `Sources/SwiftTUIViews/Input/`,
  `Sources/SwiftTUIViews/NavigationViews/` (presentationRole usage sites)
- `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift` (modifier surface)
- `Platforms/CLI/Sources/SwiftTUICLI/` (existing flag parsing)

---

## Finding 1 — Presentation role data already flows from built-ins

[`SemanticRoleTypes.swift`](../../Sources/SwiftTUICore/Semantics/SemanticRoleTypes.swift)
defines `PresentationRole` with these cases:

```
alert, button, confirmationDialog, disclosureGroup, link, list, menu,
picker, scrollView, scrollViewWithIndicators, section, sheet, slider,
stepper, table, tableRow, tabView, textEditor, textField, toggle
```

`SemanticMetadata.presentationRole` is `PresentationRole?`. Built-in
widgets already populate it:

| File | Line | Sets |
|---|---|---|
| `Sources/SwiftTUIViews/Controls/ValueControls.swift` | 88 | `.toggle` |
| `Sources/SwiftTUIViews/Controls/ValueControls.swift` | 261 | `.textField` |
| `Sources/SwiftTUIViews/Controls/ValueControls.swift` | 356 | `.disclosureGroup` |
| `Sources/SwiftTUIViews/Controls/Picker.swift` | 154 | `.picker` |
| `Sources/SwiftTUIViews/Controls/Link.swift` | 49 | `.link` |
| `Sources/SwiftTUIViews/Input/TextEditor.swift` | 70 | `.textEditor` |
| `Sources/SwiftTUIViews/Input/SecureField.swift` | 91 | `.textField` |
| `Sources/SwiftTUIViews/NavigationViews/TabView.swift` | 227 | `.tabView` |
| `Sources/SwiftTUIViews/ScrollView/ScrollView.swift` | 240 | `.scrollView` / `.scrollViewWithIndicators` |
| `Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift` | 469 | exposes `presentationRole(_:)` modifier |

`SemanticMetadata.tabItemLabel` is also already a structured
`TabItemLabel` (title + optional detail + optional badge); see
[`RenderTreeAndSemanticsTypes.swift:1-31`](../../Sources/SwiftTUICore/Resolve/ResolvedNode.swift).

**Implication for [`ACCESSIBILITY.md`](./ACCESSIBILITY.md):** the
proposed `AccessibilityRole` enum should *map onto* `PresentationRole`
where the cases overlap, not duplicate it. We may even want to
**rename** `PresentationRole` to `AccessibilityRole` (or unify them
under a single name) since the data is the accessibility role —
"presentation" was a hint, not a separate concept. The proposal said
we'd add new fields; the audit says ~75% of the role data is already
there. We're **adding labels/hints/hidden/live**, not roles.

| Proposed `AccessibilityRole` case | Already in `PresentationRole`? |
|---|---|
| `button` | yes |
| `checkbox` | not exactly — Toggle uses `.toggle`. Add or alias. |
| `link` | yes |
| `image` | no — no image widget yet |
| `textField` | yes |
| `secureField` | yes (mapped via `.textField` on `SecureField`; revisit) |
| `slider` | yes |
| `progressBar` | no |
| `stepper` | yes |
| `timer` | no |
| `list` | yes |
| `listItem` | not directly — list uses row identity; revisit |
| `menu` | yes |
| `menuItem` | no — derive from menu children |
| `tab` | not directly — `tabView` is set on container; tab item label is on `tabItemLabel` |
| `tabList` | derived (TabView) |
| `tabPanel` | derived (Tab body) |
| `table` | yes |
| `row` | yes (`tableRow`) |
| `cell` | not directly |
| `columnHeader` | no |
| `rowHeader` | no |
| `heading(level:)` | no |
| `status` | no |
| `alert` | yes |
| `group` | not directly — could derive from container |
| `region` | no |
| `separator` | no |
| `custom(String)` | no |
| (existing only) `confirmationDialog` | yes — needs to map |
| (existing only) `disclosureGroup` | yes |
| (existing only) `sheet` | yes |
| (existing only) `section` | yes |
| (existing only) `scrollView` | yes |
| (existing only) `scrollViewWithIndicators` | yes |
| (existing only) `tabView` | yes |
| (existing only) `tableRow` | yes |

Most overlap is clean. New cases the accessibility proposal needs to
*add* to the existing `PresentationRole` enum:

- `image`, `progressBar`, `timer`, `cell`, `columnHeader`, `rowHeader`,
  `heading(level:)`, `status`, `region`, `separator`, `menuItem`,
  `tabItem`, `group`, `custom(String)`.

Roughly 12–14 new cases. The semantic surface is already 60–70%
complete.

---

## Finding 2 — `SemanticSnapshot` does not carry roles today

[`Semantics.swift`](../../Sources/SwiftTUICore/Semantics/Semantics.swift)'s
`SemanticExtractor` produces a `SemanticSnapshot` containing
`interactionRegions`, `focusRegions`, `scrollRoutes`,
`selectionRoutes`, and `namedCoordinateSpaces`. **It does not include
the per-node `presentationRole` data**, even though that data is on
every visited node's `semanticMetadata`.

This means today, downstream consumers (focus tracker, scroll handler,
etc.) can't see the role data. They don't need to — they only care
about hit testing and focus traversal.

For accessibility, we need to extend the snapshot with a new
collection — call it `accessibilityNodes: [AccessibilityNode]` — that
carries `(identity, rect, role, label?, hint?, hidden, liveRegion?,
isFocused)` per node that's relevant to AT. The extractor walk is
already in place; this is an additional `append` per visited node.

The structural shape:

```swift
public struct AccessibilityNode: Equatable, Sendable {
  public var identity: Identity
  public var rect: CellRect
  public var role: AccessibilityRole
  public var label: String?
  public var hint: String?
  public var hidden: Bool
  public var liveRegion: AccessibilityPoliteness?
  public var children: [Identity]  // for nesting
}

public struct SemanticSnapshot: Equatable, Sendable {
  // ...existing fields...
  public var accessibilityNodes: [AccessibilityNode]
}
```

Cost estimate: medium. The walk exists; we add a per-node record. The
hard parts are role inference for non-builtin views and tree
nesting (since the walk is depth-first with parent context).

**Implication for [`ACCESSIBILITY.md`](./ACCESSIBILITY.md):** the
"Phase 3 — Accessibility modifiers" phase splits into two halves:

- **Phase 3a:** add `accessibilityLabel`/`accessibilityHint`/
  `accessibilityHidden` fields to `SemanticMetadata`, plus the
  modifiers that write them.
- **Phase 3b:** extend `SemanticExtractor` to emit
  `AccessibilityNode` records in the snapshot.

These can land in the same PR but are conceptually distinct.

---

## Finding 3 — `WebSurfaceFrameEncoder` is raster-level, not semantic

[`WebSurfaceTransport.swift:664-961`](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)
is the encoder both proposals assumed we'd reuse for the embedded
host's wire format. Reading it: the encoder takes a `RasterSurface`
and emits JSON of the form:

```json
{
  "version": 1,
  "width": 80,
  "height": 24,
  "styles": [null, {"fg": "...", "bg": "...", "em": 1}, ...],
  "rows": [[[x, "char", spanWidth, styleIndex], ...], ...],
  "images": [...]
}
```

This is a **2D character grid with per-cell style indices**, plus
image attachments. There is **no role, no label, no liveRegion, no
focus identity, no semantic tree** in this format. The browser bundle
in `Platforms/Web/` consumes this and reconstructs a visual character
grid. Effectively xterm.js-shaped output, just JSON-encoded instead
of ANSI-encoded.

The input parser (`WebSurfaceInputParser`) handles `key`, `mouse`,
`paste`, `resize`, `style` commands — also no semantic concepts.

**Implication for [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md):**
the proposal's claim "the same protocol that today flows over WASI
stdin/stdout flows over a WebSocket" is correct *as a transport*. The
proposal's implication that this protocol *also* carries the data
needed for ARIA rendering is wrong. To do real ARIA in the browser we
need one of:

1. **Extend the wire format** with a parallel `accessibilityTree`
   field alongside `rows`. Browser bundle reads both: keeps the
   character grid for visual rendering, mounts a hidden DOM tree from
   the accessibility data with `aria-live` regions, role-correct
   elements, and labels. Screen readers traverse the DOM; sighted
   users see the grid. This is the most surgical option. Cost: extend
   encoder + new `AccessibilityNode` type + browser-side mounter.
2. **Replace the encoder** with a semantic-tree emitter and let the
   browser do all the visual layout in the DOM. This is closer to a
   web-native UI. Bigger change, breaks the existing browser bundle.
3. **Send two streams** — keep the raster encoder unchanged for the
   visual side, send a separate semantic tree on a second WebSocket
   topic. Double bookkeeping.

Lean: option 1 — add `accessibilityTree` alongside `rows` in the
existing JSON, version-bump from `1` to `2`. Minimal disruption to
the visual side; ARIA mounted on the same connection.

**Implication for [`ACCESSIBILITY.md`](./ACCESSIBILITY.md):** the
"Phase 6 — Embedded-host ARIA mapping" phase is bigger than implied,
because it requires a wire-format extension. Specifically:

1. Define `AccessibilityNode` (Finding 2).
2. Extend `SemanticExtractor` to emit them.
3. Extend `WebSurfaceFrameEncoder` (or write a new sibling encoder)
   to serialize them.
4. Extend the browser bundle to mount them as DOM under the visual
   grid.

Steps 1–2 are usable for any future a11y target (SwiftUI host can
also consume `AccessibilityNode`). Steps 3–4 are embedded-host
specific.

---

## Finding 4 — Some env-var detection already exists

[`TerminalPresentation.swift:84-135`](../../Sources/SwiftTUI/Terminal/TerminalPresentation.swift)
has `TerminalCapabilityProfile.detect(environment:isTTY:)` which
already reads:

- `TERM` — picks `colorLevel: .none` for `dumb`, `.ansi256` for
  `*256color`, else `.ansi16`.
- `COLORTERM` — picks `colorLevel: .trueColor` when it contains
  `truecolor` or `24bit`.
- `LC_ALL` / `LC_CTYPE` / `LANG` — picks
  `glyphLevel: .ascii` if locale doesn't say UTF-8, else `.unicode`.
- **`NO_COLOR`** — picks `colorLevel: .none` when set (any value
  spec-compliant; current code uses `!= nil` which matches the spec).
- `isTTY` — drops to `colorLevel: .none` and disables hyperlinks /
  mouse / synchronized output when stdout is not a TTY.

[`TerminalAppearanceDetection.swift`](../../Sources/SwiftTUI/Terminal/TerminalAppearanceDetection.swift)
also reads `COLORFGBG` to heuristically detect dark/light mode.

[`TerminalHost.swift:1382-1440`](../../Sources/SwiftTUI/Terminal/TerminalHost.swift)
reads `TMUX`, `TERM_PROGRAM`, `LC_TERMINAL`, `COLORTERM` for terminal
identity heuristics (used for SGR-pixel mouse support).

What's **not** yet read:

- `FORCE_COLOR` — would override `colorLevel: .none` when stdout is
  non-TTY.
- `CLICOLOR=0` — legacy BSD convention.
- `CLICOLOR_FORCE` — legacy BSD force.
- `CI=true` — should imply non-interactive / reduce-motion.
- `SWIFTTUI_*` family — none exist yet.

**Implication for [`ACCESSIBILITY.md`](./ACCESSIBILITY.md) and
[`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md):** Phase 1 (env
contract) is **smaller than the proposal implied**. We need to:

1. **Extend** `TerminalCapabilityProfile.detect` with `FORCE_COLOR`,
   `CLICOLOR`, `CLICOLOR_FORCE`, `CI`. Single function, ~20 lines.
2. **Add** `SWIFTTUI_ASCII`, `SWIFTTUI_REDUCE_MOTION`,
   `SWIFTTUI_ACCESSIBLE` reads. Probably a new
   `AccessibilityCapabilityProfile` sibling type or a small
   extension on the existing one — TBD.
3. **Have `SwiftTUIOptions` *delegate* to the existing detection**
   rather than duplicate it. The flags override the env, but the env
   detection already works.

The "Phase 1 is the cheapest, broadest user-visible win" framing in
the accessibility phasing remains true — but Phase 1 is now
*extension*, not *new construction*.

---

## Finding 5 — Cursor placement infrastructure exists; policy is missing

[`TerminalHost.swift`](../../Sources/SwiftTUI/Terminal/TerminalHost.swift) has
`moveCursor(to:)` (lines 991, 1923), `hideCursorSequence()` (1699,
1961), `showCursorSequence()` (1703, 1965). The runtime hides the
cursor at startup (line 1894) and shows it at teardown (1908).

[`FocusTracker`](../../Sources/SwiftTUICore/Semantics/FocusTracker.swift) exposes
`currentFocusIdentity: Identity?`. Each `FocusRegion` carries a
`rect: CellRect`. The runtime can therefore answer "where is the
focused widget's bounds?" with one lookup.

What's missing:

- **A policy** that, after each commit, looks up the focused widget
  and calls `moveCursor` to a chosen anchor inside its bounds.
- **An anchor** abstraction per focusable widget — text fields want
  the caret position; list rows want the row start; buttons want
  label start. Currently widgets don't expose this. Could be:
  - A new `cursorAnchor: CellPoint?` field on `SemanticMetadata`
    that built-ins populate (relative to bounds), plus an
    `accessibilityCursorAnchor()` modifier as the consumer escape
    hatch.
  - Or derive: focused widget's bounds → top-left, with TextField
    overriding to caret position.

**Implication for [`ACCESSIBILITY.md`](./ACCESSIBILITY.md):** Phase 2
(cursor-as-focus) is a policy + anchor patch in `RunLoop+Rendering`
or wherever the commit phase finalizes output. The pieces exist.
Estimated cost: small (a day of focused work). The biggest gotcha is
that the runtime currently hides the cursor by default for visual
reasons; we want a switch that *shows* it at the focused anchor in
accessible mode (or always, if the cursor-as-focus policy turns out
to also be visually fine).

---

## Finding 6 — Diff-based commit pipeline confirmed

`CommitPlanner.swift` and `Rasterizer.swift` are the diff path. The
seven-phase pipeline in `AGENTS.md` is real. The "we don't pay full
repaint per frame" advantage is real.

The `WebSurfaceFrameEncoder` does, however, encode and emit a **full
surface** every commit (`strategy: .fullRepaint` on
[line 251](../../Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift)).
For the WASI surface this is fine — it's used for snapshot-shaped
delivery. For the embedded web host, full surface per frame would be
wasteful over WebSocket, especially at higher refresh rates.

**Implication for [`EMBEDDED_WEB_HOST.md`](./EMBEDDED_WEB_HOST.md):**
Phase 1 of the embedded host can ride on the existing full-surface
encoder (correctness over performance). A later phase should add a
diff-based variant that encodes only changed cells, mirroring the
terminal-side `CommitPlanner` strategy. Worth adding as an explicit
performance phase in the embedded-host plan.

---

## Finding 7 — No flag parsing beyond runner-internal

[`Platforms/CLI/Sources/SwiftTUICLI/CLIMode.swift`](../../Platforms/CLI/Sources/SwiftTUICLI/CLIMode.swift)
parses `--instances`, `--scenes`, `--attach`, `--pid`, `--instance`
via a hand-rolled `while index < args.count` loop. Anything else is
dropped silently.

Examples in `Examples/` (gallery, minimal) declare `@main struct …:
App` with no parser at all. Consumers writing their own flags would
either depend on `swift-argument-parser` themselves or hand-roll
parsing.

This **confirms the [`ARGUMENT_PARSING.md`](./ARGUMENT_PARSING.md)
proposal's diagnosis of the status quo verbatim**. No correction
needed; the proposal landed on the right problem statement.

---

## Finding 8 — Structural facts for the ARIA wire format

Now that we've established the format will be extended (Finding 3),
some structural notes for the design:

- **Identity** is `Sources/SwiftTUICore/Geometry/AnchorTypes.swift`'s `Identity` —
  effectively a path-shaped key. Stable across frames for the same
  view instance. Serializable as a string. Good fit for the
  `id` attribute on the DOM mirror.
- **`CellRect`** is `(origin: (x, y), size: (width, height))`,
  integers. The browser bundle already converts these to pixel
  positions for visual rendering; the same conversion can position
  the offscreen ARIA mirror.
- **Tree shape:** `PlacedNode` already has parent/child structure.
  The accessibility tree should *mirror* this, with hidden-from-AT
  nodes (`accessibilityHidden(true)`, transient overlay nodes,
  out-of-clip nodes) skipped. Note that `PlacedNode.isTransient`
  already exists and is filtered by `SemanticExtractor`; we follow
  the same rule.
- **Focus state:** the focus tracker holds `currentFocusIdentity`.
  The accessibility tree should mark whichever node matches as
  `isFocused: true`. Browser bundle calls `.focus()` on the
  corresponding DOM element.

---

## Updated cost estimates

Because of these findings, the proposed phasing becomes:

| Phase | What | Cost relative to original estimate |
|---|---|---|
| 1 | Env contract + ASCII mode | **Smaller** — extends existing detection, doesn't replace |
| 2 | Cursor-as-focus | **Same** — policy patch on existing infra |
| 3a | Add label/hint/hidden/liveRegion fields + modifiers | Same |
| 3b | Extend `SemanticExtractor` with `AccessibilityNode` records | New — was implicit before |
| 4 | Reduce-motion + accessible mode | Same |
| 5 | Live regions + announcer | Same |
| 6 | Embedded-host ARIA mapping | **Larger** — wire-format extension required |
| 7 | WASM web ARIA mapping | Same — rides on Phase 6 wire-format work |
| 8 | SwiftUI host bridge | **Smaller** — `AccessibilityNode` already structured for it |
| 9 | Tests + lint | Same |

Net: **earlier phases are smaller and faster than implied; the
embedded-host ARIA phase is bigger than implied because of the
wire-format extension; later phases benefit from the consolidated
`AccessibilityNode` representation.**

---

## Action items pushed back into the proposals

1. **`ACCESSIBILITY.md`** — Update "What we already have in
   swift-tui" section with the actual file/line references from this
   audit. Update the `AccessibilityRole` enum to *extend*
   `PresentationRole` rather than duplicate it (or rename
   `PresentationRole` → `AccessibilityRole` and add the missing
   cases). Split Phase 3 into 3a/3b. Note that Phase 6 requires
   wire-format extension.

2. **`EMBEDDED_WEB_HOST.md`** — Correct the "wire format reuse" claim:
   transport reusable, format must be extended for ARIA. Add
   wire-format-versioning note (`version: 2` for ARIA-aware bundles).
   Add explicit "diff-based encoder" as a deferred performance
   phase.

3. **`ARGUMENT_PARSING.md`** — Note that
   `TerminalCapabilityProfile.detect` already reads `NO_COLOR`,
   `TERM`, `COLORTERM`, `LANG`/`LC_*`. The `SwiftTUIOptions`
   `runtimeConfiguration()` should *delegate* to the existing
   detection rather than duplicate it. New env vars
   (`FORCE_COLOR`, `CLICOLOR`, `SWIFTTUI_*`) extend the existing
   profile.

These updates have been applied. Search each proposal for "Audit
correction (2026-05-04)" to find them in place.

---

## Open questions surfaced by the audit

1. ~~**Should `PresentationRole` be renamed to `AccessibilityRole`?**~~
   **Resolved by
   [ADR-0011](../decisions/0011-accessibility-role-replaces-presentation-role.md)**
   — yes; rename and absorb the missing 15 cases. Single field on
   `SemanticMetadata`, single modifier, single source of truth.

2. ~~**Should `SemanticMetadata.cursorAnchor` be added?**~~ **Resolved
   by [ADR-0012](../decisions/0012-accessibility-node-shape.md)** —
   yes; the field lives on `AccessibilityNode` in absolute surface
   coordinates. Built-in TextField populates it; nil means "use
   the node's origin"; the `accessibilityCursorAnchor(_:)` modifier
   is the escape hatch.

3. ~~**Flat list with parent identity, or recursive tree?**~~
   **Resolved by [ADR-0012](../decisions/0012-accessibility-node-shape.md)**
   — flat array, parent encoded via `parentIdentity: Identity?`,
   tree reconstruction at the consumer. Matches the established
   pattern of `SemanticSnapshot`'s other collections.

4. **Wire-format version bump: hard break or backward-additive?**
   The accessibility proposal and the embedded-host proposal have
   landed on **backward-additive** — `version: 2` adds
   `accessibilityTree` alongside the existing `rows` field; older
   browser bundles ignore the new field. Captured in
   `EMBEDDED_WEB_HOST.md` Audit correction. Not promoted to an ADR
   because it's a wire-format detail, not a foundational decision —
   if we need to break later, we can.

5. **Where does the "show cursor at focused anchor" gate live?
   Always-on, or behind reduce-motion / accessible-mode?** Still
   open. Lean: always-on. Showing the cursor at the focused widget
   is good UX for sighted users too; it's only the "hide cursor
   entirely" default that's wrong for screen readers. Decide at
   Phase 2 implementation time.

6. **Should `CI=true` enable accessible mode or just reduce-motion?**
   Still open. Lean: reduce-motion only. CI users want clean output,
   not sequential prompts. Decide at Phase 1 / Phase 4 implementation
   time.

The two foundational questions (rename + node shape) are now
ADR-locked; the wire-format and runtime-policy questions remain
open but are not on the critical path.

---

## Changelog

- 2026-05-04: Audit performed. Findings captured. Action items
  pushed back into the three sister proposals as inline corrections
  marked `Audit correction (2026-05-04)`.
- 2026-05-04: Two of the six surfaced open questions
  (PresentationRole rename, AccessibilityNode shape) locked in via
  [ADR-0011](../decisions/0011-accessibility-role-replaces-presentation-role.md)
  and
  [ADR-0012](../decisions/0012-accessibility-node-shape.md).
  Open-questions section updated to mark them resolved with
  cross-references.
