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

A selectable builder-authored row must have exactly one compatible `tag`.
Rows with a missing, ambiguous, or incompatible tag still render, but they are
not selectable and SwiftTUI reports a runtime issue.

## Nested Controls

Rows and cells host their authored view subtrees. An inner control receives its
own pointer and keyboard input before the collection's row-background selection
fallback. Thus, control activation does not also select or toggle its row.

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
row identity follows the data ID through reordering. Source-backed automatic
table columns retain a monotonic high-water width. The width increases when a
wider row enters the viewport. It does not decrease while the element IDs are
stable. Thus, a column does not move as rows scroll through it.

Rows can be taller than one cell in both `List` and `Table`. Collection chrome
follows the measured row. A list paints its selection marker and separators on
the row's cells. A table repeats the outer border through each cell of a tall
row. Thus, the vertical rules stay unbroken.

```swift
Table(services, columns: [TableColumn("Service")]) { service in
  VStack(alignment: .leading, spacing: 0) {
    Text(service.id)
    Text(service.status)
  }
}
```

Inside a `ScrollView`, the enclosing scroll layout declares the viewport. The
collection windows both realized rows and generated display lines against this
viewport. Thus, per-frame cost follows viewport size instead of data-set size.
A collection with unbounded height has no viewport for windowing. This condition
occurs under `.fixedSize()` or an ideal-height probe. The collection realizes
every row and reports `collection.unboundedRealization` once. These callers
request the true ideal size. An estimate can give the wrong size when row
heights differ.

Arbitrary builder composition stays supported and keeps every authored node
committed. It uses the eager path. SwiftTUI cannot prove a total indexed row
source for heterogeneous content. Thus, it realizes and measures every row in
every frame. Past a few hundred rows, the runtime reports
`collection.eagerLargeCollection`. Prefer the data initializers for large
homogeneous collections.

## Scrolling And Selection

A collection's visible window is owned separately from its selection. Scrolling
moves the window. Selection moves within it.

- The **mouse wheel** scrolls the window and leaves the selection alone, so you
  can look at row 500 while row 3 stays selected.
- **PageUp**, **PageDown**, **Home**, and **End** scroll the window. A
  non-selectable data-backed collection is focusable, so these keys reach it. A
  selectable one keeps focus at the row layer, as before.
- **Arrow keys** move the selection. The window follows only when necessary. It
  moves only far enough to reveal the new row and one context row. A selection
  step within the visible rows does not scroll.
- ``ScrollViewProxy/scrollTo(_:anchor:)`` reaches a row by ID whether or not it
  is currently realized.

> Note: before this contract, the wheel stepped the selection and the window
> was recomputed each frame from the selected row. Code that relied on
> wheel-as-selection must move to the arrow-key path or drive the selection
> binding directly.

## See Also

- ``List``
- ``Table``
- ``TableRow``
- ``TableColumn``
- ``ForEach``
- <doc:Focus>
