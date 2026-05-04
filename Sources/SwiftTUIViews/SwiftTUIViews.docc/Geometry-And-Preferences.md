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

## Cookbook

The current API is intentionally explicit: publish opaque geometry with
preferences, then resolve it inside ``GeometryReader`` after placement. Prefer
these patterns before adding helper APIs for geometry-change callbacks or
broader geometry effects.

### Draw A Marker Around Child Bounds

Use an anchor preference when the child owns the geometry and an overlay owns
the marker. The marker reads the resolved rectangle in the overlay's local
space, then places a stroked rectangle over the child.

```swift
private enum BoundsMarkerKey: PreferenceKey {
  static let defaultValue: Anchor<Rect>? = nil

  static func reduce(
    value: inout Anchor<Rect>?,
    nextValue: () -> Anchor<Rect>?
  ) {
    value = nextValue() ?? value
  }
}

struct MarkedLabel: View {
  var body: some View {
    Text("Deploy")
      .padding(1)
      .anchorPreference(key: BoundsMarkerKey.self, value: .bounds) { $0 }
      .overlayPreferenceValue(
        BoundsMarkerKey.self,
        alignment: .topLeading
      ) { anchor in
        GeometryReader { proxy in
          if let anchor {
            let rect = proxy[anchor]

            Rectangle()
              .strokeBorder(.terminalBorder(.accent))
              .frame(
                width: Int(rect.size.width),
                height: Int(rect.size.height)
              )
              .offset(
                x: Int(rect.origin.x),
                y: Int(rect.origin.y)
              )
          }
        }
      }
  }
}
```

### Align Overlay To A Named Space

Use ``View/coordinateSpace(name:)`` when the overlay should align to a sibling
or ancestor region instead of the overlay's own local bounds.

```swift
struct HeaderBadge: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Text("Name")
          .frame(width: 12, alignment: .topLeading)
          .coordinateSpace(name: "name-column")

        Text("Status")
      }

      Text("Recorder")
      Text("SwiftTUI")
    }
    .overlay(alignment: .topLeading) {
      GeometryReader { proxy in
        let column = proxy.frame(in: .named("name-column"))

        Text("^")
          .foregroundStyle(.terminalBorder(.accent))
          .offset(
            x: Int(column.origin.x),
            y: Int(column.maxY)
          )
      }
    }
  }
}
```

Named-space lookup is placement-time. Moving the named view inside a
``ScrollView``, lazy stack, safe-area inset, or custom ``Layout`` updates the
resolved frame when the view is placed.

### Diagnose Missing Names

Missing named coordinate spaces fall back to global coordinates so existing
gesture and overlay code keeps rendering. Treat that fallback as a diagnostic
signal, not as a layout contract.

```swift
struct MissingNameProbe: View {
  var body: some View {
    VStack(alignment: .leading) {
      Text("Panel")
        .coordinateSpace(name: "details-panel")

      GeometryReader { proxy in
        // Typo: this name does not match "details-panel".
        let frame = proxy.frame(in: .named("detail-panel"))
        Text("probe \(Int(frame.origin.x)),\(Int(frame.origin.y))")
      }
    }
  }
}
```

When running through a terminal `RunLoop`, install `FrameDiagnosticsLogger`
and inspect the geometry columns:

```swift
runLoop.diagnosticsLogger = FrameDiagnosticsLogger(
  path: "/tmp/swifttui-frames.tsv"
)
```

The TSV columns `geometry_missing_named_coordinate_spaces` and
`first_geometry_missing_named_coordinate_space` identify frames that resolved a
missing name. Duplicate names are also recorded in
`geometry_duplicate_named_coordinate_spaces` and
`first_geometry_duplicate_named_coordinate_space`.

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

- ``View/anchorPreference(key:value:transform:)``
- ``View/transformAnchorPreference(_:value:transform:)``

### Geometry Resolution

- ``GeometryReader``
- ``GeometryProxy``
- ``GeometryProxy/frame(in:)``
- ``CoordinateSpace``
- ``View/coordinateSpace(name:)``
