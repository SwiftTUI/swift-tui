# ``View``

Author terminal interfaces with a SwiftUI-shaped view system, state model, layout contract, and focus environment.

## Overview

The `View` module is the authoring surface of TerminalUI.

It provides:

- body-only ``View/View`` definitions
- typed builders through ``ViewBuilder``
- state and data flow through ``State``, ``Binding``, and ``Bindable``
- environment and focused-value access through ``EnvironmentValues``, ``EnvironmentReader``, ``GeometryReader``, ``FocusedValue``, and ``FocusedBinding``
- focus coordination through ``FocusState``
- layout composition through ``Layout``, ``AnyLayout``, the built-in stack layouts,
  and viewport-lazy containers such as ``LazyVStack`` and ``LazyHStack``, including
  the single-``ForEach`` full-lazy path
- the controls, containers, metrics, and modifiers that make up most authored terminal interfaces, including single-line and multiline text entry, split navigation, tab shells, and terminal-native alert or confirmation presentation

`View` is intentionally close to SwiftUI in shape. The goal is not to expose a terminal-specific DSL. The goal is to preserve the parts of SwiftUI that make large UI codebases composable and predictable while still targeting cell-based rendering.

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

The public surface ends at authored views, layouts, and environment-driven modifiers. Lowering helpers and wrapper types remain package-only implementation details.

## Topics

### Essentials

- ``View/View``
- ``ViewBuilder``
- ``AnyView``
- ``Resolver``

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

### Guides

- <doc:Authoring-Views>
- <doc:State-Environment-And-Focus>
