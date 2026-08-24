# State, Environment, And Focus

Own values with `@State`, share observable models through the environment,
and steer focus — one invalidation path drives all of it.

## Overview

SwiftTUI keeps state, observation, environment, and focus on one runtime
invalidation path: a local `@State` write, an observable model write, and a
focus change all rerender through the same scheduler. This article shows the
wrappers working together, then routes each topic to the guide that owns it.

```swift
@MainActor @Observable
final class SearchModel {  // implicitly Sendable
  var query = ""
}

struct SearchScreen: View {
  @Environment(SearchModel.self) private var model
  @State private var showsLength = false

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      QueryField(model: model)
      Toggle("Show length", isOn: $showsLength)
      if showsLength {
        Text("Query is \(model.query.count) characters")
      }
    }
  }
}

struct QueryField: View {
  @Bindable var model: SearchModel
  @FocusState private var isEditing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("Query", text: $model.query)
        .focused($isEditing)
      Button("Edit query") { isEditing = true }
    }
  }
}
```

Inject the model once at the root —
`SearchScreen().environment(SearchModel())` — and each wrapper plays its
role. `SearchScreen` owns `showsLength` with ``State`` and passes
`$showsLength`, a ``Binding``, to the `Toggle` control. Reading
`model.query` in `body` subscribes that view to the model. ``Bindable``
projects an editable binding into the model for `TextField`. ``FocusState``
mirrors focus, so setting it in the button action moves focus to the field.

### State and identity

`@State` storage belongs to the view's runtime identity: it survives
re-evaluation but resets when that identity changes, for example under a
changed `.id(...)` value or a moved `ForEach` row. For how identity is
keyed, when state resets, and where to hoist owners that must survive lazy
tabs or presentation churn, see <doc:State-Keying>.

### Observation

Author models as `@MainActor @Observable final class` — implicitly
`Sendable`, which environment storage requires. Reads in `body` are
dependency-tracked, and a write invalidates exactly the views that read the
changed property. Observable writes are accepted from any executor and
applied on the main actor at the next frame head; `@State` and ``Binding``
writes are main-actor-only, enforced at compile time.

### Environment

``Environment`` reads inherited values by key path,
``View/environment(_:_:)`` writes one for a subtree, and
``View/environment(_:)`` injects an observable model that descendants read
back with `@Environment(Model.self)`. Runtime-injected actions expose
host-owned verbs: ``EnvironmentValues/requestTermination`` asks the active
session to end through the same ``View/onTerminationRequest(perform:)``
policy used for exit keys and signals.

```swift
struct QuitButton: View {
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Button("Quit") { _ = requestTermination() }
  }
}
```

To define your own environment keys (``EnvironmentKey``) or build custom
property wrappers that participate in evaluation like the built-ins, see
<doc:Custom-Dynamic-Properties>.

### Focus

``FocusState`` lets app state observe and control which view receives key
input, via ``View/focused(_:)`` or ``View/focused(_:equals:)``, while
``FocusedValue`` and ``FocusedBinding`` export context outward from the
focused subtree. The full model — traversal, defaults, reset, and each
intentional SwiftUI difference — is in <doc:Focus>.

## Related Symbols

- ``State``
- ``Binding``
- ``Bindable``
- ``Environment``
- ``EnvironmentValues``
- ``EnvironmentKey``
- ``FocusState``
- ``FocusedValue``
- ``FocusedBinding``
- ``RequestTerminationAction``
