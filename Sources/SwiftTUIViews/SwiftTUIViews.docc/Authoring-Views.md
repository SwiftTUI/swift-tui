# Authoring Views

Build a terminal screen from small views: compose containers, style them with
modifiers, and drive them from state.

## Overview

`SwiftTUIViews` works like a compact SwiftUI. A view is a value with a `body`,
and your `body` describes the whole screen for the current state. When state
changes, SwiftTUI re-evaluates the affected bodies and updates only the
terminal cells that changed. The difference from SwiftUI is the canvas: you
lay out whole terminal cells, not points. Padding, spacing, and frame values
are integers, text wraps by column width, and input is keyboard-first.

Views are cheap values that SwiftTUI rebuilds on every update. Never store a
view instance and mutate it to change the screen; change the state the view
reads instead.

This article grows one small status panel, introducing containers, modifiers,
state, conditional content, collections, and images along the way. Start with
a view:

```swift
import SwiftTUIViews

struct StatusPanel: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("swifttui.sh").bold()
      Text("All systems normal")
        .foregroundStyle(.success)
    }
  }
}
```

If your app depends on the batteries-included `SwiftTUI` product,
`import SwiftTUI` provides the same authoring surface plus the runners.

## Compose With Containers

``VStack``, ``HStack``, and ``ZStack`` are the workhorses. `spacing` is a
cell count, and the alignment names match SwiftUI. A row for one service:

```swift
struct ServiceRow: View {
  let name: String
  let healthy: Bool

  var body: some View {
    HStack(spacing: 1) {
      Text(healthy ? "●" : "○")
        .foregroundStyle(healthy ? .success : .danger)
      Text(name)
      Spacer()
      Text(healthy ? "up" : "down")
        .foregroundStyle(.secondary)
    }
  }
}
```

``Spacer`` pushes the trailing status text to the right edge of whatever
width the row is given. `ZStack` overlays its children back to front, which
suits badges and watermarks:

```swift
ZStack(alignment: .topTrailing) {
  StatusPanel()
  Text("beta").foregroundStyle(.warning)
}
```

Prefer the built-in containers. Lists, tables, outline groups, and lazy
stacks are covered in <doc:Collections>, scrolling containers in
<doc:Scrolling>, and split views and tab shells in <doc:Navigation-And-Tabs>.
Reach for a custom ``Layout`` only for a reusable layout rule that stacks and
frames cannot express clearly. A custom layout takes part in its parent's
layout through three defaulted members: ``Layout/layoutProperties`` declares
the axis its `Spacer` and `Divider` children follow,
``Layout/spacing(subviews:cache:)`` states the spacing the parent stack keeps
around the container, and the two `explicitAlignment(of:in:proposal:subviews:cache:)`
overloads answer a horizontal or vertical alignment guide for the container as
a whole.

## Style With Modifiers

Modifiers wrap the view they are called on, so order matters. `padding(_:)`
takes a cell count and defaults to one cell. The default `border(...)` draws
into the outermost cells of the view's frame without growing it, so pad first
and the border lands in the padding ring instead of on your content:

```swift
StatusPanel()
  .padding()
  .border(.separator)
  .frame(width: 40, alignment: .topLeading)
```

Swap the first two modifiers and the border draws over the panel's outermost
cells, with blank padding around it. To reserve extra cells outside the frame
instead, pass `placement: .outset` to `border`. For flexible sizing, the
`frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`
overload accepts `.infinity` to expand into available space.

`foregroundStyle(_:)` accepts
concrete colors such as `.cyan` alongside semantic roles such as `.primary`,
`.secondary`, `.success`, `.warning`, and `.danger` that resolve through the
active theme. Theming, tinting, and the full style catalog are in
<doc:Styling-And-Theming>; motion is in <doc:Animating-Views>.

## Drive It From State

Store view-local values in ``State`` and pass writable references as
``Binding`` values, exactly as in SwiftUI. The `$` prefix projects a
`Binding`, a writable reference that lets a control mutate state it does not
own. Mutating a `@State` value invalidates the views that read it. You never
update the screen imperatively:

```swift
struct StatusPanel: View {
  @State private var showDetails = false
  @State private var refreshCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("swifttui.sh").bold()
      Toggle("Show details", isOn: $showDetails)
      Button("Refresh") {
        refreshCount += 1
      }
      Text("Refreshed \(refreshCount) times")
        .foregroundStyle(.secondary)
    }
  }
}
```

View bodies, button actions, and lifecycle closures such as `.onAppear`,
`.onChange(of:initial:_:)`, and `.task(...)` run on the main actor, and
`Binding.init(get:set:)` requires `@MainActor` get and set closures. Ordinary
authored code never notices. It matters only when you bring your own
concurrency: return to the main actor before touching state.

Built-in controls join keyboard focus traversal automatically. The full
control catalog (text fields, sliders, steppers, pickers) is in
<doc:Forms-And-Controls>, key bindings and commands are in
<doc:Commands-And-Key-Input>, focus movement is in <doc:Focus>, and how state
survives identity changes is in <doc:State-Keying>.

## Conditional Content And Collections

An `if` inside a body includes or removes a subtree, and ``ForEach`` renders
one view per element:

```swift
struct Service: Identifiable {
  let id: String
  let name: String
  let healthy: Bool
}

struct ServiceList: View {
  let services: [Service]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(services) { service in
        ServiceRow(name: service.name, healthy: service.healthy)
      }
      if services.contains(where: { !$0.healthy }) {
        Divider()
        Text("Some services need attention")
          .foregroundStyle(.warning)
      }
    }
  }
}
```

`ForEach` also accepts a `Range<Int>` or an explicit `id:` key path for data
that is not `Identifiable`. Give elements stable identities: an element's
state follows its identity, not its position. For long feeds, the `List`,
`LazyVStack`, and `Table` containers in <doc:Collections> add selection and
viewport laziness.

## Images

``Image`` decodes PNG and JPEG sources and renders them into cells. Load from
a file path or from bytes you already have:

```swift
VStack(alignment: .leading, spacing: 1) {
  Image(path: "logo.png")
  Image(data: pngBytes)
    .resizable()
    .scaledToFit()
    .frame(width: 24, height: 8)
    .border(.separator)
}
```

An image without `resizable()` is measured at its intrinsic size in cells.
`resizable()` fills whatever frame the parent proposes, while `scaledToFit()`
and `scaledToFill()` preserve aspect ratio. `Image(fileURLString:)` accepts a
`file://` URL string. For animated GIF playback, use `AnimatedImage` from the
[SwiftTUIAnimatedImage](https://swifttui.sh/docs/documentation/swifttuianimatedimage)
module, which the batteries-included `SwiftTUI` product re-exports.

## Type Erasure

Prefer typed `@ViewBuilder` composition, `some View` helpers, and generic
`Content: View` storage. Use ``AnyView`` only at deliberate boundaries where
a call site must store or transport heterogeneous view values.

## Where To Go Next

- Run what you authored:
  [Running Apps](https://swifttui.sh/docs/documentation/swifttuiruntime/running-apps)
- Controls and forms: <doc:Forms-And-Controls>
- Keyboard commands: <doc:Commands-And-Key-Input>
- Theming and styles: <doc:Styling-And-Theming>
- Motion: <doc:Animating-Views>
- Scrolling: <doc:Scrolling>
- Navigation shells: <doc:Navigation-And-Tabs>
- State identity: <doc:State-Keying>
- Focus: <doc:Focus>
- Lists and tables: <doc:Collections>
