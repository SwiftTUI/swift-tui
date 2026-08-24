# Navigation and Tabs

Drive push and pop with data bound to a `NavigationStack`, and organize
top-level screens as a `TabView` with a terminal-native tab strip.

## Overview

Navigation in SwiftTUI is data-driven end to end. A ``NavigationStack``
renders its root until bound data activates a destination, and every pop —
Escape, a built-in control, or your own code — is a write back into that same
data. There is deliberately no `NavigationLink` and no
`@Environment(\.dismiss)`; the governing contract is <doc:Dismissal-Is-Data>.
``TabView`` declares its screens as ``Tab`` values against a selection
binding and renders a tab strip whose look is a swappable style.

## Push and pop with a typed path

Bind an array of `Hashable & Sendable` values with
``NavigationStack/init(path:root:)`` and register a view builder for the
element type with ``View/navigationDestination(for:destination:)`` inside the
stack:

```swift
enum Route: Hashable, Sendable {
  case detail(Int)
}

struct DeploymentsView: View {
  @State private var path: [Route] = []

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Deployments")
        Button("Open detail 1") { path.append(.detail(1)) }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .detail(let number):
          VStack(alignment: .leading, spacing: 0) {
            Text("Detail \(number)")
            Button("Push detail 2") { path.append(.detail(2)) }
            Button("Pop to root") { path.removeAll() }
          }
        }
      }
    }
  }
}
```

The array is the whole navigation story: append a value to push, remove the
last value to pop, and empty the array to return to the root. Escape pops
exactly one value at a time. The last path value's destination is the visible
surface, so seeding the array is a deep link:

```swift
@State private var path: [Route] = [.detail(1), .detail(2)]
```

A pushed value with no registered builder fails loud instead of rendering
nothing: SwiftTUI reports the `navigation.missingValueDestination` runtime
issue naming the value type.

## Push from a Boolean or an item

The other two ``View/navigationDestination(isPresented:destination:)`` and
``View/navigationDestination(item:destination:)`` forms work without a typed
path, on a plain ``NavigationStack/init(root:)`` stack. A Boolean pushes
fixed content:

```swift
struct SettingsView: View {
  @State private var showsAdvanced = false

  var body: some View {
    NavigationStack {
      Button("Advanced settings") { showsAdvanced = true }
        .navigationDestination(isPresented: $showsAdvanced) {
          Text("Advanced settings")
        }
    }
  }
}
```

An optional `Identifiable` item pushes the visual form of selected data; the
destination closure receives the current item:

```swift
struct Track: Identifiable, Sendable {
  var id: String
  var title: String
}

struct LibraryView: View {
  @State private var inspectedTrack: Track?

  var body: some View {
    NavigationStack {
      Button("Inspect Track 1") {
        inspectedTrack = Track(id: "track-1", title: "Track 1")
      }
      .navigationDestination(item: $inspectedTrack) { track in
        Text("Detail \(track.title)")
      }
    }
  }
}
```

Both forms follow the presentation-dismissal contract in
<doc:Dismissal-Is-Data>: the binding is the single source of truth, and a pop
is a data write. When Escape or a built-in close action pops the destination,
SwiftTUI writes `false` into the `isPresented:` binding or `nil` into the
`item:` binding — dismissal never happens beside your state, only through it.
Give an in-destination close control the same binding to clear. Destinations
can register further destinations, so these pushes nest. Keep one destination
source active at a time per view: when several activate in the same frame,
one destination is kept, the losing bindings are written back to inactive,
and the `navigation.multipleActiveDestinations` runtime issue is reported.

## Title the visible surface

``NavigationStack`` renders no chrome of its own.
``View/navigationTitle(_:)`` contributes the visible surface's title to the
stack's toolbar chrome, so declare a toolbar on the stack to show it:

```swift
NavigationStack(path: $path) {
  Text("Deployments")
    .navigationDestination(for: Route.self) { route in
      DetailView(route: route)
        .navigationTitle("Detail")
    }
}
.toolbar()
.toolbarStyle(DefaultTopToolbarStyle())
```

The title row tracks pushes and pops: whichever surface is visible supplies
the title.

## Declare tabs

``TabView`` takes a selection binding and a sequence of ``Tab`` declarations.
Each tab pairs a strip label with a `Hashable & Sendable` selection value and
its content:

```swift
enum Screen: Hashable {
  case inbox
  case archive
}

struct MailboxView: View {
  @State private var screen = Screen.inbox

  var body: some View {
    TabView(selection: $screen) {
      Tab("Inbox", badge: "7", value: Screen.inbox) {
        InboxList()
      }
      Tab("Archive", value: Screen.archive) {
        ArchiveList()
      }
    }
  }
}
```

`badge:` appends bracketed text to the strip label (`Inbox · [7]`), and
`detail:` adds a secondary text segment (`Home · 3`). Only the selected tab's
body resolves and draws.

The tab strip is a single focus stop. While it is focused, the Left and
Right arrows move the highlighted tab, Home and End jump to the first and
last tabs, and Return or Space commits the highlighted tab to the selection
binding. The binding is also yours to write — setting `screen = .archive`
from any action switches tabs programmatically.

## Switch the strip style

Set `tabViewStyle(_:)` on the ``TabView`` or any ancestor. The
built-in styles are `.automatic` (the default underline strip),
`.underline`, `.powerline` (connected single-row segments), and
`.literalTabs` (boxed, terminal-drawn tab shapes):

```swift
TabView(selection: $screen) {
  // Tab declarations…
}
.tabViewStyle(.powerline)
```

Those dot names are ``AnyTabViewStyle`` statics wrapping
``AutomaticTabViewStyle``, ``UnderlineTabViewStyle``,
``PowerlineTabViewStyle``, and ``LiteralTabsTabViewStyle``; a custom look
conforms to the public ``TabViewStyle`` protocol and passes through the same
modifier.

With `.literalTabs`, tabs that do not fit the available width collapse
behind a trailing `▾` trigger. On the focused strip, Down or Up expands the
trigger into a bordered menu of the collapsed tabs, the arrows move within
it, Return selects, and Escape closes the menu. The other built-in styles
keep every declared tab in the strip.

## Deselected tab state

Switching away tears down the deselected tab's live body, but its value-typed
`@State` — along with `FocusState`, collection scroll anchors, and navigation
activation — is archived and restored when that tag becomes active again, so
counters, drafts, and scroll positions survive round trips.
<doc:Dormant-Tab-State> documents exactly what the archive preserves and the
runtime issue reported when a state value is not archivable.

## See also

- <doc:Dismissal-Is-Data>
- <doc:Dormant-Tab-State>
- <doc:Coming-From-SwiftUI>
