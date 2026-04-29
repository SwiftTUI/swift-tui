# canvas-demo

A small verification app for the current `Canvas` API. It exercises the
interactive Braille subcell canvas and the dense pixel-grid canvas variants.

The drawing surface deliberately uses `Canvas(Drawing)` and
`CanvasDrawing.draw(into:)` with Braille subpixel coordinates. Drag input maps
`DragGesture` samples into the active canvas grid. Cell-only mouse samples
anchor to the reported cell origin; true sub-cell samples keep their fractional
position. The cursor and hover crosshair are Canvas overlays so the app stays
inside today's public Canvas surface. The pixel-grid tabs use the same drawing
controls while rendering through the full-cell and vertical half-block Canvas
modes.

## Run

```bash
cd Examples/canvas
swift run canvas-demo
```

## Controls

| Input       | Action                            |
| ----------- | --------------------------------- |
| Arrows      | Move cursor by 1 Braille subpixel |
| H/J/K/L     | Move cursor by 1 Braille subpixel |
| Space/Enter | Paint with the selected tool      |
| D or P      | Select draw tool                  |
| E           | Select erase tool                 |
| C/Backspace | Clear the sketch                  |
| Drag/click  | Paint or erase on the active tab  |
| Hover       | Show sub-cell crosshair when supported |
| Ctrl+C      | Quit via host shell               |

## Tests

```bash
cd Examples/canvas
swift test
```
