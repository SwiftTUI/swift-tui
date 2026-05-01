# Geometry And Preferences

Use anchor preferences when a subtree needs to publish geometry that another
part of the view tree resolves after layout.

## Overview

Ordinary preferences reduce during view resolution. Anchor preferences follow
that same reduction path, but the value they carry is an opaque geometry token
rather than a concrete rectangle or point. Resolve the token inside
``GeometryReader`` after placement has assigned real bounds.

```swift
private enum BoundsKey: PreferenceKey {
  static let defaultValue: Anchor<Rect>? = nil

  static func reduce(
    value: inout Anchor<Rect>?,
    nextValue: () -> Anchor<Rect>?
  ) {
    value = nextValue() ?? value
  }
}

struct BorderedLabel: View {
  var body: some View {
    Text("Deploy")
      .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
      .overlayPreferenceValue(BoundsKey.self, alignment: .topLeading) { anchor in
        GeometryReader { proxy in
          if let anchor {
            let rect = proxy[anchor]
            Text("\(Int(rect.size.width))x\(Int(rect.size.height))")
          }
        }
      }
  }
}
```

``GeometryProxy`` also exposes ``GeometryProxy/frame(in:)`` for local, global,
and named coordinate-space frames. Named spaces come from
``View/coordinateSpace(name:)``:

```swift
VStack(alignment: .leading) {
  Text("Header")
    .coordinateSpace(name: "header")

  GeometryReader { proxy in
    let frame = proxy.frame(in: .named("header"))
    Text("offset \(Int(frame.origin.y))")
  }
}
```

Named coordinate-space names should be unique in a rendered frame. Duplicate
names currently keep last-writer-wins behavior, and missing names fall back to
global coordinates for compatibility with gesture resolution. Both cases are
recorded in frame diagnostics.

Anchor resolution is intentionally layout-time. Measuring a ``GeometryReader``
or an unselected ``ViewThatFits`` candidate does not realize its authored
content or commit lifecycle, task, gesture, command, drop, focus, or semantic
side effects.

## Container And Layout Boundaries

Containers that defer child placement also defer local geometry. `ScrollView`,
lazy stacks, ``ViewThatFits``, and safe-area containers may measure a
layout-dependent subtree without realizing the `GeometryReader` body. The body
runs only when the selected or visible branch is placed with concrete bounds.

Custom ``Layout`` implementations participate in the same split. Calls to
``LayoutSubview/sizeThatFits(_:)`` measure a subview and must not depend on
`GeometryReader` body side effects. The matching
``LayoutSubview/place(at:anchor:proposal:)`` call establishes the child-local
geometry that `GeometryReader`, anchor preferences, global frames, and named
coordinate spaces observe. Layouts that provide sendable measurement and
placement signatures remain eligible for the frame-tail worker because geometry
realization stays on the placement side of the pipeline.

## Topics

### Anchor Preferences

- `Anchor`
- `AnchorSource`
- ``View/anchorPreference(key:value:transform:)``
- ``View/transformAnchorPreference(_:value:transform:)``

### Geometry Resolution

- ``GeometryReader``
- ``GeometryProxy``
- ``GeometryProxy/frame(in:)``
- ``CoordinateSpace``
- ``View/coordinateSpace(name:)``
