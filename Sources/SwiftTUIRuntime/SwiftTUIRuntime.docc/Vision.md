# About SwiftTUI

SwiftTUI is SwiftUI for the terminal. An iOS or macOS engineer can pick it up
without relearning UI: you write `View` values with a declarative, body-only,
state-driven API, and SwiftTUI renders them as terminal text, a browser
canvas, or a raster surface inside a host application.

## SwiftUI Faithfulness

SwiftTUI mirrors SwiftUI's *shape*, not just its names. Knowledge transfers:
layout negotiation, modifier ordering, state identity, focus, and animation
behave the way a SwiftUI developer expects.

- **Recursive layout negotiation.** A parent proposes a size, a child reports
  what it wants, the parent places it. Modifier order changes the result.
- **Graph-scoped state.** `@State`, `@Binding`, `@Environment`, `@FocusState`,
  and the repo-owned `@Bindable` keep their SwiftUI semantics. Unkeyed state
  is tied to structural position in the resolved graph. Explicit `.id(...)`
  and `ForEach` data identities can preserve a runtime owner across structural
  moves.
- **A body-only `View` protocol.** Authoring views never see the rendering
  pipeline. Lowering to primitives is internal.
- **Declarative composition.** `@ViewBuilder`, `ViewModifier`, presentation
  modifiers, and scenes compose the same way they do in SwiftUI.

Faithfulness is a *constraint*, not a veneer. When a literal desktop behavior
would degrade the terminal experience, SwiftTUI uses a terminal-native default
while keeping the API shape SwiftUI-shaped.

## Deliberate Terminal-Native Deviations

- **Tree-forward collections.** `List`, `OutlineGroup`, and `Table` lean
  toward structural, keyboard-first navigation rather than touch-scrolling
  ergonomics.
- **A continuous coordinate space over a cell grid.** Geometry, gestures, and
  drawing work in continuous cell coordinates (`Point`), distinct from the
  integer cell grid (`CellPoint`) the terminal actually addresses.
- **Terminal-program embedding as authored content.** A real child terminal
  program can be embedded in the view tree through `TerminalView`.
- **Restrained chrome.** Defaults favor low-noise output appropriate to a
  terminal rather than maximal decoration.

## Principled Omissions

A few SwiftUI APIs are omitted on principle, not as gaps. If you reach for one
of these and get a compile error, this is why:

- **No `NavigationLink`, no `@Environment(\.dismiss)` — navigation and
  dismissal are strictly data-driven.** `NavigationLink` subverts data-driven
  UI: it fuses a control to a navigation side effect, so navigation state
  stops being derivable from (and mutable through) the app's data.
  `@Environment(\.dismiss)` couples reusable content to an assumed presenter —
  a view cannot know the context in which it is displayed. Instead, bindings
  to data drive navigation and presentation: a push mutates the data that
  declares a destination, and dismissal clears the binding (or item) that
  presents the surface. Presenter-side observation (for example, an
  `onDismiss:` callback) is compatible with this stance; child-side dismissal
  commands are not. See the `SwiftTUIViews` article
  [Dismissal Is Data](https://swifttui.sh/docs/documentation/swifttuiviews/dismissal-is-data).
- **No `.tabItem` — structured tab declarations.** Terminal tab chrome is
  structured value metadata, not an arbitrary label view tree. Declare tabs
  with `Tab(_:detail:badge:value:content:)`, which keeps the label, selection
  value, and content in one data-driven declaration. Plain tagged children
  remain supported: `Text` supplies its implicit label, while opaque content
  receives a stable `"Tab N"` fallback. `View.tabItem(_:)` is intentionally
  omitted.

## What SwiftTUI Is Today

SwiftTUI provides:

- SwiftUI-shaped layout, state, environment, and focus
- ``RunLoop``-driven interactive sessions with alternate-screen ownership and
  ANSI rendering
- Tree-forward collection presentation as a first-class authoring pattern
- PNG and baseline JPEG image presentation
- GIF import/export and finite animation through `SwiftTUIAnimatedImage`, which
  is included by the `SwiftTUI` convenience product
- Compact charts and metric components through the peer
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package
- Terminal-native presentation through alerts, confirmation dialogs, sheets,
  popovers, popover tips, menus, and toasts
- Typed-path and binding-driven `NavigationStack` destination presentation,
  with path mutation for deep links, pushes, pops, and pop-to-root
- Keyboard-based focus and navigation model with pointer-based augmentation
- Terminal capability detection for colors, images, pointer precision, and more
- Shared accessibility semantics for terminal, Web/WASI, and SwiftUI host
  delivery

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Runtime-Render-Pipeline>
- <doc:Host-Integration>
- <doc:Hosts-And-Platforms>
