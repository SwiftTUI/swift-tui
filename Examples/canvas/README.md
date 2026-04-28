# canvas-demo

A small verification app for the current `Canvas` API. It exists to pin the
baseline before Canvas grows per-cell color, pixel-grid, and half-block
rendering modes.

The drawing surface deliberately uses `Canvas(Drawing)` and
`CanvasDrawing.draw(into:)` with Braille subpixel coordinates. The cursor is a
second Canvas overlay so the app stays inside today's public Canvas surface.

## Run

```bash
cd Examples/canvas
swift run canvas-demo
```

## Controls

| Shortcut      | Action                 |
| ------------- | ---------------------- |
| Shift+Arrows  | Move cursor by 1 dot   |
| Ctrl+Arrows   | Move cursor by 8 dots  |
| Shift+Space   | Draw at cursor         |
| Ctrl+E        | Erase at cursor        |
| Ctrl+K        | Clear drawing          |
| Ctrl+C        | Quit via host shell    |

## Tests

```bash
cd Examples/canvas
swift test
```
