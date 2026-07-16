# Pointer And Canvas Coordinates

## Overview

SwiftTUI uses one coordinate space for authored interaction and drawing:
continuous terminal cells.

`Point(x: 4.5, y: 2.5)` means the middle of the cell at column 4, row 2. It
does not mean device pixels. Layout still uses integer `CellSize` and
`CellRect`, but direct-manipulation APIs carry the fractional point when the
runtime can obtain it.

## Pointer Input

Use gestures when the interaction has a recognisable shape:

```swift
Canvas(SketchDrawing(points: points))
  .frame(width: 40, height: 12)
  .gesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        points.append(value.location)
      }
  )
```

`DragGesture.Value.location`, `startLocation`, and `translation` are continuous
cell-space values. On a cell-only terminal, the runtime supplies the center of
the reported cell. On native, web, or terminal-pixel input paths, the same API
can carry sub-cell positions.

`DragGesture.Value.path` is complete for the current gesture. It retains samples
from pointer-down through the current value and is cleared when the recognizer
tears down. Persist path samples into app state when a stroke or route should
outlive the active gesture.

For hover-only affordances, use ``View/onPointerHover(_:)``:

```swift
view.onPointerHover { phase in
  switch phase {
  case .entered(let point), .moved(let point):
    hover = point
  case .exited:
    hover = nil
  }
}
```

Hover events are local to the view that installed the handler. The terminal
runtime enables high-volume all-motion reporting only while the rendered tree
contains hover subscribers.

## Gesture Precedence

Use ``View/gesture(_:including:)`` for ordinary recognition and
``View/highPriorityGesture(_:including:)`` when an enclosing interaction must
win before ordinary gestures or controls in its subhierarchy:

```swift
Button("Open") {
  openSelection()
}
.highPriorityGesture(
  TapGesture().onEnded {
    showPreviewInstead()
  }
)
```

Once the high-priority recognizer claims the pointer stream, ordinary sibling
recognizers do not receive it and a descendant control does not activate.
``View/simultaneousGesture(_:including:)`` is the explicit exception: it keeps
receiving the same stream alongside a high-priority recognizer.

All three attachment modifiers honor ``GestureMask``. In particular,
`including: .subviews` omits the gesture at the modified view, while
`including: .gesture` omits descendant gesture attachments.

## Coordinate Spaces And Hit Testing

Local and global coordinate spaces preserve fractional values. Named spaces are
available with ``View/coordinateSpace(name:)``; unresolved names fall back to
global coordinates so authored code keeps working while views are refactored.

Use ``View/contentShape(_:)`` when a view's pointer target is not its full
placed rectangle. Rectangular shapes remain cell-denominated through
`CellRect`; path shapes use continuous ``Path`` values.

## Runtime Capability Display

Read ``GeometryReader`` or ``EnvironmentReader`` when an app needs to show or
adapt to runtime precision:

- `GeometryProxy.pointerInputCapabilities` describes whether events are
  cell-only or sub-cell.
- `GeometryProxy.cellPixelMetrics` describes the runtime's current cell-pixel
  estimate or reported value.

These values are metadata. They should guide optional affordances, not change
the base layout contract.

## Canvas

``Canvas`` drawings receive a ``CanvasContext`` sized in terminal cells.
Drawing methods such as `setPixel(at:)` and `line(from:to:)` accept continuous
cell-space ``Point`` values and pack them into the selected ``CanvasGrid``.

For small ad-hoc drawings, use the closure form:

```swift
Canvas { context in
  context.line(from: .zero, to: Point(x: 10, y: 2.5))
}
```

Closure drawings compare by identity. Use a value type conforming to
``CanvasDrawing`` when a drawing should compare structurally equal across
rerenders.

Dense pixel-grid helpers are still terminal-cell abstractions. Use them for
editor-like surfaces, heatmaps, and previews where each logical pixel is meant
to occupy a full cell or half-block.
