# gifeditor

A terminal-native GIF editor built on **swift-terminal-ui**. Read and write
animated GIFs, edit them frame-by-frame on a pixel grid where one GIF pixel
maps to one terminal cell, and use a small toolbox of pen / eraser / fill /
gradient / marquee tools.

This example is intentionally split across four targets so it can grow into a
multi-platform app later without restructuring:

| Target           | Role                                         | Depends on             |
| ---------------- | -------------------------------------------- | ---------------------- |
| `GIFEditorCore`  | Pure model + GIF89a encoder/decoder bridge   | `GIF` (decoder), Foundation |
| `GIFEditorUI`    | Terminal `View` tree + view model            | `TerminalUI`, `GIFEditorCore` |
| `GIFEditor`      | Composition root (entry point factory)       | `GIFEditorUI`, `TerminalUI` |
| `gifeditor`      | Executable that hosts the terminal app       | `GIFEditor`, `TerminalUICLI` |

A future SwiftUI / UIKit port would reuse `GIFEditorCore` verbatim and add a
parallel `GIFEditorUI_SwiftUI` target alongside `GIFEditorUI`.

## Run

```bash
cd Examples/gifeditor
swift run gifeditor                       # launch with a fresh 32x32 document
swift run gifeditor ../../nyan.gif        # launch editing a real GIF
```

After making edits, press `Ctrl+S` to save (back to the source path or to
`./untitled.gif` for new documents). Use `Ctrl+Shift+S` to save-as a new path.

## Keybindings

Single-letter shortcuts without a modifier are reserved by the framework for
typing, arrow navigation, Tab, Enter and Escape, so every editor command
includes a modifier.

### Tools (`Ctrl+<letter>`)

| Shortcut      | Tool                                    |
| ------------- | --------------------------------------- |
| `Ctrl+P`      | **P**en — paint the primary color      |
| `Ctrl+E`      | **E**raser — clear to transparent       |
| `Ctrl+B`      | **B**ucket fill (4-connected)           |
| `Ctrl+G`      | **G**radient between primary/secondary |
| `Ctrl+M`      | **M**arquee — rectangular selection    |
| `Ctrl+I`      | Eyedropper — pick color from cursor    |
| `Ctrl+X`      | Swap primary and secondary color       |

### Cursor (within the canvas)

The framework reserves bare arrow keys for focus navigation, so cursor
movement uses Shift+Arrow / Ctrl+Arrow / Vi-style movement with Shift.

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Shift+←/→/↑/↓`   | Move cursor by 1 pixel                   |
| `Ctrl+←/→/↑/↓`    | Move cursor by 8 pixels                  |
| `Shift+H/J/K/L`   | Vi-style 1-pixel movement                |
| `Shift+Space`     | Apply the current tool at the cursor     |
| `Shift+Enter`     | Confirm marquee (commit selection rect)  |

### Frames / timeline

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+,`          | Previous frame                           |
| `Ctrl+.`          | Next frame                               |
| `Ctrl+N`          | New blank frame after current            |
| `Ctrl+D`          | Duplicate current frame after current    |
| `Ctrl+Shift+D`    | Delete current frame                     |
| `Ctrl+[`          | Decrease current frame delay (10 cs)     |
| `Ctrl+]`          | Increase current frame delay (10 cs)     |
| `Ctrl+0`          | Reset all frame delays to current value  |

### Layers

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+Shift+N`    | New empty layer above current            |
| `Ctrl+Shift+J`    | Select layer below                       |
| `Ctrl+Shift+K`    | Select layer above                       |
| `Ctrl+Shift+H`    | Toggle current layer visibility          |
| `Ctrl+Shift+X`    | Delete current layer                     |

### Clipboard

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+C`          | Copy selection (or whole layer if none)  |
| `Ctrl+V`          | Paste at cursor                          |
| `Ctrl+Z`          | Undo last edit                           |
| `Ctrl+Shift+Z`    | Redo                                     |

### Palette / colors

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+1`..`Ctrl+9`| Pick palette slot 1..9 as primary        |
| `Alt+1`..`Alt+9`  | Pick palette slot 1..9 as secondary      |

### File / app

| Shortcut          | Action                                    |
| ----------------- | ----------------------------------------- |
| `Ctrl+S`          | Save                                     |
| `Ctrl+Shift+S`    | Save As (writes `./untitled.gif`)        |
| `Ctrl+R`          | Resize canvas (cycles 16/24/32/48/64)    |
| `Ctrl+Q`          | Quit (also `Ctrl+C` on the host shell)   |

## Editing model

* The document carries a fixed-size **indexed-color frame buffer** (`UInt8?`
  per pixel — `nil` means transparent) plus a shared **256-slot palette**.
* Every frame is a stack of **layers** painted bottom-to-top. The bottom
  layer's transparent pixels show the canvas's background color; higher
  layers' transparent pixels show whatever painted below them on the same
  frame.
* The exporter flattens layers per frame, then writes a GIF89a file using a
  single global color table. Each frame is written with `.background`
  disposal so frames fully replace their predecessors — easy to reason about
  and matches the editor's "fully painted frame" mental model.

## Remaining framework gaps

The editor's pixel grid now renders through `Canvas` instead of building one
`Rectangle` view per pixel. The remaining gaps are structural/input lifecycle
work outside this Canvas-adaptation branch.

1. **Single-key shortcuts inside an active scope.** Today
   `keyCommand(_:key:modifiers:action:)` requires a non-empty modifier set
   (single-key bindings are reserved for typing/arrow nav/Tab/Enter/Escape).
   That forces every tool shortcut into `Ctrl+<letter>`. A typical pixel
   editor wants bare letters (`p`, `e`, `b`, `g`, `m`) when the canvas owns
   focus. A scope-local `onKeyPress(when: focused) { … }` hook, or letting
   `keyCommand` opt-in to single-key bindings inside a focus-bounded scope,
   would fix this.
2. **Bare arrow keys for cursor movement.** Same root cause: arrow keys are
   framework-reserved for focus navigation, so cursor movement uses
   `Shift+Arrow` / Vi-keys-with-Shift. A canvas-style view that consumes
   arrow keys when focused would let the editor use plain arrows.
3. **Pointer/mouse input on the pixel grid.** Canvas can render full-cell and
   half-block pixel grids, but the editor still needs a public pointer-hit-test
   entry to click-to-paint. Full-cell editing can work from cell mouse
   coordinates; half-block editing needs sub-cell pointer offsets from hosts
   that support them.
4. **`swift-gif` is decode-only.** The vendored decoder has no encoder
   pair, so the editor ships its own GIF89a encoder (LZW + sub-block
   framing) inside `GIFEditorCore`. Promoting that into
   `Vendor/swift-gif` would benefit anything else that wants to write GIFs.
5. **Lifecycle for "save before quit".** The framework currently exits on
   the host's quit keys without firing a Stop hook a view can intercept;
   the editor handles dirty-document save in-app via `Ctrl+S`, but a
   `WindowGroup.onTerminate { … }` would close the loop.

## Tests

```bash
cd Examples/gifeditor
swift test
```

The core test suite verifies:

* GIF89a encoder produces output the (vendored) decoder can read back
  pixel-for-pixel for a hand-built document and a round-trip of `nyan.gif`.
* Document edits (pen, fill, gradient, marquee copy/paste) leave the model
  in expected states.
* The terminal UI renders the editor canvas through Canvas-backed full-cell
  and half-block pixel grids.
