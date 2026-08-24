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
compared with its previous value using `==`, and when it is equal, its whole
rendered subtree is kept as-is instead of being rebuilt.

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

The direct form is also safer: if the view's `body` reads `@State` or
`@Observable` values, or focus or press state, SwiftTUI notices and simply
does not reuse it. The `.equatable()` wrapper instead trusts your `==`
completely — if `==` ignores a value the subtree's rendering depends on (a
captured closure is the classic case), the reused subtree will be stale.
Treat `==` as a correctness contract, not a hint.

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

`LazyVStack` and `LazyHStack` realize only the visible band when their shape
lets the framework see what "visible" means. The eligible shape is:

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
- Feed it one direct `ForEach` over your data.
- Produce one row view per element. If a single element expands into several
  sibling rows, the container builds everything.
- Pass an explicit `spacing:` value. Leaving it unspecified makes spacing
  depend on neighboring content, which also disables windowing.

A shape that misses these rules still renders correctly — it just builds every
row up front, like a plain `VStack`.

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

## What not to do

- Do not hand-roll draw caching — pre-rendering rows to strings, caching your
  own rendered output, or throttling your own updates. The framework already
  reuses unchanged output and redraws only changed cells; a hand-rolled cache
  adds staleness bugs without adding speed.
- Do not reach for `AnyView` to "help" the engine. Type erasure hides exactly
  the structure SwiftTUI uses to recognize and reuse views. Keep subtrees
  typed and use `AnyView` only as a deliberate escape hatch — see the
  [AnyView guide](https://swifttui.sh/docs/documentation/swifttuiviews/anyview).
