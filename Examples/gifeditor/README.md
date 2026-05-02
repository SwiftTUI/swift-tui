# gifeditor

A terminal-native GIF editor built on **swift-tui**. Read and write
animated GIFs, edit them frame-by-frame on a color canvas where one GIF pixel
maps to one terminal half-cell, and use a small toolbox of pen / eraser / fill /
gradient / marquee tools with keyboard or pointer input.

This example is intentionally split across four targets so it can grow into a
multi-platform app later without restructuring:

| Target           | Role                                         | Depends on             |
| ---------------- | -------------------------------------------- | ---------------------- |
| `GIFEditorCore`  | Pure model + GIF encoder/decoder bridge      | `GIF`, Foundation |
| `GIFEditorUI`    | Terminal `View` tree + view model            | `SwiftTUI`, `GIFEditorCore` |
| `GIFEditor`      | Composition root (entry point factory)       | `GIFEditorUI`, `SwiftTUI` |
| `gifeditor`      | Executable that hosts the terminal app       | `GIFEditor`, `SwiftTUICLI` |

A future SwiftUI / UIKit port would reuse `GIFEditorCore` verbatim and add a
parallel `GIFEditorUI_SwiftUI` target alongside `GIFEditorUI`.

## Run

```bash
cd Examples/gifeditor
swift run gifeditor                       # launch with a fresh 32x32 document
swift run gifeditor ../../nyan.gif        # launch editing a real GIF
```

After making edits, press `Ctrl+S` to save (back to the source path or to
`./untitled.gif` for new documents). Use `Alt+S` to save-as a new path.

## Keybindings

Focused editor commands use bare keys where they map to ordinary pixel-editor
actions.

The bindings avoid terminal-ambiguous chords such as `Ctrl+Shift+letter`,
`Ctrl+digit`, `Ctrl+[` / `Ctrl+]`, and `Alt+[`, because the current terminal
input path does not receive those as distinct key presses. Press `?` in the
editor to open the same shortcut reference in-app.

### Tools

| Shortcut      | Tool                                    |
| ------------- | --------------------------------------- |
| `p`           | **P**en — paint the primary color      |
| `e`           | **E**raser — clear to transparent       |
| `b`           | **B**ucket fill (4-connected)           |
| `g`           | **G**radient between primary/secondary |
| `m`           | **M**arquee — rectangular selection    |
| `i`           | Eyedropper — pick color from cursor    |
| `x`           | Swap primary and secondary color       |
| `Space`       | Apply the current tool at the cursor    |
| `Enter`       | Confirm marquee (commit selection rect) |
| `Escape`      | Clear selection                         |
| `?`           | Open keyboard help                      |

The canvas also supports direct pointer editing. Drag with **Pen** or
**Eraser** to paint connected strokes, drag with **Marquee** to select a
rectangle, drag with **Gradient** to apply a gradient between the drag endpoints,
and click with **Fill** or **Eyedropper** to target a single pixel. Hosts that
report terminal-pixel pointer locations can address the top and bottom half of a
cell independently; cell-only hosts fall back to the top half of each terminal
cell.

### Cursor (within the canvas)

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `←/→/↑/↓`         | Move cursor by 1 pixel                   |
| `Ctrl+←/→/↑/↓`    | Move cursor by 8 pixels                  |
| `h/j/k/l`         | Vi-style 1-pixel movement                |

### Frames / timeline

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Alt+,`           | Previous frame                           |
| `Alt+.`           | Next frame                               |
| `Ctrl+N`          | New blank frame after current            |
| `Ctrl+D`          | Duplicate current frame after current    |
| `Alt+D`           | Delete current frame                     |
| `Alt+-`           | Decrease current frame delay (10 cs)     |
| `Alt+=`           | Increase current frame delay (10 cs)     |
| `Alt+0`           | Reset all frame delays to current value  |

### Layers

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Alt+N`           | New empty layer above current            |
| `Alt+J`           | Select layer below                       |
| `Alt+K`           | Select layer above                       |
| `Alt+H`           | Toggle current layer visibility          |
| `Alt+X`           | Delete current layer                     |

### Clipboard

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+C`          | Copy selection (or whole layer if none)  |
| `Ctrl+V`          | Paste at cursor                          |

### History

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+Z`          | Undo last document edit                   |
| `Ctrl+Y`          | Redo last undone edit                     |

### Palette / colors

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `1`..`9`          | Pick palette slot 1..9 as primary        |
| `Alt+1`..`Alt+9`  | Pick palette slot 1..9 as secondary      |

### File / app

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+S`          | Save                                     |
| `Alt+S`           | Save As (writes `./untitled.gif`)        |
| `Ctrl+R`          | Resize canvas (cycles 16/24/32/48/64)    |
| `Ctrl+Q`          | Quit                                     |
| `?`               | Open keyboard help                       |

## Editing model

* The document carries a fixed-size **indexed-color frame buffer** (`UInt8?`
  per pixel — `nil` means transparent) plus a shared **256-slot palette**.
* Every frame is a stack of **layers** painted bottom-to-top. The bottom
  layer's transparent pixels show the canvas's background color; higher
  layers' transparent pixels show whatever painted below them on the same
  frame.
* Document edits are captured in a bounded undo / redo stack. Pointer strokes
  and pointer-applied gradients are grouped as single history entries.
* The exporter flattens layers per frame, then writes a GIF89a file using a
  single global color table. Each frame is written with `.background`
  disposal so frames fully replace their predecessors — easy to reason about
  and matches the editor's "fully painted frame" mental model.

## Tests

```bash
cd Examples/gifeditor
swift test
```

The core test suite verifies:

* The `swift-gif` encoder bridge produces output the decoder can read back
  pixel-for-pixel for a hand-built document and a round-trip of `nyan.gif`.
* Document edits (pen, fill, gradient, marquee copy/paste) leave the model
  in expected states.
* The terminal UI renders the editor canvas through a Canvas-backed half-block
  color grid and maps sub-cell pointer locations onto GIF pixels.
