# SwiftTUI Live Demo — Ideas

> **Goal**: replace the current single-tab counter (`LimitedGalleryView`
> wrapping `CounterTab`) with content that proves SwiftTUI's strengths
> in under 10 seconds of viewing.

**What we have available right now**

The `Examples/WebExample/TerminalApp` target imports
`GalleryDemoViews` from `Examples/gallery`. The full
`GalleryView` is not wired up because some surfaces are constrained on
WASI; instead a `LimitedGalleryView` shows just `CounterTab`. Tabs
already in `GalleryDemoViews/`:

- `CounterTab` — basic math + slider + animation hue rotation
- `CalculatorTab`
- `AnimationsTab` — springs, transitions, matched geometry, phase animator, completion callbacks
- `BordersAndShapesTab`
- `FileDropTab`
- `ImagesTab`
- `PhysicsTab`
- `TodoTab`
- `CommandPalette`

So step zero of any "richer demo" is: figure out which existing tabs work
under WASI today, and turn the limited gallery into a multi-tab gallery.
This is the lowest-effort, highest-impact change.

---

## What the demo needs to prove

Order of importance for the **marketing / docs hybrid** the website is becoming:

1. **It really runs in the browser.** No emulator shim. SwiftUI-shaped Swift, compiled to `wasm32-wasi`, drawing into integer cells.
2. **The authoring story matches SwiftUI.** Anyone who has written SwiftUI should look at the source and say "yes, that is what I expected."
3. **Layout is real.** Stacks, frames, lazy collections, custom layouts — not a textbox with absolute coordinates.
4. **State is real.** `@State`, `@FocusState`, `@Binding`, `withAnimation`, `.task` all fire.
5. **Capability negotiation is visible.** Toggle a theme, watch the truecolor / 256-color / 16-color fallback. Toggle Kitty graphics on/off.
6. **Multi-scene works.** Show that one `App` declaration owns more than one `WindowGroup` and the browser host can switch between them.

A demo that hits 3 of these will already be more compelling than a counter.

---

## Tier 1 — high impact, low risk (do these first)

### 1. Switch the demo from `LimitedGalleryView` to a curated tabbed gallery

`LimitedGalleryView` exists because some tabs presumably misbehave on WASI
today. The fix is to **expand it deliberately** rather than promote the
full `GalleryView`. Curate three tabs that demonstrate the framework
clearly:

- **Counter** (keep — it is small, fast, and friendly)
- **Animations** (spring + matched-geometry section is the showpiece)
- **Borders & shapes** (prove that drawing is integer-cell, not character art)

Keep the same `TabView` rendering path, just feed it three children.
Concrete first PR: turn `LimitedGalleryView` into a real `TabView` with
those three tabs and verify each runs in WASI without spawning subprocesses
or hitting filesystem APIs that the WASI runner cannot satisfy.

### 2. A "live system" splash that reads as marketing AND as a feature surface

Single screen, no tabs. It looks like a deploy / observability dashboard
because that is the genre TUIs are most associated with, but every cell
on screen is real SwiftTUI:

```
 SwiftTUI · live demo                                wasm32-wasi
 ┌─────────────────────────────────────────────────────────┐
 │  Frame pipeline                          7 / 7 phases   │
 │  ●●●●●●●  resolve · measure · place · semantics ·       │
 │           draw · raster · commit                        │
 │  16 ms budget    ▰▰▰▰▰▰▰▰▱▱  9.2 ms                     │
 │                                                         │
 │  Capabilities    UNICODE  TRUECOLOR  SAB-STDIN  KITTY?  │
 │  Surface         RasterSurface · 96 × 24 cells          │
 │                                                         │
 │  ▸ Counter       18 / 24                                │
 │    ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱  +1   −1   reset            │
 │                                                         │
 │  ▸ Sparkline     CPU last 60s                           │
 │    ▁▁▂▃▃▅▆▆▇█▇▇▆▅▄▃▃▂▂▁▁▁▁▂▃▄▅▅▅▆▇▆▆▅▅▄▄▃▃▃▂▂▁         │
 │                                                         │
 │  press  q  quit   ⌘k  palette   tab  next focus         │
 └─────────────────────────────────────────────────────────┘
```

Pieces involved:

- `SwiftTUICharts.Sparkline` driven by a `.task` loop generating fake
  metrics
- a `ProgressView` for the budget bar
- a `Stepper` or two `Button`s for the counter (so the user can interact)
- a tiny "capabilities" row that reads the live `TerminalCapabilityProfile`
  out of the environment — this is the bit that no other TUI demo can
  match, because the browser host is reporting real capability state
- a focus chain wired through so `Tab` actually cycles between the
  counter, the sparkline freeze toggle, and a "rotate theme" button

This single screen sells the framework better than any tab list because
every section answers "is the framework actually running?" with "yes,
look at this number, it is changing right now."

### 3. Theme-rotate button → exposes capability negotiation

Add a single button that cycles `TerminalRenderStyle` through three
themes (e.g. `.solarizedDark`, `.solarizedLight`, `.gruvbox`). This is
two lines of code to wire up and it shows that **the same authored
view** redraws against different host themes. Combined with idea (2),
this is the clearest visual proof that the host owns the chrome and the
framework owns the cells.

---

## Tier 2 — interactive showpieces

### 4. Tiny 1-keystroke text-adventure

A `VStack` with a paragraph of room description, a list of exits, and an
input field. State machine in `@State`. The whole game fits in 80 lines
of Swift. Why this works:

- proves text layout, scrolling, focus, input handling
- nostalgic genre, fits the terminal aesthetic
- it is more *fun* than a counter, which is the user's feedback
- runs entirely in `@State`, no I/O, perfect for WASI

Rooms could be self-referential ("The compiler hums quietly. To the north
you see a door labelled `resolve`. To the east, a passage labelled
`measure`...") so the adventure also teaches the pipeline.

### 5. Conway's Game of Life

A `Canvas`-style grid (a `LazyVStack` of `LazyHStack`s of cells, or a
custom `Layout`). Click / arrow-key to toggle cells, space to step,
slider to control speed. Why this works:

- proves grid layout under load
- proves the framework can drive ~30fps redraws (`AnimationsTab` already
  shows this)
- it is a recognized "framework benchmark" — every UI framework has a
  Life demo, SwiftTUI should too
- showcases `withAnimation` for cell birth/death transitions

Risk: scrolling to fit on a small viewport. Mitigation: cap at ~40×20.

### 6. A working markdown previewer

`TextEditor` on the left, rendered preview on the right, both inside a
single `HStack`. The preview is a tiny markdown→`Text` styled-run pass.
Why this works:

- proves multiline text editing
- proves split-pane layout under resize (uses the same SIGWINCH path the
  current demo's "Details" scene already exercises)
- doubles as a real tool — many people would actually use this

Risk: markdown parsing surface is non-trivial. Mitigation: support only
headings, bold, italic, lists, and code spans — that is enough to look
real.

### 7. Live ASCII clock with theme-aware figures

`TextFigure("\(hour):\(minute):\(second)", font: .future)` driven by a
`.task` that ticks once per second. Add a `Picker` for the FIGlet font,
a `Slider` for animation speed, and a `Toggle` for 12h/24h. Why this
works:

- showcases `TextFigure` with embedded fonts — a feature most TUI
  frameworks do not have
- one-screen, beautiful, calm
- 60 lines of code

This pairs well with the splash dashboard idea (3) — could be the
"hero ornament" inside it.

---

## Tier 3 — ambitious / multi-scene

### 8. `git status` browser

Read a static `git_status.json` fixture compiled into the WASM binary
(no real git access from WASI). Render a SwiftUI-shaped commit graph
(branch lines drawn through `Layout`-protocol custom layout) plus a
file tree. Browse, filter with `/`, expand with arrows.

Why this works:

- shows custom `Layout` participation (the unique sales pitch of #1 in
  the Why section)
- shows tree-forward `OutlineGroup` / `List`
- a *real* TUI workflow that anyone reading the SwiftTUI page would
  recognize
- multi-scene capable: a "diff" `WindowGroup` could open on Enter

Risk: scope. Mitigation: ship the file tree first, defer the graph.

### 9. Multi-scene "deploy console"

The original `WebExampleApp` already declares two `WindowGroup`s
(`"Component Gallery"` and `"Details"`). Exploit this. Build a
two-scene demo:

- main scene: list of running deploys (live updating via `.task`)
- detail scene: open on Enter to show one deploy's logs streaming in

This is the **only** demo idea on this list that sells the multi-scene
story. If the goal is to lead with "one App, three runtimes" — and the
existing site does — then the demo should at minimum show one App
with two scenes.

### 10. SwiftTUICharts dashboard tour

Cycle through every chart type (`BarChart`, `Sparkline`, `BulletChart`,
`HeatStrip`, `ThresholdGauge`, `StackedBarChart`) with a `TabView`. Each
tab is a single chart on synthetic data. Plays as a "showreel".

This is the closest thing to "a charts library demo," which has its own
audience. If `SwiftTUICharts` is a track that needs visibility, this is
the demo for it.

---

## Tier 4 — playful

### 11. Snake

Standard cell-grid Snake. Arrow keys, score, collision. Why it works:
recognizable, fun, low risk. Why it doesn't: it does not particularly
showcase the framework's strengths beyond "frames render fast." Use
this as a 4th tab inside the gallery, not as the primary demo.

### 12. Tetris, Pong, Minesweeper

Same risk profile as Snake. Skip these unless someone asks for a TUI
arcade.

### 13. A single `nyan.gif` running on `AnimatedImage`

The repo already ships `nyan.gif`. `AnimatedImage(...)` would make it
play back at the correct speed inside the demo. This shows GIF support,
the embedded image pipeline, and `AnimatedImage` as a peer product. It
is a 30-second hack with surprisingly high cuteness.

---

## Recommended ship plan

If this work were sequenced into PRs:

1. **PR 1** — Promote `LimitedGalleryView` to a 3-tab `TabView`
   (Counter, Animations, Borders & Shapes). Removes the "demo is just
   a counter" critique with one file change.
2. **PR 2** — Build the "live system" splash (idea 2) as a new tab in
   the same `TabView`, default-selected. This becomes the hero. Add the
   theme-rotate button (idea 3) inside it.
3. **PR 3** — Wire up the multi-scene story (idea 9) using the
   already-declared `"details"` `WindowGroup`. Even a minimal "press
   Enter to open a detail scene" beat sells the differentiator.
4. **PR 4 (optional, fun)** — Drop `nyan.gif` (idea 13) into a
   "Surprise" tab as a love-letter to the terminal aesthetic.

Total work for PRs 1–3: probably under a day for someone fluent in the
codebase, since every tab's view code already exists in `GalleryDemoViews`.

---

## What NOT to demo

- **Anything that requires real network or filesystem.** WASI's
  capabilities here are thin and the stub fixture overhead would
  dominate the source code, hurting the "look how SwiftUI-shaped
  this is" pitch.
- **Anything that is mostly pretty pictures with no interaction.**
  Scroll-driven motion graphics belong on the marketing page (above /
  below the iframe), not inside the framework demo. The framework's
  pitch is interaction.
- **Anything that would make someone think "but this is just a
  ncurses port."** Custom `Layout`, `@FocusState`, `withAnimation`,
  `matchedGeometryEffect` — these are the things SwiftTUI has and
  ncurses-shaped frameworks do not. Lead with them.

---

## Open questions

- **Is there a WASI capability gap blocking the full `GalleryView`?**
  If the only blocker is, say, `FileDropTab`'s file picker, that one tab
  can be hidden and the rest enabled. If there is a deeper issue, that
  is worth documenting separately.
- **Is the WASM bundle size a constraint?** `Examples/WebExample/pages-dist`
  is brotli-compressed to land under Cloudflare Pages' 25 MiB per-file
  limit. Adding tabs adds binary size; the splash dashboard idea (2) is
  cheaper than enabling the whole gallery.
- **Should the demo feature SwiftTUICharts at all?** It is a separate
  product. The marketing page implies it ships; the demo could prove it.
  But the website already has a "Charts" group in the public-surface
  inventory, so it may not need demo-time real estate.
