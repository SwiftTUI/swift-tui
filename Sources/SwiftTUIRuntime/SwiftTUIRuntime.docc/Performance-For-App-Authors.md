# Performance for App Authors

Keep a SwiftTUI app fast with the handful of levers the framework gives you:
memoization, stable identity, lazy containers, and measurement.

## Overview

Most SwiftTUI apps never need performance work. Two things are already fast by
default. First, when a frame changes, SwiftTUI redraws only the terminal cells
that actually changed, not the whole screen. Second, lazy containers such as
`LazyVStack` build only the rows that are visible (plus a small margin), no
matter how long the underlying list is.

When an app does slow down, the fix is almost always one of the levers below,
applied after measuring. The engine-level detail behind them lives in
<doc:Runtime-Render-Pipeline>, the deep reference; you do not need it to use
this guide.

## Memoize a stable subtree with `.equatable()`

When state changes, SwiftTUI re-evaluates the views that depend on it,
including their children. `EquatableView` — usually applied as `.equatable()`
— is the designated opt-in that stops this at a boundary: the wrapped view is
compared with its previous value using `==`. When the value is equal and the
runtime's dependency and lifetime checks pass, the resolved subtree can be
reused instead of rebuilding its body. Equality alone is not sufficient.

It helps when a large, stable subtree sits beside frequently-changing state.
Here, a 48-cell panel is skipped on every counter tick:

```swift
/// Its only stored value is `title`, so the synthesized `==` is exact,
/// and its body reads no dynamic state.
struct DashboardPanel: View, Equatable {
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).bold()
      Divider()
      ForEach(Array(0..<8), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<6), id: \.self) { column in
            Text("r\(row)c\(column)").border(.separator)
          }
        }
      }
    }
  }
}

struct DemoRoot: View {
  @State private var ticks = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("ticks: \(ticks)")
      Button("tick") { ticks += 1 }
      DashboardPanel(title: "Static Panel").equatable()
    }
  }
}
```

Prefer conforming the boundary view to `Equatable` directly — a plain
`struct DashboardPanel: View, Equatable` already participates with no wrapper:

```swift
// No `.equatable()` needed: the conformance alone is the opt-in.
DashboardPanel(title: "Static Panel")
```

Both forms validate tracked dependencies before memo reuse. State and
observation read certificates check the values read by the committed
subtree. Changed or uncertifiable reads decline reuse; unchanged certified reads
can permit it when the other gates also pass. Focus, environment, transaction,
and lifetime checks still apply.

Your `==` must nevertheless include every ordinary input that affects rendering
or behavior. The runtime cannot certify arbitrary data hidden in an untracked
reference or captured closure. Treat equality as a correctness contract, and
use tracked state or observation for mutable model data.

`.equatable()` does nothing useful when the wrapped value changes every frame
anyway, when the subtree is trivially cheap, or when the content does not
conform to `Equatable` (it will not compile). Inside a `ForEach` or a
conditional, prefer the direct conformance: the wrapper adds its own layer,
which shifts the view's identity relative to the unwrapped form.

## Keep identity stable

Reuse works only when SwiftTUI can recognize a view as "the same one as last
frame". Two habits protect that:

- Do not churn `.id(...)`. Giving a view a new id every update tells SwiftTUI
  it is a brand-new view: its `@State` resets and nothing from the previous
  frame is reused. Change an id only when you *want* that reset.
- Keep `ForEach` ids stable. Derive them from the data's own identity, not
  from array positions in a reordering list and not from values regenerated on
  every update.

```swift
// Stable: the id follows the item, so reordering or inserting
// reuses every unchanged row.
ForEach(messages, id: \.messageID) { message in
  MessageRow(message: message)
}
```

## Help lazy containers window

`LazyVStack` and `LazyHStack` realize only the visible band under a `ScrollView`.
Static fragments, `Group`, conditionals, and one or more `ForEach` sources all
compose into windowed fragments; for example:

```swift
ScrollView {
  LazyVStack(spacing: 0) {
    ForEach(entries, id: \.id) { entry in
      LogRow(entry: entry)   // one row per element
    }
  }
}
```

The author-actionable rules:

- Put the lazy stack inside a `ScrollView`. Without a scrolling viewport there
  is no visible band to window to.
- Keep direct children structural. `ForEach` sources, `Group`, `if`, and other
  declared structure compose into fragments across multiple sources; a logical
  element may contribute zero or multiple fragments. Opaque bodies or modifiers
  hiding a `ForEach` do not acquire structural transparency.
- Default (`nil`) spacing is exact between realized neighboring fragments, so
  an explicit `spacing:` is optional. Observed negative spacing uses exhaustive
  layout, and a single element whose body expands without bound must be realized
  in full.

A shape that needs exhaustive layout still renders correctly — it just builds
every row up front, like a plain `VStack`.

One visible consequence to plan for: offscreen rows do not exist yet. They
cannot receive focus until scrolled into view, though programmatic scrolling
still reaches them.

## Measure before you optimize

Judge performance only in release builds — debug builds carry checks that
distort timings:

```bash
swift run -c release my-app
```

For real numbers, link the
[SwiftTUIProfiling](https://swifttui.sh/docs/documentation/swifttuiprofiling)
product. It is opt-in, costs nothing until enabled, and is activated with one
scene modifier gated by an environment variable:

```swift
import SwiftTUIProfiling

var body: some Scene {
  WindowGroup { RootView() }
    .profiling()   // a complete no-op unless SWIFTTUI_PROFILE is set
}
```

Then run with `SWIFTTUI_PROFILE=frames` to get a per-frame record stream (a
stderr summary by default), and compare before and after a change. The
`memory` and `cpu` signals cover the other two questions you are likely to
ask.

### Inspect retained work and frame pressure

For a workload that appears to reuse content but still spends time validating
it, enable `SWIFTTUI_RETAINED_VALIDATION_COUNTERS=1`. It records comparisons,
identity checks, and metadata restamping in layout metrics, so a reuse hit is
not mistaken for zero work. This diagnostic is off by default.

`SWIFTTUI_MERGE_PRESSURE_PACING=1` enables an optional scheduler policy for
sustained invalidation pressure. It spaces invalidation-only frames according
to measured frame cost, with a gap capped at 50 milliseconds. Input, including
wheel-driven changes, signals, external wakes, and due deadlines bypass the
gap. It is off by default; compare both frame throughput and interaction
latency on your workload before enabling it. Frame traces report pacing and
presentation cost alongside wake causes and coalescing.

See <doc:Environment-Variables> and <doc:Logging-And-Diagnostics> for enabling
trace output. Keep diagnostic counters off when measuring the normal baseline.

## What not to do

- Do not hand-roll draw caching — pre-rendering rows to strings, caching your
  own rendered output, or throttling your own updates. The framework already
  reuses unchanged output and redraws only changed cells; a hand-rolled cache
  adds staleness bugs without adding speed.
- Do not reach for `AnyView` to "help" the engine. Type erasure hides exactly
  the structure SwiftTUI uses to recognize and reuse views. Keep subtrees
  typed and use `AnyView` only as a deliberate escape hatch — see the
  [AnyView guide](https://swifttui.sh/docs/documentation/swifttuiviews/anyview).
