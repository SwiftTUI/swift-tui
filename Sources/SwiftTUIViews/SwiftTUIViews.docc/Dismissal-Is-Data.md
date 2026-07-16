# Dismissal Is Data

Model presentation visibility in the presenting view. SwiftTUI reads a
Boolean binding or an optional identifiable item to create a presentation,
and dismissal clears that same source value.

## Present with a Boolean

Use a Boolean when the presented content does not need a separate model value:

```swift
struct InspectorHost: View {
  @State private var showsInspector = false

  var body: some View {
    Button("Inspect") {
      showsInspector = true
    }
    .sheet(
      isPresented: $showsInspector,
      onDismiss: {
        // The sheet has left the committed rendered tree.
      }
    ) {
      Text("Inspector")
    }
  }
}
```

Escape, a built-in close action, or an application write of `false` all clear
the binding. The optional `onDismiss` callback observes the resulting teardown;
it is not the command that performs dismissal.

## Present an identifiable item

Use an optional item when the presentation is the visual form of selected
application data:

```swift
struct Document: Identifiable, Sendable {
  var id: String
  var title: String
}

struct DocumentHost: View {
  @State private var inspectedDocument: Document?

  var body: some View {
    Button("Inspect README") {
      inspectedDocument = Document(id: "readme", title: "README")
    }
    .sheet(item: $inspectedDocument) { document in
      Text("Inspecting \(document.title)")
    }
  }
}
```

The content closure receives the current item. Replacing its value with another
value that has the same ID refreshes the mounted content without losing local
state. Replacing the ID tears down the old activation and mounts a new one.
Setting the item to `nil` dismisses it.

Item forms are available for sheets, alerts, confirmation dialogs, popovers,
and full-screen covers. A full-screen cover uses the same data contract while
occupying the complete terminal proposal without a sheet header, card inset,
border, or implicit close button.

## Observe teardown at the presenter

`onDismiss` runs once after a previously committed activation disappears. It
does not run for an initially inactive binding. The callback follows the same
contract for direct state writes, Escape, built-in actions, toast expiration,
item-ID replacement, and removal of the presenting subtree.

Presented content does not receive an ambient dismiss command. If content owns
a dismissal control, give it the binding or an application action that clears
the source data. This keeps navigation and presentation decisions visible in
the state owner and makes restoration, testing, and deep linking predictable.
