# ``AnyView``

Erase a concrete view type at a deliberate boundary.

## Overview

`AnyView` stores a view whose concrete type is not known to the surrounding
code. It is useful when a specific call site must keep heterogeneous authored
views in one value, but it should not be the default way to compose SwiftTUI
interfaces.

Prefer typed composition first:

- use `@ViewBuilder` for conditional branches
- use generic `Content: View` storage for reusable containers
- return `some View` from helpers
- use model data plus `ForEach` instead of prebuilt arrays of erased rows

Reach for `AnyView` when those shapes cannot represent the boundary without
moving type erasure somewhere else.

## Runtime Behavior

SwiftTUI lowers an `AnyView` into a stable wrapper and a type-aware payload:

```text
AnyView
+-- AnyViewPayload<ErasedStaticType>
    +-- concrete content
```

The wrapper's structural identity follows the authored `AnyView` position. The
payload identity includes the erased static payload type.

If the same static payload type is rendered again, SwiftTUI preserves payload
state, lifecycle registrations, focus registrations, action registrations, and
measurement reuse. If the static payload type changes, SwiftTUI replaces the
payload subtree and removes the old state and lifecycle registrations.

Explicit `.id(...)` values inside the payload become entity identities used for
routing a compatible runtime owner across structural moves, and they remain
available for focus, actions, and user-directed lookup. They do not override the
payload type boundary. An explicit ID inside `AnyView(Text(...))` will not keep
the old state alive after the same position changes to `AnyView(VStack { ... })`.

## Differences From SwiftUI

SwiftTUI's `AnyView` has the same broad source-level role as SwiftUI's
`AnyView`: it erases a concrete `View` type. Do not assume it has identical
runtime behavior.

The important differences are:

- SwiftTUI documents the retained-graph boundary. The wrapper and
  `AnyViewPayload<ErasedStaticType>` nodes are real implementation nodes, not an
  invisible convenience.
- SwiftTUI uses the erased static payload type as the state-preservation
  boundary. Same static payload type preserves the payload subtree; changed
  static payload type replaces it.
- SwiftTUI keeps explicit `.id(...)` values inside the payload as entity
  identities for compatible runtime-owner routing, focus, actions, and lookup,
  but those IDs do not keep state alive across a changed erased static payload
  type.
- SwiftTUI's terminal renderer depends on structural reuse for incremental
  painting, measurement reuse, lifecycle cleanup, and task cancellation. Erasure
  that may be harmless in a small SwiftUI app can be visible in SwiftTUI as
  extra repaint work or as a changed lifecycle boundary.
- SwiftTUI treats public `AnyView` APIs more strictly than many SwiftUI
  codebases. A reusable SwiftTUI API should prefer typed builders and generic
  storage even when a SwiftUI sample might use `AnyView` for convenience.

Use SwiftUI familiarity to understand the source shape, not as a promise about
state, lifecycle, or performance behavior.

## Prefer A Builder For Branches

When a property or helper returns conditional UI, prefer `@ViewBuilder` or
`some View`.

```swift
struct ConnectionBadge: View {
  let isConnected: Bool

  @ViewBuilder
  var body: some View {
    if isConnected {
      HStack {
        Text("[ok]")
        Text("Online")
      }
        .foregroundStyle(.green)
    } else {
      HStack {
        Text("[x]")
        Text("Offline")
      }
        .foregroundStyle(.red)
    }
  }
}
```

Avoid erasing just to make the branches share a spelling:

```swift
struct ConnectionBadge: View {
  let isConnected: Bool

  var body: AnyView {
    if isConnected {
      return AnyView(
        HStack {
          Text("[ok]")
          Text("Online")
        }
          .foregroundStyle(.green)
      )
    } else {
      return AnyView(
        HStack {
          Text("[x]")
          Text("Offline")
        }
          .foregroundStyle(.red)
      )
    }
  }
}
```

The second version works, but it hides structure the builder can preserve. That
can reduce reuse and makes later refactors more likely to blur identity
boundaries.

## Acceptable: Local Heterogeneous Values

`AnyView` is reasonable when an app-level registry really stores unrelated view
types chosen at runtime.

```swift
struct InspectorSection: Identifiable {
  let id: String
  let title: String
  let content: AnyView
}

let sections: [InspectorSection] = [
  InspectorSection(
    id: "summary",
    title: "Summary",
    content: AnyView(SummaryInspector())
  ),
  InspectorSection(
    id: "activity",
    title: "Activity",
    content: AnyView(ActivityInspector())
  )
]

struct InspectorList: View {
  let sections: [InspectorSection]

  var body: some View {
    List(sections) { section in
      Section(section.title) {
        section.content
      }
    }
  }
}
```

Keep this kind of erasure local. If you are designing a reusable API, prefer a
generic builder:

```swift
struct InspectorHost<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    GroupBox("Inspector") {
      content
    }
  }
}
```

## Acceptable: Availability Or Integration Seams

`AnyView` can be the least bad option when platform availability or a plugin
boundary genuinely produces unrelated concrete view types.

```swift
func terminalAccessory(for mode: AccessoryMode) -> AnyView {
  switch mode {
  case .compact:
    return AnyView(CompactAccessory())
  case .expanded:
    return AnyView(ExpandedAccessory())
  case .external(let provider):
    return provider.makeAccessory()
  }
}
```

Use this at the edge. Once the value is back in ordinary authored UI, keep
composition typed.

## Dangerous: Public APIs That Force Erasure

Avoid making reusable package APIs traffic in `AnyView`.

```swift
public struct DashboardPanel: View {
  public let header: AnyView
  public let content: AnyView

  public init(header: AnyView, content: AnyView) {
    self.header = header
    self.content = content
  }

  public var body: some View {
    VStack {
      header
      content
    }
  }
}
```

Prefer generic storage:

```swift
public struct DashboardPanel<Header: View, Content: View>: View {
  private let header: Header
  private let content: Content

  public init(
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content
  ) {
    self.header = header()
    self.content = content()
  }

  public var body: some View {
    VStack {
      header
      content
    }
  }
}
```

Generic storage keeps the caller's structure visible to SwiftTUI and avoids
making erasure contagious across downstream code.

## Dangerous: Using Type Swaps As State Preservation

State is preserved across an `AnyView` boundary only while the erased static
payload type remains the same.

```swift
struct SwitchingCell: View {
  let expanded: Bool

  var body: some View {
    if expanded {
      AnyView(ExpandedCell().id("cell"))
    } else {
      AnyView(CompactCell().id("cell"))
    }
  }
}
```

The inner `.id("cell")` remains useful for compatible routing, focus, and action
lookup, but it does not keep `ExpandedCell` state alive after the payload changes
to `CompactCell`. If state must survive the mode switch, own it above the erased
boundary and pass bindings or model references into each branch.

```swift
struct SwitchingCell: View {
  @State private var draft = ""
  let expanded: Bool

  var body: some View {
    if expanded {
      ExpandedCell(text: $draft)
    } else {
      CompactCell(text: $draft)
    }
  }
}
```

## Dangerous: Cached View Values As App State

Do not store authored view values as the source of truth for app behavior.

```swift
struct BadScreen: View {
  @State private var cachedAccessory = AnyView(Text("Idle"))

  var body: some View {
    cachedAccessory
  }
}
```

Store model state instead and derive the view from that state.

```swift
struct GoodScreen: View {
  @State private var status = Status.idle

  var body: some View {
    StatusAccessory(status: status)
  }
}
```

Views are transient descriptions. Treating erased views as durable app state can
freeze environment, focus, lifecycle, entity identity, and structural-position
assumptions at the wrong layer.

## Dangerous: Erasing Every Row

Prefer data-driven rows over arrays of prebuilt erased row views.

```swift
let rows: [AnyView] = items.map { item in
  AnyView(ItemRow(item: item))
}
```

This makes structural position and entity identity harder to audit and often
moves row ownership away from the data that should drive it. Prefer:

```swift
ForEach(items) { item in
  ItemRow(item: item)
}
```

If rows genuinely come from unrelated plugins, require stable data identity at
the registry boundary and keep the erased value as close to that boundary as
possible.

## Impact Checklist

Before introducing `AnyView`, ask:

1. Could this be a `@ViewBuilder` branch?
2. Could this be generic `Content: View` storage?
3. Could this return `some View` from a helper?
4. Is the erased value short-lived and local to the boundary that needs it?
5. Does state that must survive type changes live above the erased boundary?
6. Will future maintainers understand why erasure is necessary here?

If the answer to the first three questions is "yes", avoid `AnyView`. If the
answer to the last three questions is "no", redesign the boundary before
shipping it.
