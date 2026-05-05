# State Keying: Ordinal vs Source-Location

This document compares two strategies for keying `@State` storage in a
SwiftUI-shaped view framework:

1. **Ordinal keying** — the approach SwiftUI uses.
2. **Source-location keying** — an alternative that keys state by file, line,
   and column.

Both strategies solve the same problem: when a view's body is re-evaluated,
the framework must reconnect each `@State` declaration to the correct
persisted value. The strategies differ in *how* they identify "the correct
value."

SwiftTUI's current implementation uses source-location slots under the
authored view identity, then scopes live imperative callbacks to the runtime
view graph that registered them. That means:

- a surviving owner reconnects to state by `(view identity path,
  source-location slot)`
- the same stateful view value rendered into two different live graphs gets
  separate graph-scoped storage
- button actions, key-command handlers, projected bindings, and gesture updates
  mutate the graph that registered the callback rather than whichever graph
  most recently resolved the same view value
- no-invalidator `DefaultRenderer` snapshots keep the same-instance fallback
  used by tests and previews: reusing the same view instance can carry an
  imperative write into a later snapshot of that instance

The graph scope is an implementation detail of dynamic-property storage. It is
not a new public identity namespace, and it does not change the owner-placement
rule later in this document.

---

## The problem

A view can declare multiple `@State` properties:

```swift
struct PairEditor: View {
    @State private var left = ""
    @State private var right = ""

    var body: some View {
        HStack {
            TextField("Left", text: $left)
            TextField("Right", text: $right)
        }
    }
}
```

When `body` re-evaluates, the framework sees two `@State` declarations. It
needs a key for each one so it can look up the persisted value from the
previous frame. The key must be:

- **Stable** across re-evaluations (same declaration → same key).
- **Unique** within the view (different declarations → different keys).

Both strategies satisfy these requirements. They diverge in edge cases
involving source-level refactors.

---

## Strategy 1: Ordinal keying (SwiftUI)

SwiftUI assigns each `@State` property a slot index based on its position
among the view's state properties. The first `@State` declaration is slot 0,
the second is slot 1, and so on.

The key for a state value is:

```
(view_identity_in_tree, slot_index)
```

### How it works

```swift
struct Counter: View {
    @State private var count = 0       // slot 0
    @State private var label = "Tap"   // slot 1

    var body: some View {
        Button("\(label): \(count)") { count += 1 }
    }
}
```

On every re-evaluation of `Counter.body`, SwiftUI reconnects:
- `count` to the value stored at `(Counter_identity, 0)`
- `label` to the value stored at `(Counter_identity, 1)`

The slot index is determined by declaration order in the struct — it is a
compile-time property of the type, not a runtime discovery. SwiftUI's
attribute graph maintains a fixed slot layout per view type.

### What "ordinal" means concretely

The ordinal is not literally the property's position in source text. It is the
index among state-bearing properties as the framework encounters them during
property-wrapper initialization. In practice, this matches declaration order
because Swift initializes stored properties in declaration order.

---

## Strategy 2: Source-location keying

An alternative strategy captures the declaration's file, line, and column at
compile time using Swift's `#fileID`, `#line`, and `#column` literals:

```swift
@propertyWrapper
struct State<Value> {
    private let sourceLocation: String

    init(
        wrappedValue: Value,
        fileID: StaticString = #fileID,
        line: UInt = #line,
        column: UInt = #column
    ) {
        self.sourceLocation = "\(fileID):\(line):\(column)"
        // ...
    }
}
```

The key for a state value is:

```
(view_identity_in_tree, source_location_string)
```

### How it works

```swift
struct Counter: View {
    @State private var count = 0       // key: "Counter.swift:3:5"
    @State private var label = "Tap"   // key: "Counter.swift:4:5"

    var body: some View {
        Button("\(label): \(count)") { count += 1 }
    }
}
```

On every re-evaluation, the framework reconnects:
- `count` to the value stored at `(Counter_identity, "Counter.swift:3:5")`
- `label` to the value stored at `(Counter_identity, "Counter.swift:4:5")`

The source location is captured once at property-wrapper initialization and
stored with the state box. It does not change across re-evaluations because
property wrappers are initialized once per view instance.

---

## Where they behave identically

For all normal usage — declaring state, reading it, mutating it, passing
bindings — the two strategies are indistinguishable. The key is stable and
unique in both cases.

```swift
struct Timer: View {
    @State private var elapsed = 0
    @State private var running = false

    var body: some View {
        VStack {
            Text("\(elapsed)s")
            Toggle("Running", isOn: $running)
        }
        .task(id: running) {
            while running {
                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
            }
        }
    }
}
```

Both strategies persist `elapsed` and `running` correctly across
re-evaluations. Both correctly reset state when the view's tree identity
changes (e.g., when a parent conditional switches branches). Both correctly
preserve state when the view's tree identity is stable.

---

## Where they diverge

The two strategies produce different behavior under two specific source-level
refactors. Both are uncommon. Neither is likely to cause real bugs. But they
are the honest difference between the approaches.

### Case 1: Reordering declarations

**Ordinal keying loses. Source-location keying wins.**

Before:

```swift
struct Profile: View {
    @State private var name = ""      // ordinal: slot 0, source: "Profile.swift:2:5"
    @State private var bio = ""       // ordinal: slot 1, source: "Profile.swift:3:5"

    var body: some View {
        VStack {
            TextField("Name", text: $name)
            TextField("Bio", text: $bio)
        }
    }
}
```

A developer reorders the declarations (perhaps to group related properties):

```swift
struct Profile: View {
    @State private var bio = ""       // ordinal: slot 0, source: "Profile.swift:2:5"
    @State private var name = ""      // ordinal: slot 1, source: "Profile.swift:3:5"

    var body: some View {
        VStack {
            TextField("Name", text: $name)
            TextField("Bio", text: $bio)
        }
    }
}
```

**Under ordinal keying:** Slot 0 previously held `name`'s value. After the
reorder, slot 0 is now `bio`. The values silently swap — `bio` gets `name`'s
old value and vice versa. The view renders with the wrong data in each field.

**Under source-location keying:** Both properties moved to different lines.
The old keys (`Profile.swift:2:5` and `Profile.swift:3:5`) no longer match
either property's new source location. Both values are orphaned, and both
properties reinitialize to their defaults (`""`). No silent swap occurs — the
state resets cleanly.

**Severity:** Low. Reordering `@State` declarations is a source-level change
that implies recompilation. In SwiftUI, the attribute graph is not persisted
across app launches, so the swap only affects hot-reload or preview scenarios
where state survives recompilation. In most workflows, recompilation resets
all state anyway.

### Case 2: Moving a declaration to a different line

**Source-location keying loses. Ordinal keying wins.**

Before:

```swift
struct Settings: View {
    @State private var volume = 0.5     // ordinal: slot 0, source: "Settings.swift:2:5"

    @State private var brightness = 0.8 // ordinal: slot 1, source: "Settings.swift:4:5"

    var body: some View {
        VStack {
            Slider(value: $volume)
            Slider(value: $brightness)
        }
    }
}
```

A developer removes the blank line, moving `brightness` up:

```swift
struct Settings: View {
    @State private var volume = 0.5     // ordinal: slot 0, source: "Settings.swift:2:5"
    @State private var brightness = 0.8 // ordinal: slot 1, source: "Settings.swift:3:5"

    var body: some View {
        VStack {
            Slider(value: $volume)
            Slider(value: $brightness)
        }
    }
}
```

**Under ordinal keying:** `volume` is still slot 0, `brightness` is still
slot 1. Both values are correctly reconnected. The blank-line removal has no
effect on state.

**Under source-location keying:** `brightness` moved from line 4 to line 3.
Its key changed from `"Settings.swift:4:5"` to `"Settings.swift:3:5"`. The
old value is orphaned, and `brightness` reinitializes to `0.8`. The user's
preference is lost.

**Severity:** Low. This only matters if state survives recompilation (same
scenarios as Case 1). In practice, reformatting source code resets the
affected state values to their defaults — a clean loss rather than a silent
corruption, but a loss nonetheless.

### Case 3: Adding a new declaration between existing ones

**Ordinal keying loses. Source-location keying wins.**

Before:

```swift
struct Dashboard: View {
    @State private var refresh = false  // ordinal: slot 0, source: "Dashboard.swift:2:5"
    @State private var query = ""       // ordinal: slot 1, source: "Dashboard.swift:3:5"

    var body: some View {
        VStack {
            Toggle("Auto-refresh", isOn: $refresh)
            TextField("Search", text: $query)
        }
    }
}
```

A developer adds a new property between the two existing ones:

```swift
struct Dashboard: View {
    @State private var refresh = false  // ordinal: slot 0, source: "Dashboard.swift:2:5"
    @State private var interval = 30   // ordinal: slot 1, source: "Dashboard.swift:3:5"  [NEW]
    @State private var query = ""       // ordinal: slot 2, source: "Dashboard.swift:4:5"

    var body: some View {
        VStack {
            Toggle("Auto-refresh", isOn: $refresh)
            Stepper("Interval: \(interval)s", value: $interval)
            TextField("Search", text: $query)
        }
    }
}
```

**Under ordinal keying:** `refresh` stays at slot 0 — fine. But `interval`
now occupies slot 1, which previously held `query`'s value (a `String`). If
the framework does not validate types, `interval` could receive a garbage
value. If it does validate types (SwiftUI does), the type mismatch forces a
reset of slot 1 and all subsequent slots. Either way, `query` at slot 2 loses
its previous value because it moved from slot 1 to slot 2.

**Under source-location keying:** `refresh` keeps its key — fine. `interval`
gets a new key that never existed — clean initialization. `query` moved from
line 3 to line 4, so its key changed — its old value is orphaned and it
reinitializes. This is the same "line movement" loss from Case 2.

**Net result:** Ordinal keying loses `query`'s value (slot shift). Source-
location keying also loses `query`'s value (line shift). Both lose. But
ordinal keying additionally risks type mismatches at the shifted slots, while
source-location keying fails cleanly with default reinitialization.

---

## Conditional state and dynamic property counts

Both strategies must handle views whose state declarations are *not*
conditional. In Swift, `@State` properties are stored properties on the view
struct — they always exist regardless of which branch `body` takes:

```swift
struct Onboarding: View {
    @State private var name = ""       // always exists
    @State private var agreed = false  // always exists
    @State private var step = 0        // always exists

    var body: some View {
        switch step {
        case 0:
            TextField("Name", text: $name)
            Button("Next") { step = 1 }
        case 1:
            Toggle("I agree", isOn: $agreed)
            Button("Done") { step = 2 }
        default:
            Text("Welcome, \(name)")
        }
    }
}
```

All three properties are initialized when the struct is created. The `body`
conditional controls which ones are *used in the view tree*, but all three
are keyed and persisted regardless. Both strategies handle this identically —
there is no "conditional state" problem.

The divergence would arise if a framework allowed state declarations *inside*
the body closure (SwiftUI does not). Source-location keying could handle this
naturally (each call site has a unique location). Ordinal keying would need
additional bookkeeping to handle conditional slots.

---

## Interaction with the attribute graph

SwiftUI's ordinal keying is not just a keying choice — it is a consequence of
the attribute graph architecture. The graph maintains a fixed slot layout per
view type. Slots are allocated once and reused across re-evaluations. This
design requires ordinal stability: the slot layout must not change between
evaluations of the same view type.

Source-location keying is compatible with both graph-based and tree-based
architectures. It does not require a fixed slot layout because the key is
self-describing — the framework can look up state by key in a dictionary
rather than by index in an array. This flexibility comes at a minor cost:
dictionary lookups are slower than array indexing. For UI frameworks, this
cost is negligible.

A framework using source-location keying could adopt an attribute graph
later without changing its keying strategy. The graph would store state in a
map rather than a slot array, but the dependency-tracking and invalidation
benefits of the graph are orthogonal to the keying strategy.

---

## Summary of tradeoffs

| Scenario | Ordinal | Source-location |
|---|---|---|
| Normal usage | Correct | Correct |
| Reorder declarations | Silent value swap | Clean reset to defaults |
| Move declaration to different line | No effect | Clean reset to defaults |
| Insert declaration between existing ones | Slot shift (type mismatch risk) | Clean reset for moved lines |
| State survives recompilation | More stable across formatting changes | More stable across reordering |
| Conditional state in body | N/A (Swift doesn't allow it) | Would work naturally |
| Attribute graph compatibility | Native fit (array slots) | Compatible (dictionary lookup) |
| Implementation complexity | Requires fixed slot layout | Requires only `#fileID`/`#line`/`#column` |

**Neither strategy is strictly better.** They fail in different edge cases,
both of which are uncommon and occur only when state survives recompilation.
The practical difference is negligible for production applications.

The honest characterization: ordinal keying is the natural fit for a
persistent attribute graph. Source-location keying is simpler to implement,
fails more cleanly (reset vs swap), and does not constrain the framework's
internal architecture.

---

## Practical owner placement guidance

The comparison above is only about how a surviving owner reconnects to its
persisted state slot. It does **not** protect state when the owning view
identity itself is recreated.

That distinction matters in this repository because several runtime features
intentionally resolve children lazily or out of line:

- active-tab content in `TabView`
- deferred view payloads captured for later evaluation
- root-hoisted presentation overlays
- wrapper-hosted and scene-hosted compositions that can re-resolve only part
  of the tree on a given frame

If a piece of state must survive churn across one of those seams, the durable
rule is to own it above the seam and pass bindings or model references into
the lazy child. Keying cannot recover state from an owner that disappeared and
was recreated somewhere else.

Practical consequences:

- Diagnose "tab switch" or "presentation dismiss" resets as owner-placement
  problems first, not keying problems.
- Do not over-hoist by default. Tab-local state can be allowed to reset when a
  tab is genuinely deselected if that is the intended product behavior.
- Distinguish transient visual flicker from true state loss. Flicker can come
  from composition or host-sync issues even when state ownership is correct.
- Root-hoisted presentation churn should be transparent to the currently
  selected tab. If opening or dismissing a palette resets the active tab's
  local state without the palette changing selection, that is a presentation
  bug rather than an expected lazy-tab reset.
- When a child is resolved lazily, prefer parent-owned state plus explicit
  bindings over child-local `@State` for data that must persist across
  activation changes.
