# State Keying

Where `@State` storage lives, why it resets, and how to place or key owners so
the state you care about survives.

## Overview

Your view struct is a value: SwiftTUI rebuilds it on every evaluation, so the
struct cannot hold state itself. Each `@State` declaration is stored by the
framework and keyed to two things:

- the view's **position** in the view structure — which container it sits in,
  which slot among its siblings, and which `if`/`else` branch produced it, and
- an optional **explicit identity** — an `.id(_:)` value, or the data key of
  the `ForEach` element that produced it.

While a view keeps the same position, or keeps the same explicit identity,
every evaluation reconnects to the same storage. When neither matches, the old
storage is torn down and `@State` starts over from its authored initial value.
The classic "why did my state reset?" cases below are all instances of this
one rule.

## An if/else swap is a move

The two branches of a conditional are different positions, even when both
contain the same view type:

```swift
struct Panel: View {
  @State private var isCompact = false

  var body: some View {
    if isCompact {
      Score()            // one position
    } else {
      Score().padding()  // a different position
    }
  }
}
```

Each toggle of `isCompact` removes the view at one position and creates a
fresh one at the other, so any `@State` inside `Score` restarts. Plain
removal behaves the same way: when `if isVisible { Score() }` turns false,
the storage is discarded, and reinserting the view later starts from the
initial value again — state is never resurrected.

## `.id(_:)` names the identity

An explicit `.id(_:)` replaces position with a name. Changing the id is a
deliberate reset switch — the old identity's storage is discarded and a fresh
one begins:

```swift
struct Editor: View {
  @State private var generation = 0

  var body: some View {
    VStack {
      Button("Discard draft") { generation += 1 }
      DraftField().id("draft-\(generation)")  // new id: fresh @State inside
    }
  }
}
```

The other direction is just as useful: a *stable* id keeps state attached
while positions shift around it. Without the id below, showing the banner
shifts every following sibling to a new position and resets it; with the id,
the field's state survives the shift:

```swift
VStack {
  if showBanner {
    Text("Saved")        // inserting this shifts the siblings below
  }
  DraftField().id("draft")  // stable id: state survives the shift
}
```

## ForEach rows follow their data identity

`ForEach` keys each row by its element's identity — `Identifiable`
conformance, or the `id:` key path you pass. With stable ids, row-local state
follows the item through insertion, removal, and reordering, including rows of
a nested `ForEach` whose outer row moves:

```swift
// Stable identity: each row's state follows its item.
ForEach(items) { item in
  TodoRow(item: item)
}

// Index keying: state belongs to the position, not the item.
ForEach(items.indices, id: \.self) { index in
  TodoRow(item: items[index])
}
```

In the index-keyed version, inserting or reordering items leaves each row's
state at its old position, now paired with whichever item moved there. Key
rows by a value that identifies the item itself, not where it currently sits.

## Put the owner where it lives long enough

Keying only controls how a *surviving* owner reconnects to its storage. It
cannot recover state whose owner was genuinely torn down, and some features
tear down or lazily resolve children by design:

- windowed collections — `List` and `Table` realize only the rows near the
  viewport, so a row scrolled far away may not stay resident
- root-hoisted presentation overlays
- scoped content payloads captured for later evaluation

If per-item state must outlive that churn, own it above the seam and hand the
rows bindings:

```swift
struct Inbox: View {
  let messages: [Message]
  @State private var drafts: [Message.ID: String] = [:]  // outlives rows

  var body: some View {
    List(messages) { message in
      ReplyField(text: binding(for: message.id))
    }
  }

  private func binding(for id: Message.ID) -> Binding<String> {
    Binding(
      get: { drafts[id, default: ""] },
      set: { drafts[id] = $0 }
    )
  }
}
```

Do not hoist by reflex, though. State that *should* reset with its content —
a highlight, a transient expansion — is best left local. And diagnose before
moving anything: a "reset" during a presentation dismiss is usually an
owner-placement problem, and transient flicker can be a rendering issue even
when state ownership is correct.

## Tab switches archive value state

Switching tabs is not on the loses-state list. `TabView` resolves only the
selected tab body, but when a tab is deselected its value-typed `@State` (and
`@FocusState`) is archived and restored the next time that tag becomes
active. State containing class instances, tasks, or closures does not survive
dormancy; SwiftTUI reports a `tab.dormantStateUnsupportedValue` runtime issue
and asks you to use value-only state or hoist that ownership above the
`TabView`. Lifecycle is not archived: `onAppear` runs again and tasks restart
on reactivation. The full contract is in <doc:Dormant-Tab-State>.

## Live runtimes versus snapshots

Button actions, bindings, and gesture updates write to the storage of the
live runtime that registered them. Two runtimes can evaluate the same view
value, and each still gets its own independent storage — writes never leak
between them through the view value. Only in a snapshot context with no
running app (a plain renderer pass in a test or preview) can reusing one view
instance carry imperative writes into a later snapshot of that same instance.

## See Also

- <doc:Dormant-Tab-State>
- <doc:State-Environment-And-Focus>
- <doc:Focus>
- <doc:Authoring-Views>
