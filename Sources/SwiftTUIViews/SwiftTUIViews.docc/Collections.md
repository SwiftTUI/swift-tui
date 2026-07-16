# Lists And Tables

Build terminal collections with authored row content, optional or multiple
selection, and viewport-backed data sources.

## Plain Collections

A plain ``List`` does not require tags or selection state. Rows remain authored
views, so controls and lifecycle modifiers inside them participate in normal
focus, input, state, and lifecycle handling.

```swift
List {
  Text("Status: healthy")
  Button("Redeploy") {
    redeploy()
  }
}
```

Use ``Table`` with ``TableColumn`` values when the same data is easier to scan
as aligned cells:

```swift
Table(columns: [TableColumn("Service"), TableColumn("Status")]) {
  TableRow {
    Text("API")
    Text("Healthy")
  }
  TableRow {
    Text("Worker")
    Text("Paused")
  }
}
```

## Optional And Multiple Selection

Optional single selection starts with no selected row and uses the value from
the row's `tag`:

```swift
@State private var selectedService: String?

List(selection: $selectedService) {
  Text("API").tag("api")
  Text("Worker").tag("worker")
}
```

Use a set-valued binding for multiple selection. Each row toggles independently:

```swift
@State private var selectedServices: Set<String> = []

List(selection: $selectedServices) {
  Text("API").tag("api")
  Text("Worker").tag("worker")
}
```

A selectable builder-authored row should have exactly one compatible `tag`.
Rows with a missing, ambiguous, or incompatible tag still render, but they are
not selectable and SwiftTUI reports a runtime issue.

## Nested Controls

Rows and cells host their authored view subtrees. An inner control receives its
own pointer and keyboard input before the collection's row-background selection
fallback, so activating the control does not also select or toggle its row.

```swift
List(selection: $selectedService) {
  HStack {
    Text("API")
    Spacer()
    Button("Restart") {
      restartAPI()
    }
  }
  .tag("api")
}
```

## Viewport-Backed Data

For a `RandomAccessCollection`, use the direct data initializers when rows have
a one-to-one relationship with elements. Selected forms use the element ID as
the row tag automatically:

```swift
struct Service: Identifiable {
  var id: String
  var status: String
}

@State private var selectedService: Service.ID?

List(services, selection: $selectedService) { service in
  HStack {
    Text(service.id)
    Spacer()
    Text(service.status)
  }
}
```

Tables expose the same data shapes. The closure declares the cells for one row:

```swift
Table(
  services,
  selection: $selectedService,
  columns: [TableColumn("Service"), TableColumn("Status")]
) { service in
  Text(service.id)
  Text(service.status)
}
```

In a finite viewport, direct data collections realize, measure, place, draw,
and publish semantics for only the visible band plus bounded overscan. Their
row identity follows the data ID through reordering. Source-backed table auto
columns retain a monotonic high-water width as wider rows enter the viewport.

Arbitrary builder composition remains fully supported and keeps every authored
node committed, but it can require eager work because SwiftTUI cannot prove a
total indexed row source for heterogeneous content. Prefer the data initializers
for large homogeneous collections.

## See Also

- ``List``
- ``Table``
- ``TableRow``
- ``TableColumn``
- ``ForEach``
- <doc:Focus>
