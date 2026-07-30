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
columns retain a monotonic high-water width as wider rows enter the viewport:
widths grow to fit the widest row that has been visible and do not shrink again
while the element IDs are stable, so a column does not twitch as rows scroll
through it.

Inside a `ScrollView` the enclosing scroll layout declares the viewport it will
show the collection through, and the collection windows against that. A
collection given genuinely unbounded height — under `.fixedSize()`, or an
ideal-height probe — has nothing to window against, so it realizes every row
and reports `collection.unboundedRealization` once. That is deliberate: those
callers asked for the true ideal size, and estimating it from a probe would
quietly mis-size a collection whose rows differ in height.

Arbitrary builder composition remains fully supported and keeps every authored
node committed, but it takes the eager path: SwiftTUI cannot prove a total
indexed row source for heterogeneous content, so every row is realized and
measured every frame. Past a few hundred rows this is reported as
`collection.eagerLargeCollection`. Prefer the data initializers for large
homogeneous collections.

## Scrolling And Selection

A collection's visible window is owned separately from its selection. Scrolling
moves the window; selection moves within it.

- The **mouse wheel** scrolls the window and leaves the selection alone, so you
  can look at row 500 while row 3 stays selected.
- **PageUp**, **PageDown**, **Home**, and **End** scroll the window. A
  non-selectable data-backed collection is focusable so these reach it; a
  selectable one keeps focus at the row layer, as before.
- **Arrow keys** move the selection. The window follows only when it has to,
  and then only far enough to reveal the new row with a row of context beyond
  it — a selection step within the visible rows does not scroll at all.
- ``ScrollViewProxy/scrollTo(_:anchor:)`` reaches a row by ID whether or not it
  is currently realized.

> Note: before this contract, the wheel stepped the selection and the window
> was recomputed each frame from the selected row. Code that relied on
> wheel-as-selection should move to the arrow-key path or drive the selection
> binding directly.

## See Also

- ``List``
- ``Table``
- ``TableRow``
- ``TableColumn``
- ``ForEach``
- <doc:Focus>
