# Scrolling

Present overflowing content in a fixed viewport and move it with the keyboard,
the mouse wheel, the indicators, or code.

## Overview

A ``ScrollView`` clips its content to whatever space the layout gives it and
exposes the rest one cell at a time. Offsets are cell-denominated: the scroll
position is a ``ScrollCellOffset`` holding integer `x` and `y` cell counts,
and every movement — keys, wheel, indicator drags, and imperative commands —
clamps to the scrollable range. Scrolling moves only the visible window; it
never moves focus or selection.

## Present Scrollable Content

Pass the scrollable axes to the initializer; the default is `.vertical`. The
viewport is whatever the surrounding layout proposes, so give the scroll view
a finite frame along each scrollable axis:

```swift
ScrollView(.vertical) {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(entries, id: \.id) { entry in
      Text(entry.title)
    }
  }
}
.frame(height: 8, alignment: .topLeading)
.border(.separator)
```

The same shape works horizontally, or on both axes with
`[.horizontal, .vertical]`:

```swift
ScrollView(.horizontal) {
  HStack(spacing: 1) {
    ForEach(0..<12, id: \.self) { index in
      Text("item \(index)")
    }
  }
}
.frame(width: 20)
```

## Read And Set The Position

`ScrollView(_:position:content:)` binds the offset to state you own. The
binding is live in both directions: user scrolling writes the new offset back,
and writing the binding moves the viewport on the next frame, clamped to the
content bounds. ``ScrollCellOffset`` carries its own movement vocabulary —
`scrollBy(x:y:)` for relative steps, `scrollTo(x:y:)` for absolute
coordinates, and `scrolledBy(x:y:)` for a non-mutating copy.

```swift
struct LogPane: View {
  @State private var position = ScrollCellOffset.zero

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical, position: $position) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(lines, id: \.self) { line in
            Text(line)
          }
        }
      }
      .frame(height: 8, alignment: .topLeading)
      Text("offset y:\(position.y)")
    }
  }
}
```

## Scroll From Code

``ScrollViewReader`` hands its content a ``ScrollViewProxy`` whose commands
address the first scroll view in the reader's scope. Mark targets with
`id(_:)`, then reach them with ``ScrollViewProxy``'s `scrollTo(_:anchor:)`. A
`nil` anchor reveals the target with the smallest possible movement; `.top`,
`.center`, or `.bottom` align it to the viewport, clamped at the content
edges. The proxy also jumps to an edge with `scrollTo(edge:)`, steps by cells
with `scrollBy(x:y:)`, and sets absolute offsets with `scrollTo(x:y:)`.

```swift
ScrollViewReader { proxy in
  VStack(alignment: .leading, spacing: 0) {
    HStack(spacing: 1) {
      Button("First error") {
        _ = proxy.scrollTo("first-error", anchor: .top)
      }
      Button("End") {
        _ = proxy.scrollTo(edge: .bottom)
      }
    }
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(lines) { line in
          Text(line.text)
            .id(line.isFirstError ? "first-error" : "line-\(line.id)")
        }
      }
    }
    .frame(height: 6, alignment: .topLeading)
  }
}
```

Every proxy command returns a discardable `Bool`: `true` when the command
moved the offset, `false` when nothing moved — either no target matched the
ID, or the content was already in place. Check it when a caller needs to know
whether anything happened; discard it otherwise. Inside a data-backed ``List``
or ``Table``, `scrollTo` reaches a row by ID even when that row is not
currently realized.

## Control The Indicators

Overflowing axes show scroll indicators by default. Tune them per axis with
``View/scrollIndicators(_:axes:)``; the `axes` parameter defaults to both.
`ScrollIndicatorVisibility` offers `.automatic`, `.visible`, `.hidden`, and
`.never`; hiding indicators leaves the content scrollable. The setting flows
through the environment, so one modifier covers every scroll view beneath it.

```swift
ScrollView([.vertical, .horizontal]) {
  contentGrid
}
.scrollIndicators(.hidden, axes: .horizontal)
```

Use ``ScrollViewStyle`` to change indicator and container appearance:

```swift
ScrollView {
  logContents
}
.scrollViewStyle(.minimal)
.frame(height: 8)
```

The automatic style reserves indicator tracks outside the clipped content
viewport. The minimal style overlays the indicators on that viewport. Both
obey `scrollIndicators`, and neither changes the host's panning policy.
Custom styles can supply content insets, single-cell indicator glyphs, paint,
and opacity; <doc:Authoring-Styles> describes the presentation contract.

## Keyboard And Focus

A scroll view is itself focusable: Tab traversal reaches it like any control.
While it has focus, the arrow keys step one cell along the scrollable axes,
Home returns to the start, and End jumps to the far edge — bottom for a
vertical axis, trailing for a horizontal-only one. Each visible indicator is
separately focusable and drives just its own axis; a pointer press or drag on
an indicator track scrubs the offset directly.

Focus and scrolling stay independent, with one deliberate bridge: when focus
moves to a control inside the content — Tab onto a button below the fold —
the viewport scrolls just enough to reveal it. The reveal fires only when
focus changes, so scrolling away afterward does not snap back to the focused
control.

## The Mouse Wheel

Wheel and trackpad scrolling target the scroll view under the pointer — no
focus required. Deltas apply per axis and clamp at the content edges; a wheel
event the innermost scroll view cannot use passes outward, so nested scroll
views hand off at their boundaries. To intercept the wheel before any scroll
view, attach ``View/onScrollWheel(perform:)`` and return
``ScrollWheelResult/handled`` to consume the event or
``ScrollWheelResult/ignored`` to pass it along:

```swift
timelineRow
  .onScrollWheel { event in
    guard event.deltaY != 0 else { return .ignored }
    zoom(by: event.deltaY)
    return .handled
  }
```

On terminals a click-drag over content stays a click-drag; only hosts whose
native paradigm is touch pan the content with a drag.

## Prefer Collection Viewports For Data

For long homogeneous data, reach for ``List`` or ``Table`` with their data
initializers instead of a `ForEach` inside a plain scroll view: collections
window row realization against the viewport, so per-frame cost follows the
visible band rather than the data set. How collections split scrolling from
selection — wheel, paging keys, and arrow-key selection — is covered in
<doc:Collections>.

## See Also

- ``ScrollView``
- ``ScrollViewReader``
- ``ScrollViewProxy``
- ``ScrollCellOffset``
- <doc:Collections>
