# ``SwiftTUIViews``

Author terminal interfaces with a SwiftUI-shaped view system, state model, layout contract, and focus environment.

## Overview

The `SwiftTUIViews` module is the authoring surface of SwiftTUI.

It provides:

- body-only ``View/View`` definitions
- first-class public modifier algebra through ``ViewModifier``,
  ``View/modifier(_:)``, and ``ModifiedContent``
- typed builders through ``ViewBuilder``
- graph-scoped state and data flow through ``State``, ``Binding``, and ``Bindable``
- environment and focused-value access through ``Environment``, ``EnvironmentValues``, ``EnvironmentReader``, ``GeometryReader``, ``FocusedValue``, and ``FocusedBinding``
- geometry-bound preferences through `Anchor`, `AnchorSource`, and
  ``GeometryProxy``
- focus coordination through ``FocusState``
- layout composition through ``Layout``, ``AnyLayout``, the built-in stack layouts,
  and viewport-lazy containers such as ``LazyVStack`` and ``LazyHStack``, including
  the single-``ForEach`` full-lazy path
- continuous cell-space gestures and drawing through ``DragGesture``,
  ``SpatialTapGesture``, ``View/onPointerHover(_:)``, ``Canvas``, and
  ``CanvasDrawing`` / ``CanvasClosureDrawing``
- the controls, containers, metrics, and modifiers that make up most authored terminal interfaces, including single-line and multiline text entry, split navigation, tab shells, and terminal-native presentation (`alert`, `confirmationDialog`, `sheet`, `fullScreenCover`, `popover`, `popoverTip`, `toast`)
- ASCII-art banner text through ``TextFigure``, backed by embedded FIGlet fonts that participate in normal layout proposals without requiring external font files

`SwiftTUIViews` is intentionally close to SwiftUI in shape. The goal is not to expose a terminal-specific DSL. The goal is to preserve the parts of SwiftUI that make large UI codebases composable and predictable while still targeting cell-based rendering.

## Authoring Model

Views are resolved into a strict downstream pipeline, but authors do not work with render nodes directly. You declare structure and modifiers in terms of views:

```swift
struct DeployPanel: View {
  @State private var isExpanded = true

  var body: some View {
    GroupBox("Deploy") {
      DisclosureGroup("Details", isExpanded: $isExpanded) {
        Text("Healthy")
      }
    }
  }
}
```

The public surface ends at authored views, layouts, and first-class modifiers.
Lowering helpers remain package-only implementation details.

## Topics

### Essentials

- ``View/View``
- ``ViewBuilder``
- ``AnyView``
- ``Resolver``
- ``TextFigure``

### State And Data Flow

- ``State``
- ``Binding``
- ``Bindable``
- <doc:State-Environment-And-Focus>

### Layout

- ``Layout``
- ``AnyLayout``
- ``HStackLayout``
- ``VStackLayout``
- ``LazyVStack``
- ``LazyHStack``
- ``ZStackLayout``

### Input And Drawing

- ``Canvas``
- ``CanvasDrawing``
- ``CanvasClosureDrawing``
- ``CanvasContext``
- ``DragGesture``
- ``SpatialTapGesture``
- ``HoverPhase``
- <doc:Pointer-And-Canvas>

### Shapes

- ``Shape``
- ``InsettableShape``
- ``Rectangle``
- ``RoundedRectangle``
- ``Circle``
- ``Ellipse``
- ``Capsule``
- <doc:Shapes>
- <doc:AspectCorrectShapes>

### Guides

- <doc:Authoring-Views>
- <doc:AnyView>
- <doc:Geometry-And-Preferences>
- <doc:State-Environment-And-Focus>
- <doc:State-Keying>
- <doc:Focus>
- <doc:Dismissal-Is-Data>
- <doc:Shapes>
