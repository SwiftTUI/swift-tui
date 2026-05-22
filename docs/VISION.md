# Vision

## What SwiftTUI is

SwiftTUI is a UI framework for the terminal that an iOS or macOS engineer can
pick up without relearning UI. You write `View` values with a declarative,
body-only, state-driven API; SwiftTUI resolves them through a typed rendering
pipeline and presents the result as terminal text, a browser canvas, or a
raster surface inside a host application.

The framework is a pre-1.0, single-maintainer, AI-assisted package. The `0.x`
line is usable for real terminal interfaces, but minor releases may still make
source-breaking adjustments while the public surface is being proven.

## The guiding principle: SwiftUI faithfulness

SwiftTUI mirrors SwiftUI's *shape*, not just its names. The goal is that
knowledge transfers: layout negotiation, modifier ordering, state identity,
focus, and animation behave the way a SwiftUI developer expects.

Concretely, faithfulness means:

- **Recursive layout negotiation.** A parent proposes a size, a child reports
  what it wants, the parent places it. Modifier order changes the result.
- **Graph-scoped state.** `@State`, `@Binding`, `@Environment`, `@FocusState`,
  and the repo-owned `@Bindable` keep their SwiftUI semantics, including state
  identity tied to a view's position in the resolved graph.
- **A body-only `View` protocol.** Authoring views never see the rendering
  pipeline. Lowering to primitives is internal.
- **Declarative composition.** `@ViewBuilder`, `ViewModifier`, presentation
  modifiers, and scenes compose the same way they do in SwiftUI.

Faithfulness is a *constraint*, not a veneer. When a literal translation of a
desktop behavior would degrade the terminal experience, SwiftTUI reinterprets
it toward a terminal-native default — but the API shape stays SwiftUI-shaped so
the reinterpretation is the only thing a developer has to learn.

## Deliberate terminal-native deviations

A SwiftUI-faithful surface still has to be a *good terminal framework*. SwiftTUI
makes a small number of intentional departures:

- **Tree-forward collections.** `List`, `OutlineGroup`, and `Table` lean toward
  structural, keyboard-first navigation rather than touch-scrolling ergonomics.
- **A continuous coordinate space over a cell grid.** Geometry, gestures, and
  drawing work in continuous cell coordinates (`Point`), distinct from the
  integer cell grid (`CellPoint`) the terminal actually addresses.
- **Terminal-program embedding as authored content.** A real child terminal
  program can be embedded in the view tree through `TerminalView`.
- **Restrained chrome.** Defaults favor calm, low-noise output appropriate to a
  terminal rather than maximal decoration.

## In scope today

- The SwiftUI-shaped authoring surface: containers, controls, layout, state,
  focus, gestures, animation, navigation, and presentation surfaces.
- A typed seven-phase render pipeline with off-main execution of the heavy
  stages.
- Four execution modes: terminal-native, WASI/browser, host-managed embedding,
  and a localhost-browser WebHost.
- A semantic accessibility substrate feeding terminal, web, and SwiftUI-host
  consumers.
- Animated-image playback in the default `SwiftTUI` convenience product, with
  charts and terminal-program embedding as peer products.

## Out of scope today

- Pixel-precise, media-heavy layout. SwiftTUI targets the cell grid, with
  Braille and half-block subpixel tricks, not arbitrary pixel composition.
- Host-native input methods (IME / composition) inside SwiftTUI's own text
  inputs.
- A general retained navigation controller. Navigation is binding-driven.

## Where this leads

The near-term direction is stabilizing the public surface toward a `0.9.0`
public beta and then `1.0.0`. The project does not document speculative
roadmaps here.

The honest, current distance between this vision and the shipped code is
tracked — concretely and without aspiration creeping back into the rest of the
documentation — in [VISION-GAP.md](VISION-GAP.md).
