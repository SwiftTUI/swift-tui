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

Anchor resolution is intentionally layout-time. Measuring a ``GeometryReader``
or an unselected ``ViewThatFits`` candidate does not realize its authored
content or commit lifecycle, task, gesture, command, drop, focus, or semantic
side effects.

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
