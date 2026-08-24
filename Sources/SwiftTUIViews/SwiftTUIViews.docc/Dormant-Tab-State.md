# Dormant Tab State

What survives in a deselected tab, what restarts when the tab returns, and
how to keep reference-typed models alive across tab switches.

## Overview

`TabView` renders only the selected tab. A deselected tab is not hidden: its
view tree is torn down, and its body is not evaluated again until the tab is
reselected. Before teardown, SwiftTUI archives the tab's value-typed
persistent state and restores it when that tag becomes selected again, so
the common case just works:

```swift
struct InboxTab: View {
  @State private var selectedRow: UUID?
  @State private var draft = ""

  var body: some View {
    VStack(alignment: .leading) {
      TextField("Reply draft", text: $draft)
      InboxRows(selection: $selectedRow)
    }
  }
}

TabView(selection: $section) {
  Tab("Inbox", value: "inbox") { InboxTab() }
  Tab("Archive", value: "archive") { ArchiveTab() }
}
```

Switch to Archive and back: `selectedRow` and `draft` come back exactly as
you left them, restored before the tab's first new body evaluation.

What crosses the dormant seam:

- `@State` values that are recursively value-only, including `@State` nested
  inside a custom `DynamicProperty`. Standard-library and Foundation value
  types qualify — `UUID`, `Date`, SIMD vectors, and arrays and structs built
  from them. (`Data` is the exception: its mirror exposes a raw pointer, so
  it is rejected like any pointer.)
- `@FocusState` values.
- Collection scroll positions — the visible window of a list or table.
- Navigation activation: a destination presented inside the tab is presented
  again when the tab returns.

## Reference Types Do Not Survive

Anything with a live runtime edge is torn down, not archived: class
instances, running tasks and continuations, closures and captured bindings,
`GestureState`, pointers, and metatypes. A class-backed model owned inside a
tab is the common trap:

```swift
struct FeedTab: View {
  // Not archivable: FeedModel is a class.
  @State private var model = FeedModel()
  // ...
}
```

When this tab departs, SwiftTUI reports the
`tab.dormantStateUnsupportedValue` runtime issue naming the slot and its
stored type, and the tab returns with a fresh `FeedModel` built from the
authored initial value. The reset is never silent.

The fix is the one the diagnostic suggests: hoist ownership above the
`TabView` and pass the model down, so it never crosses the dormant seam:

```swift
@MainActor @Observable
final class FeedModel {  // implicitly Sendable
  var entries: [Entry] = []
}

struct RootView: View {
  let feed: FeedModel  // created once, above the TabView
  @State private var section = "feed"

  var body: some View {
    TabView(selection: $section) {
      Tab("Feed", value: "feed") { FeedTab(model: feed) }
      Tab("Log", value: "log") { LogTab() }
    }
  }
}
```

The hoisted model survives every switch, and the tab's remaining value-typed
`@State` still archives normally. Hoist only what must survive; tab-local
state that should reset on deselection can stay tab-local. See
<doc:State-Keying> for the general owner-placement model.

## Lifecycle Restarts on Return

Returning to a tab is a fresh activation seeded with restored values, not a
resumed frame:

- `onDisappear` runs when the tab departs, and `onAppear` runs again when it
  returns.
- A `.task` is cancelled at departure and starts again from the top on
  return. Repeated switching keeps exactly one active task per declared
  `.task`; visits do not leak or stack tasks.
- Focus candidates are re-derived from the new active tree (the restored
  `@FocusState` value still applies), and gesture state begins at its
  authored seed.

```swift
Tab("Feed", value: "feed") {
  FeedList(model: feed)
    .task { await feed.streamUpdates() }  // cancelled on departure,
}                                         // restarted on return
```

Write `.task` bodies to be restartable, and put results that must outlive
the visit in archivable `@State` or a hoisted model.

## Which Archive a Tab Gets Back

Archives are keyed by the tab's tag value, not its declared position, so
reordering tab declarations preserves each tab's state. Removing a tag
evicts its archive, and reinserting it later starts from authored values.
Replacing the `TabView` itself — changing its `.id` — starts a new lifetime
with no inherited archives. Duplicate tags get isolated per-occurrence
storage and report a `tab.duplicateTag` runtime warning, because selection
between equal tags is ambiguous. For the navigation structures that commonly
surround tabs, see <doc:Navigation-And-Tabs>.

## The Archive Contract in Detail

The rest of this article is the normative contract, for readers who need
the exact rules.

**Keying and lifetime.** An archive belongs to one live `TabView` owner and
one selection identity: the typed tag value, its optional-matching policy,
and its duplicate-tag occurrence. The registry lives on the `TabView` owner
and retains at most one value-only archive per declared inactive tab, so
repeated switching never accumulates historical view nodes. A nested
`TabView` rejoins both its active payload and its own inactive-tab archives
when its outer tab returns.

**What a record stores.** Only state-slot values whose producer declares
them persistent for dormancy and whose payload passes a recursive
value-only safety audit, plus closure-free entity-routing anchors that let
descendant state rejoin the same lifetime. No view nodes, resolved output,
registrations, handlers, observation dependencies, or evaluator closures
are retained. Framework scratch that a control re-derives after
reactivation — a `TextEditor`'s measured content width — is declared
transient and is neither archived nor warned about.

**Restoration.** Activation installs archived values before
dynamic-property update and body evaluation, so the first restored frame
already sees them. Restore seeds placeholder records only; authored
resolution adopts them, and any record the payload no longer claims is
reclaimed at the frame barrier.

**Diagnostics and atomicity.** Exclusion is never silent: rejected
persistent values report the deduplicated `tab.dormantStateUnsupportedValue`
issue with the slot and stored type, and ambiguous selection reports
`tab.duplicateTag`. The registry participates in the frame checkpoint, so an
aborted frame neither consumes nor publishes dormant state. A state write
that lands while the departing tab's asynchronous frame tail is suspended is
captured as a value-only refresh guarded by the owner lifetime and a numeric
refresh token; discarded frame candidates and stale tokens cannot mutate the
committed archive.

## See Also

- <doc:State-Keying>
- <doc:Navigation-And-Tabs>
- <doc:State-Environment-And-Focus>
