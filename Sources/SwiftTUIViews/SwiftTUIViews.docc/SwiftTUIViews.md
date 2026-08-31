# ``SwiftTUIViews``

Author terminal interfaces with a SwiftUI-shaped view system, state model,
layout contract, and focus environment.

## Overview

The `SwiftTUIViews` module is the authoring surface of SwiftTUI.

It provides:

- body-only ``View`` definitions
- first-class public modifier algebra through ``ViewModifier``,
  ``View/modifier(_:)``, and ``ModifiedContent``
- typed builders through ``ViewBuilder``
- graph-scoped state and data flow through ``State``, ``Binding``, and
  ``Bindable``
- environment and focused-value access through ``Environment``,
  ``EnvironmentValues``, ``EnvironmentReader``, ``GeometryReader``,
  ``FocusedValue``, and ``FocusedBinding``
- geometry-bound preferences through `Anchor`, `AnchorSource`, and
  ``GeometryProxy``
- focus coordination through ``FocusState``
- layout composition through ``Layout``, ``AnyLayout``, and the built-in stack
  layouts. Viewport-lazy containers such as ``LazyVStack`` and ``LazyHStack``
  support the single-``ForEach`` full-lazy path
- continuous cell-space gestures and drawing through ``DragGesture``,
  ``SpatialTapGesture``, ``View/onPointerHover(_:)``,
  ``View/onScrollWheel(perform:)``, ``Canvas``, and
  `CanvasDrawing` / ``CanvasClosureDrawing``
- controls, containers, metrics, and modifiers for most terminal interfaces.
  These include single-line and multiline text entry, split navigation, tab
  shells, and terminal-native presentations: `alert`, `confirmationDialog`,
  `sheet`, `fullScreenCover`, `popover`, `popoverTip`, and `toast`.
- ASCII-art banner text through ``TextFigure``. Embedded FIGlet fonts support
  normal layout proposals without external font files.

`SwiftTUIViews` is intentionally close to SwiftUI in shape. It does not expose
a terminal-specific DSL. It preserves the SwiftUI parts that keep large UI
codebases composable and predictable. It targets cell-based rendering.

## Authoring Model

SwiftTUI sends views through a strict downstream pipeline. Authors do not work
with render nodes directly. You declare structure and modifiers in terms of views:

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

- ``View``
- ``ViewBuilder``
- ``AnyView``
- ``TextFigure``

### State And Data Flow

- ``State``
- ``Binding``
- ``Bindable``

### Layout

- ``Layout``
- ``LayoutProperties``
- ``AnyLayout``
- ``HStackLayout``
- ``VStackLayout``
- ``LazyVStack``
- ``LazyHStack``
- ``ZStackLayout``

### Input And Drawing

- ``Canvas``
- ``CanvasClosureDrawing``
- ``DragGesture``
- ``SpatialTapGesture``
- ``ScrollWheelEvent``
- ``ScrollWheelResult``

### Shape Primitives

- ``Shape``
- ``InsettableShape``
- ``Rectangle``
- ``RoundedRectangle``
- ``Circle``
- ``Ellipse``
- ``Capsule``

### Guides

- <doc:Coming-From-SwiftUI>
- <doc:Authoring-Views>
- <doc:Forms-And-Controls>
- <doc:Commands-And-Key-Input>
- <doc:Focus>
- <doc:State-Environment-And-Focus>
- <doc:State-Keying>
- <doc:Dormant-Tab-State>
- <doc:Custom-Dynamic-Properties>
- <doc:Collections>
- <doc:Scrolling>
- <doc:Navigation-And-Tabs>
- <doc:Dismissal-Is-Data>
- <doc:Styling-And-Theming>
- <doc:Animating-Views>
- <doc:Geometry-And-Preferences>
- <doc:Shapes>
- <doc:AspectCorrectShapes>
- <doc:Pointer-And-Canvas>
- <doc:Accessibility>
- <doc:AnyView>
- <doc:Divergences-And-Gaps>
