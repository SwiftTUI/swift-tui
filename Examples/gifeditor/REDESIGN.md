# gifeditor — Photoshop-Style Redesign Spec

## Goals

1. **Photoshop-flavored chrome.** Menu bar on top, contextual options bar
   under it, narrow icon-only tool dock pinned to the left, stacked panels
   on the right (Color/Palette/Layers), timeline + status pinned to the
   bottom.
2. **Mouse-clickable parity.** Every action that today is keyboard-only
   gains a clickable target (button, menu item, swatch, dropdown,
   stepper). The keyboard shortcut stays — it is shown as a hint next to
   its menu item or as a tooltip-style suffix in panel headers.
3. **Unicode icons.** Tools and panel actions are represented by single-
   character glyphs that exist in every monospace font Apple Terminal,
   iTerm2, Ghostty, and Kitty render today. No emoji (terminals widely
   render those as 2 cells with inconsistent baselines).
4. **Maximize canvas.** The chrome is sized to take the smallest amount
   of cells consistent with goals 1–3. Tool dock is 3 cells wide. Right
   panel collapses to a 14-cell column. Top chrome is 2 rows. Bottom
   chrome is 3 rows. Everything else is canvas.

---

## Current state (what we are replacing)

`EditorView.body` lays out today as:

```
┌─ header ────────────────────────────────────────────────────┐
│ gifeditor  untitled                              ● modified │
├─────────────────────────────────────────────────────────────┤
│ ┌Tools(18w)─┐  ┌── canvas ────────────────┐  ┌ Palette ──┐  │
│ │P Pen      │  │                          │  │ ████████  │  │
│ │E Eraser   │  │                          │  │ ████████  │  │
│ │B Bucket   │  │     (32×32 GIF)          │  ├ Layers ───┤  │
│ │G Gradient │  │                          │  │● Layer 1  │  │
│ │M Marquee  │  │                          │  │           │  │
│ │I Eyedrop. │  │                          │  │           │  │
│ │           │  └──────────────────────────┘  │           │  │
│ │ Space …   │  ┌Timeline frame 1/3 — 10cs──┐ │           │  │
│ │           │  │  ▣ ▣ ▣                    │ │           │  │
│ └───────────┘  └──────────────────────────┘  └───────────┘  │
├─────────────────────────────────────────────────────────────┤
│ Press ? for help                       [16,8] L1/1 half-cell│
└─────────────────────────────────────────────────────────────┘
```

Pain points:

- **No mouse target** for: tool selection (canvas captures clicks for
  drawing, not for selecting tools), palette pick, layer reorder, frame
  navigation, save/save-as/quit/resize, swap primary/secondary, layer
  visibility toggle, layer add/delete, frame add/duplicate/delete, frame
  delay adjust, equalize delays, copy/paste, help, escape/clear.
- **Toolbox column is 18 cells wide** but most of that is the label.
  Photoshop-like icon dock is 3 cells.
- **Header/footer/timeline are each separate strips** rather than one
  cohesive top bar plus one bottom bar.
- **No menu bar.** All discoverability is `?` → modal help sheet.

---

## Target layout

```
0         1         2         3         4         5         6         7
0123456789012345678901234567890123456789012345678901234567890123456789012345
┌── ✦ gifeditor ──────────────────────────────────────────────────────────┐
│ File▾  Edit▾  Image▾  Layer▾  Select▾  Frame▾  View▾  Help▾  ●modified │ <- row 0: menu bar
├─────────────────────────────────────────────────────────────────────────┤
│ Pen  ◆ #FF66AA  ▒ size 1   ⇄ swap   primary [1] secondary [2]    [?]   │ <- row 1: options bar
├───┬─────────────────────────────────────────────────────────────────────┤
│ ✎ │                                                          ┌─Color──┐ │
│ ⌫ │                                                          │P #FF66 │ │
│ ⬢ │                                                          │S #1133 │ │
│ ◐ │                                                          │  ⇄     │ │
│ ▭ │                                                          ├Palette─┤ │
│ ⊙ │                                                          │████████│ │
│ ──│              C   A   N   V   A   S                       │████████│ │
│ ■ │                                                          │████████│ │
│ □ │                                                          │████████│ │
│ ⇄ │                                                          ├Layers──┤ │
│   │                                                          │● L1  ▲▼│ │
│   │                                                          │○ L2  ＋✕│ │
│   │                                                          │        │ │
├───┴─────────────────────────────────────────────────────────────────────┤
│ Frames  ◀◀ ◀  ▣ ▣[▣]▣ ▣ ▣ ▣  ▶ ▶▶   ＋ ⎘ ✕   delay 10cs ⊖⊕  =all       │ <- row N-2: timeline
│ [16, 8]  L1/1  half-cell                       Pen — Space paints       │ <- row N-1: status
└─────────────────────────────────────────────────────────────────────────┘
   ^^^
   tool
   dock
```

### Row budget

| Region          | Rows | Notes                                                          |
| --------------- | ---: | -------------------------------------------------------------- |
| Menu bar        |    1 | `Menu("File")`, `Menu("Edit")`, …, doc title, dirty marker     |
| Options bar     |    1 | Tool-contextual: tool name, color chip, modifier toggles, swap |
| Canvas + sides  |  N-5 | Left tool dock (3w), canvas (flex), right panel (14w)          |
| Top divider     |    1 | `Divider()`                                                    |
| Bottom divider  |    1 | `Divider()`                                                    |
| Timeline strip  |    1 | Frames, delay stepper, frame ops                               |
| Status strip    |    1 | Cursor, layer counter, mode hint                               |
| **Total chrome**|    6 | All others rows go to the canvas                               |

For a typical 60×24 terminal, that gives the canvas **~18 rows** of
height and **~58 cells** of width — plenty for a 32×32 (16 row) or
48×48 (24 row) GIF. The right panel hides itself if width drops below
50 cells (`view.frame(maxWidth:)` + `.layoutPriority` so canvas wins).

---

## Component specs

### 1. Menu bar (row 0)

`HStack(spacing: 2)` containing one `Menu` per top-level menu, plus the
document title and dirty marker pushed right with `Spacer()`.

```swift
HStack(spacing: 2) {
  Menu("File") {
    Button("New", systemHint: "")            { model.newDocument() }
    Button("Open…", systemHint: "")          { model.openFile() }
    Divider()
    Button("Save", systemHint: "Ctrl+S")     { model.save() }
    Button("Save As…", systemHint: "Alt+S")  { model.saveAs() }
    Divider()
    Button("Resize Canvas…")                 { /* opens Picker sheet */ }
    Divider()
    Button("Quit", systemHint: "Ctrl+Q", role: .destructive) { … }
  }
  Menu("Edit") {
    Button("Undo",  systemHint: "Ctrl+Z")    { model.undo() }      // future
    Button("Redo",  systemHint: "Ctrl+Y")    { model.redo() }      // future
    Divider()
    Button("Copy",  systemHint: "Ctrl+C")    { model.copySelection() }
    Button("Paste", systemHint: "Ctrl+V")    { model.paste() }
    Divider()
    Button("Clear Selection", systemHint: "Esc") { model.clearSelection() }
  }
  Menu("Image") {
    Button("Resize Canvas…")                 { … }
  }
  Menu("Layer") {
    Button("New Layer",   systemHint: "Alt+N") { model.addLayer() }
    Button("Delete Layer",systemHint: "Alt+X") { model.deleteCurrentLayer() }
    Divider()
    Button("Toggle Visibility", systemHint: "Alt+H") { model.toggleCurrentLayerVisibility() }
    Button("Layer Below", systemHint: "Alt+J") { model.selectLayerBelow() }
    Button("Layer Above", systemHint: "Alt+K") { model.selectLayerAbove() }
  }
  Menu("Select") {
    Button("Clear Selection", systemHint: "Esc") { model.clearSelection() }
    Button("Confirm Marquee", systemHint: "Enter") { model.applyToolAtCursor() }
  }
  Menu("Frame") {
    Button("New Frame",         systemHint: "Ctrl+N") { … }
    Button("Duplicate Frame",   systemHint: "Ctrl+D") { … }
    Button("Delete Frame",      systemHint: "Alt+D")  { … }
    Divider()
    Button("Previous Frame",    systemHint: "Alt+,")  { … }
    Button("Next Frame",        systemHint: "Alt+.")  { … }
    Divider()
    Button("Increase Delay 10cs", systemHint: "Alt+=") { … }
    Button("Decrease Delay 10cs", systemHint: "Alt+-") { … }
    Button("Equalize All Delays", systemHint: "Alt+0") { … }
  }
  Menu("View") {
    Button("Show Tool Dock",     state: .toggle($showsTools))     { … }
    Button("Show Right Panel",   state: .toggle($showsPanels))    { … }
    Button("Show Timeline",      state: .toggle($showsTimeline))  { … }
    Divider()
    Button("Pixel Grid Mode")    { /* fullCell vs halfBlock picker */ }
  }
  Menu("Help") {
    Button("Keyboard Shortcuts…", systemHint: "?") { isHelpPresented = true }
    Button("About gifeditor")                       { … }
  }
  Spacer()
  Text("✦ \(documentLabel)").foregroundStyle(.muted)
  Text(model.isDirty ? "● modified" : "saved")
    .foregroundStyle(model.isDirty ? .warning : .success)
}
```

`Menu` opens as an overlay floating above the canvas and panels and
**does not reflow surrounding content** when expanded — the canvas,
right panel, and timeline stay put while the menu draws on top. This
behavior is delivered by **Blocker 1** below; today's inline-expanding
`Menu` is unsuitable for the top menu bar because every open/close
would reshape the editor.

Each `Button` inside an open menu is independently clickable,
keyboard-focusable, and scrolls into view. The `systemHint` form
shown above (the gray, right-aligned shortcut suffix) is delivered by
**Blocker 2** below; it renders consistently across menu rows and
toolbar items without the menu definitions having to hand-compose
layout.

### 2. Options bar (row 1)

Context-sensitive. Always shows the tool name on the left and the
swap-color affordance on the right; what sits between is tool-specific.

| Active tool   | Options bar contents (left → right)                                   |
| ------------- | --------------------------------------------------------------------- |
| Pen `✎`       | name • primary chip • brush size stepper (future) • palette quick row |
| Eraser `⌫`    | name • affected layer (current) • palette quick row                   |
| Bucket `⬢`    | name • primary chip • "respect selection" toggle • tolerance (future) |
| Gradient `◐`  | name • primary chip • → • secondary chip • "respect selection" toggle |
| Marquee `▭`   | name • selection rect WxH • [Confirm] [Clear] buttons                 |
| Eyedropper `⊙`| name • last-picked color readout                                      |

Each chip is a `Button` showing a 4-cell color block. Clicking the
primary chip opens a palette `Menu` to assign; right-click (or
`Alt+click`) sets secondary. The `[Confirm]` / `[Clear]` buttons mirror
`Enter` and `Esc`.

### 3. Left tool dock (3 cells wide)

Single icon column, pure buttons. Each row is one cell tall. Active
tool gets a colored highlight. Below the tools, a thin divider, then
the primary/secondary color stack with a swap button, mirroring
Photoshop's bottom-of-toolbox arrangement.

```swift
VStack(spacing: 0) {
  ForEach(EditorTool.allCases) { tool in
    Button(action: { model.selectTool(tool) }) {
      Text(tool.iconGlyph)            // ✎ ⌫ ⬢ ◐ ▭ ⊙
        .foregroundStyle(tool == model.tool ? .tint : .muted)
        .frame(width: 1, height: 1)
    }
    .help(tool.label)                  // tooltip: "Pen (P)"
  }
  Divider()
  Button(action: { /* primary picker */ }) {
    Rectangle().fill(primary.toTerminalColor()).frame(width: 1, height: 1)
  }
  Button(action: { /* secondary picker */ }) {
    Rectangle().fill(secondary.toTerminalColor()).frame(width: 1, height: 1)
  }
  Button(action: { model.swapPrimaryAndSecondary() }) {
    Text("⇄").foregroundStyle(.muted)
  }
  Spacer()
}
.frame(width: 3)
.border(.separator, set: .single)
```

#### Tool icon glyphs (final)

| Tool       | Glyph | Notes                                                       |
| ---------- | ----- | ----------------------------------------------------------- |
| Pen        | `✎`   | U+270E — pencil. Renders cleanly in monospace fonts.        |
| Eraser     | `⌫`   | U+232B — erase-to-the-left. Universally available.          |
| Bucket     | `⬢`   | U+2B22 — solid hexagon, suggests filled region.             |
| Gradient   | `◐`   | U+25D0 — half-filled circle.                                |
| Marquee    | `▭`   | U+25AD — rectangle outline.                                 |
| Eyedropper | `⊙`   | U+2299 — circled dot, suggests sample point.                |
| Swap P/S   | `⇄`   | U+21C4 — bidirectional arrows.                              |

> **Why no emoji.** Apple Terminal renders 🪣 / 💧 / 🧽 as wide-cell glyphs
> with hidden offsets, breaking the half-block grid. Mathematical and
> arrow blocks above are guaranteed single-cell-width and align with
> ASCII baselines.

### 4. Right panel (14 cells wide)

Three stacked sub-panels with collapsing borders. From top to bottom:

#### 4a. Color panel (4 rows)

```
┌Color───────┐
│P  ████ #FF66AA│
│S  ████ #1133AA│
│      ⇄        │
└──────────────┘
```

The two color chips are buttons; clicking pops a `Menu` over a 4×8
palette grid (32 swatches) to reassign. The swap button mirrors
keyboard `x`.

#### 4b. Palette panel (4 rows)

```
┌Palette─────┐
│■■■■■■■■■■■■│
│■■■■■■■■■■■■│
│■■■■■■■■■■■■│
└────────────┘
```

Every swatch is a 1×1 cell `Button`:
- Left-click → set primary.
- `Shift+click` (or right-click on hosts that support it, falling back
  to a long-press `Menu`) → set secondary.
- Hover → tooltip shows hex code and slot number `#FF66AA · slot 3`.

The first 9 slots are labeled `1`..`9` in the bottom-right corner of
the swatch (using `ZStack`) to expose the keyboard mapping.

#### 4c. Layers panel (flex)

Photoshop-style: top of the list is the visually-frontmost layer.
Each row has eye toggle, name, and reorder/edit affordances revealed
on hover/focus.

```
┌Layers──────────┐
│● Layer 2  ▲ ▼ ✕│  ← selected, .tint
│○ Layer 1  ▲ ▼ ✕│
├────────────────┤
│  ＋ New layer  │
└────────────────┘
```

| Glyph | Action                                  | Mirrors          |
| ----- | --------------------------------------- | ---------------- |
| `●`/`○` | Toggle layer visibility               | Alt+H            |
| `▲`   | Move layer up (select layer above)      | Alt+K            |
| `▼`   | Move layer down (select layer below)    | Alt+J            |
| `✕`   | Delete layer                            | Alt+X            |
| `＋`  | New layer button                        | Alt+N            |

Click the row body anywhere except the icons to make that layer
current.

### 5. Timeline strip (row N-2)

```
Frames ◀◀ ◀  ▣ ▣[▣]▣ ▣ ▣ ▣  ▶ ▶▶   ＋ ⎘ ✕   delay 10cs ⊖⊕   =all
```

Inline buttons, all clickable:

| Glyph  | Action                          | Mirrors |
| ------ | ------------------------------- | ------- |
| `◀◀`   | First frame                     | (new)   |
| `◀`    | Previous frame                  | Alt+,   |
| `▶`    | Next frame                      | Alt+.   |
| `▶▶`   | Last frame                      | (new)   |
| `＋`   | New blank frame after current   | Ctrl+N  |
| `⎘`    | Duplicate current frame         | Ctrl+D  |
| `✕`    | Delete current frame            | Alt+D   |
| `⊖`    | Decrease delay 10cs             | Alt+-   |
| `⊕`    | Increase delay 10cs             | Alt+=   |
| `=all` | Equalize all delays to current  | Alt+0   |

Each thumbnail is a `Button`. Active frame is wrapped in `[ ]` and
highlighted with `.tint`. Click → set `currentFrameIndex`. The strip
itself is a horizontal `ScrollView` so timelines longer than the
terminal width remain navigable; the buttons above scroll into view.

### 6. Status strip (row N-1)

```
[16, 8]  L1/1  half-cell                          Pen — Space paints
```

Pure text, no buttons. Equivalent of the current footer; the difference
is that *all of its hints are now redundant* because every action is
clickable. The status strip therefore drops to 1 row and is muted; it
serves diagnostic readout only (cursor, layer count, render mode, plus
`statusMessage` from the model on the right).

---

## Mouse-parity matrix

Every keyboard shortcut → a clickable target. **Bold** rows are new
mouse affordances introduced by this redesign.

### Tools

| Shortcut | Action            | Mouse target                                      |
| -------- | ----------------- | ------------------------------------------------- |
| `p`      | Pen               | **Tool dock `✎` button**                          |
| `e`      | Eraser            | **Tool dock `⌫` button**                          |
| `b`      | Bucket fill       | **Tool dock `⬢` button**                          |
| `g`      | Gradient          | **Tool dock `◐` button**                          |
| `m`      | Marquee           | **Tool dock `▭` button**                          |
| `i`      | Eyedropper        | **Tool dock `⊙` button**                          |
| `x`      | Swap P/S          | **Tool dock `⇄` button** + Color panel `⇄`       |
| `Space`  | Apply tool        | Canvas drag/click already handles this; **also options-bar `[Confirm]` button when in marquee/gradient** |
| `Enter`  | Confirm marquee   | **Options-bar `[Confirm]` button**                |
| `Esc`    | Clear selection   | **Options-bar `[Clear]` + Edit menu**             |
| `?`      | Help              | **Help menu → Keyboard Shortcuts**                |

### Cursor

| Shortcut             | Action               | Mouse target                                                |
| -------------------- | -------------------- | ----------------------------------------------------------- |
| Arrows / `hjkl`      | 1-pixel cursor move  | Canvas click (already)                                      |
| Ctrl+Arrows          | 8-pixel jump         | Canvas click (always direct positioning); not needed as button |

### Frames

| Shortcut | Action                | Mouse target                                                   |
| -------- | --------------------- | -------------------------------------------------------------- |
| Alt+,    | Previous frame        | **Timeline `◀` button + Frame menu**                           |
| Alt+.    | Next frame            | **Timeline `▶` button + Frame menu**                           |
| Ctrl+N   | New frame             | **Timeline `＋` button + Frame menu**                          |
| Ctrl+D   | Duplicate frame       | **Timeline `⎘` button + Frame menu**                           |
| Alt+D    | Delete frame          | **Timeline `✕` button + Frame menu**                           |
| Alt+-    | Decrease delay        | **Timeline `⊖` button + Frame menu**                           |
| Alt+=    | Increase delay        | **Timeline `⊕` button + Frame menu**                           |
| Alt+0    | Equalize all delays   | **Timeline `=all` button + Frame menu**                        |

### Layers

| Shortcut | Action                  | Mouse target                                            |
| -------- | ----------------------- | ------------------------------------------------------- |
| Alt+N    | New layer               | **Layers panel `＋` button + Layer menu**               |
| Alt+J    | Layer below             | **Layers row `▼` button + clicking row + Layer menu**   |
| Alt+K    | Layer above             | **Layers row `▲` button + clicking row + Layer menu**   |
| Alt+H    | Toggle visibility       | **Layers row `●`/`○` toggle + Layer menu**              |
| Alt+X    | Delete layer            | **Layers row `✕` button + Layer menu**                  |

### Clipboard

| Shortcut | Action  | Mouse target              |
| -------- | ------- | ------------------------- |
| Ctrl+C   | Copy    | **Edit menu → Copy**      |
| Ctrl+V   | Paste   | **Edit menu → Paste**     |

### Palette

| Shortcut       | Action               | Mouse target                                                |
| -------------- | -------------------- | ----------------------------------------------------------- |
| `1`..`9`       | Pick primary slot    | **Palette swatch click**                                    |
| Alt+`1`..`9`   | Pick secondary slot  | **Palette swatch shift-click + Color panel S chip**         |

### File / app

| Shortcut | Action          | Mouse target                            |
| -------- | --------------- | --------------------------------------- |
| Ctrl+S   | Save            | **File menu → Save**                    |
| Alt+S    | Save As         | **File menu → Save As…**                |
| Ctrl+R   | Resize canvas   | **File / Image menu → Resize Canvas…** (opens a Picker sheet for 16/24/32/48/64) |
| Ctrl+Q   | Quit            | **File menu → Quit**                    |

---

## Tool options bar — concrete contents

```swift
struct ToolOptionsBar: View {
  let model: EditorViewModel

  var body: some View {
    HStack(spacing: 2) {
      Text(model.tool.iconGlyph + " " + model.tool.label)
        .foregroundStyle(.tint)

      Divider()

      switch model.tool {
      case .pen, .eraser:
        ColorChipButton(role: .primary, model: model)
        Stepper("size \(model.brushSize)", value: $model.brushSize, in: 1...8)
      case .fill:
        ColorChipButton(role: .primary, model: model)
        Toggle("respect selection", isOn: $model.fillRespectsSelection)
      case .gradient:
        ColorChipButton(role: .primary, model: model)
        Text("→")
        ColorChipButton(role: .secondary, model: model)
        Toggle("respect selection", isOn: $model.gradientRespectsSelection)
      case .marquee:
        if let sel = model.selection {
          Text("\(sel.rect.width)×\(sel.rect.height) @ (\(sel.rect.minX),\(sel.rect.minY))")
        } else if model.pendingMarqueeAnchor != nil {
          Text("anchor set — move and confirm")
        } else {
          Text("drag or click to anchor")
        }
        Button("Confirm") { model.applyToolAtCursor() }
        Button("Clear")   { model.clearSelection() }
      case .eyedropper:
        ColorChipButton(role: .primary, model: model)
        Text(hex(model.document.palette[model.primaryColorIndex]))
      }

      Spacer()

      Button(action: { model.swapPrimaryAndSecondary() }) {
        Text("⇄ swap")
      }
      Button(action: { isHelpPresented = true }) { Text("[?]") }
    }
    .padding(.horizontal, 1)
  }
}
```

`brushSize`, `fillRespectsSelection`, and `gradientRespectsSelection`
are net-new model fields. The current implementation paints
single-pixel strokes and ignores selection for fill/gradient outside
their default behavior; the spec assumes those toggles are wired up
during the redesign.

---

## Implementation plan (suggested phases)

These are **ordered**: each phase compiles, tests pass, and the editor
remains usable.

> **Phase 0 is the blockers below.** Phase 1 must not begin until all
> four blockers have landed and shipped on `main` — every later phase
> assumes overlay-rendering menus, `Button.systemHint`, working
> `model.undo()` / `model.redo()`, and `model.brushSize`.

### Phase status

| Phase | Status | Notes |
| ----- | ------ | ----- |
| 0 (blockers) | ✅ landed | All four blockers shipped. |
| 1 — Layout skeleton | ✅ landed | 6-region body, 3-cell tool dock, right panel stack, bottom timeline + status. |
| 2 — Menu bar | ✅ landed | 7 menus, 25+ clickable items, shortcut hints via `.systemHint`. |
| 3 — Inline button affordances | ✅ landed | Tool dock, palette, layers, and timeline are now fully clickable. |
| 4 — Tool options bar | ⏳ pending | Contextual options + brush stepper + Confirm/Clear. |
| 5 — Polish | ⏳ pending | View-menu visibility toggles, pixel grid mode picker, resize-canvas sheet, hover tooltips. |

### Phase 1 — Layout skeleton

1. Replace the body's `VStack` with the new 6-region layout.
2. Move the toolbox into a 3-cell wide icon-only column. Keep its
   keyboard bindings unchanged. Switch glyphs to the table above.
3. Move the existing palette and layer views into a 14-cell wide right
   panel `VStack` with collapsing borders. Stack order: Color, Palette,
   Layers.
4. Move the timeline into the bottom strip; collapse the existing
   header into a single status row.

No new actions yet — every shortcut still works, the layout just looks
Photoshop-shaped. Tests in `CanvasViewTests`, `EditorViewModelTests`
should keep passing without changes.

### Phase 2 — Menu bar

1. Add a top-row `HStack` of `Menu` controls (File / Edit / Image /
   Layer / Select / Frame / View / Help).
2. Each menu item is a `Button` that invokes the same model methods
   the keyboard bindings call.
3. Add a `Button.systemHint(_:)` view modifier or in-label
   right-aligned hint text (`HStack { Text(label); Spacer(); Text(hint).muted }`).

This is the largest "discoverability win" — every action becomes
clickable in one place.

### Phase 3 — Inline button affordances

1. Layers panel: per-row `▲ ▼ ✕` buttons + visibility toggle button +
   `＋ New layer` footer button.
2. Timeline: prepend `◀◀ ◀`, append `▶ ▶▶ ＋ ⎘ ✕ delay ⊖⊕ =all`. Make
   each thumbnail a `Button`.
3. Tool dock: add `⇄` swap, primary/secondary chips below the tool
   list.
4. Palette: every swatch becomes a `Button` (left-click = primary,
   shift-click = secondary). Add `1`..`9` corner labels.

### Phase 4 — Tool options bar

1. Add `ToolOptionsBar` (row 1).
2. Wire up `fillRespectsSelection`, `gradientRespectsSelection` model
   fields. (`model.brushSize` is already in place via Blocker 4 — the
   options-bar stepper just binds to it.)
3. Add `Confirm` / `Clear` buttons that mirror `Enter` / `Esc` for
   marquee mode.

### Phase 5 — Polish

1. `View` menu toggles for hiding tool dock / right panel / timeline
   so a user with a narrow terminal can claim the canvas back.
2. `View → Pixel Grid Mode` `Picker` to flip between `.fullCell` and
   `.verticalHalfBlock` rendering.
3. Resize-canvas `Picker` sheet (currently `Ctrl+R` cycles silently).
4. Hover tooltips: every tool/icon button shows its label + shortcut
   in the status strip on hover (already supported via `.help(_:)` in
   the framework, fall back to a custom hover modifier if not).

---

## Blockers — landed (Phase 0 complete)

All four blockers below have shipped. Phase 1 of the redesign can
begin.

| # | Blocker                                            | Status |
| - | -------------------------------------------------- | ------ |
| 1 | Framework: dropdown menus render as overlays       | ✅ landed |
| 2 | Framework: `Button.systemHint(_:)` modifier        | ✅ landed |
| 3 | App: undo/redo on `EditorViewModel`                | ✅ landed (already existed) |
| 4 | App: variable brush size                           | ✅ landed |

### Blocker 1 — Framework: dropdown menus must render as overlays

**Status: landed.**

`Menu` no longer expands inline. Activating a menu emits a presentation
declaration that the sheet coordinator picks up and renders as an
overlay (chrome variant `.menu`) above sibling views. Opening or
closing a menu does NOT reflow the canvas, right panel, or timeline.

**Delivered:**

- `Menu` wraps its trigger row with `BuiltinSheetPresentationModifier`
  using a new `menuPromptPresentationSpec()` (token `"menu"`, chrome
  `.menu`). The trigger row stays inline at exactly 1 cell of height;
  expanded content lives in the overlay layer.
- New `PresentationChrome.menu` case in `PresentationCoordinator.swift`
  with rendering in `PromptPresentationSurface` — compact,
  intrinsic-width bordered box with no header.
- `MenuSurfaceTests.menuTriggerHeightDoesNotGrowWhenExpanded` pins the
  no-pushdown invariant: a sentinel `Text("BELOW")` placed below the
  menu sits at the same row whether the menu is closed or open.
- Keyboard `Esc` dismissal works via the existing
  `topmostEscapeDismissAction` route (sheet/menu/dialog precedence).

**v1 caveats** (tracked as future work, not redesign-blocking):

1. Menus anchor at the presentation host's top-leading rather than
   tracking their source frame. Acceptable for top-row menu bars.
   Source-anchored positioning needs a frame-plumbing change to the
   presentation system.
2. The menu shares the sheet coordinator, so opening a menu disables
   interaction with surrounding controls until it closes (the sheet
   coordinator's `disablesBaseInteractionWhenActive`). Pressing Escape
   closes the menu and restores interaction. A dedicated
   `MenuPresentationCoordinator` with non-disabling base interaction
   is the v2 follow-up.
3. Click-outside-to-dismiss is not yet wired up — Escape is the
   canonical close. (Clicking another menu's trigger opens that menu;
   the previously-open menu remains in the store but is no longer the
   topmost item, so it doesn't render until the new menu closes.)

**Touched:** `Sources/View/Controls/Menu.swift`,
`Sources/View/Controls/MenuRendering.swift`,
`Sources/View/Presentation/PresentationCoordinator.swift`,
`Sources/View/Presentation/PresentationModifiers.swift`,
`Tests/TerminalUITests/MenuSurfaceTests.swift`.

### Blocker 2 — Framework: `Button.systemHint(_:)` integrated with the toolbar

**Status: landed.**

`Button` gained a `systemHint(_:)` chaining method. The hint renders
inside the button's label area as `HStack { label; Spacer(minLength: 1); Text(hint).muted }`,
so chrome (focus highlight, press state, role coloring) covers it
uniformly. `ToolbarItemConfig` gained an optional `systemHint:` field
that the toolbar's per-item button picks up via the same modifier.

**Delivered:**

- `Button.systemHint(_:)` chaining method that stores normalized hint
  text on a new `package var systemHintText: String?` field.
- `Button.normalizeSystemHint(_:)` static helper that trims whitespace
  and folds empty/whitespace-only hints to `nil` (no ghost spacer).
- Hint rendering wired into `resolvedNode` so every existing
  `ButtonStyle` paints it without per-style changes.
- `ToolbarItemConfig.systemHint: String?` plumbed through
  `ToolbarItemButton` to call `.systemHint(...)` on the rendered
  button.
- `ButtonSystemHintTests` (7 tests) covers: alongside-label rendering,
  trailing-edge alignment when a row has spare width, flush rendering
  when the row is intrinsically sized, suppression for nil/empty/
  whitespace hints, normalization, and toolbar-item propagation.

**Touched:** `Sources/View/Controls/Button.swift`,
`Sources/View/ActionScopes/ToolbarItem.swift`,
`Sources/View/ActionScopes/Toolbar.swift`,
`Tests/TerminalUITests/ButtonSystemHintTests.swift`.

### Blocker 3 — App: undo/redo on `EditorViewModel`

**Status: landed (already in place when the spec was reviewed).**

`EditorViewModel` already carries a snapshot-based history stack with
`canUndo` / `canRedo`, `undo()` / `redo()` methods, dirty-tracking by
generation counter, save-resets-clean-generation, drag-grouping (a pen
or eraser stroke is one undo entry), and limit (`historyLimit = 100`).
`Ctrl+Z` / `Ctrl+Y` are wired up in `EditorKeyBindings.applyHistoryBindings`.
Coverage in `EditorViewModelTests` confirms drag grouping, redo
clearing on new edit, and dirty interaction with save.

### Blocker 4 — App: variable brush size

**Status: landed.**

Pen and eraser strokes now stamp a centered `thickness × thickness`
square (pencil-style square brush) at every Bresenham step, with
selection-clipping support. Brush size is clamped to `1...8` on the
view model and toggleable from the keyboard.

**Delivered:**

- `ToolOps.line(on:from:to:color:thickness:selection:)` — adds two
  defaulted parameters. `thickness == 1` preserves the original
  single-pixel behavior; even diameters bias one cell down/right of
  the geometric center so every stamp covers at least the requested
  point.
- `EditorViewModel.brushSize: Int` (1...8 clamped via didSet).
- `EditorViewModel.increaseBrushSize()` / `decreaseBrushSize()` with
  status-message announcements at min/max.
- `[` / `]` keyboard bindings in `EditorKeyBindings.handleFocusedEditorKey`.
- `applyToolAtCursor` for pen/eraser routes through `strokeCurrentLayer`
  (a self-loop line) so the brush size always applies — single click
  and drag use the same stamp pipeline.
- Tests: 5 new ToolOps tests (3×3 stamp, even-2 bias, thick eraser
  band, selection clipping, default-thickness preservation) and 4 new
  view-model tests (clamp range, thick click, thick drag as one undo
  entry, thick eraser drag as one undo entry).

**Touched:** `Sources/GIFEditorCore/Tools.swift`,
`Sources/GIFEditorUI/EditorViewModel.swift`,
`Sources/GIFEditorUI/EditorKeyBindings.swift`,
`Tests/GIFEditorCoreTests/ToolOpsTests.swift`,
`Tests/GIFEditorUITests/EditorViewModelTests.swift`.

---

## Accepted decisions

(Items reviewed and accepted as-is; **no work required before the
redesign**. They are recorded here so future readers know they were
considered explicitly.)

1. **Right-click on swatches.** swift-terminal-ui's pointer model
   exposes click events reliably; secondary-button events are
   host-dependent. The spec uses `Shift+click` for "set as secondary,"
   with right-click added opportunistically on hosts that report it,
   and a long-press fallback that opens a swatch `Menu` (now overlay,
   per Blocker 1).

2. **Color picker beyond the 32 visible slots.** A 4×8 grid covers
   slots 0..31. When a loaded GIF uses palette indices `>= 32`, the
   palette panel grows a `▼ More…` button at its bottom that opens a
   16×16 (256-slot) `Menu` overlay. For default 32-slot documents,
   that button is absent.

3. **Status hints removed from the bottom strip.** The bottom status
   strip drops the "Space paints" / "Space again" prompts because the
   new options bar surfaces tool state directly. The strip remains
   for cursor coordinates, layer counter, render mode, and
   `model.statusMessage`. The current `toolHint` text in
   `ToolboxView.swift` is deleted as part of Phase 1.

---

## File touch list

Expected diffs (UI only — `GIFEditorCore` is untouched):

- `EditorView.swift` — replace body with 6-region layout, embed
  `MenuBarView`, `OptionsBarView`, new tool dock, panel stack, timeline
  strip, status strip.
- `ToolboxView.swift` → `ToolDockView.swift` — 3-cell wide icon column.
- `PaletteView.swift` — swatches become `Button`s; add corner labels
  for 1..9.
- `LayerListView.swift` — per-row buttons (`▲ ▼ ✕`, eye toggle), `＋`
  footer.
- `TimelineView.swift` — prepend nav buttons, append frame ops + delay
  stepper.
- **new** `MenuBarView.swift` — top-row menus.
- **new** `ToolOptionsBar.swift` — context-sensitive options.
- **new** `ColorChipButton.swift` — primary/secondary chip control.
- `EditorViewModel.swift` — add `fillRespectsSelection`,
  `gradientRespectsSelection` (phase 4 only). `brushSize`, `undo`,
  and `redo` already exist via Blockers 3 and 4.
- `EditorTool.swift` (in `GIFEditorCore`) — add `iconGlyph` returning
  the new unicode glyph (the existing `glyph` returns letters and is
  used by the help screen; keep both).
- `EditorHelpView.swift` — refresh shortcut copy to mention the
  equivalent menu paths ("Save (Ctrl+S, File → Save)").

Tests:

- `CanvasViewTests` — unchanged.
- `EditorViewModelTests` — add coverage for `respectSelection`
  toggles when those land. (`brushSize` and undo/redo coverage
  already in place via Blockers 3 and 4.)
- **new** `MenuBarTests.swift` — assert each menu item invokes the same
  model method the equivalent keyboard binding does (parity test).
- **new** `ToolOptionsBarTests.swift` — assert that switching tools
  swaps the options view in the expected way.
