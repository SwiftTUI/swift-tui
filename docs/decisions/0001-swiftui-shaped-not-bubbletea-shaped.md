---
adr: "0001"
title: "SwiftUI-shaped, not Bubble Tea-shaped"
status: accepted
date: 2026-04-29
sources:
  - docs/VISION.md
  - docs/TERMINAL_NATIVE_DOCTRINE.md
  - docs/PUBLIC_SURFACE_POLICY.md
---

# ADR-0001: SwiftUI-shaped, not Bubble Tea-shaped

## Context

When designing a Swift TUI framework, the obvious starting point is
[Bubble Tea](https://github.com/charmbracelet/bubbletea) and the broader
Charm/Lip Gloss ecosystem. Bubble Tea ships an Elm-style update loop, a
component catalog, and an opinionated runtime that has shaped most modern
terminal apps in Go.

The other obvious starting point is SwiftUI: body-only views, recursive
parent-child layout negotiation, identity-keyed state, focus environments,
scene declarations. Familiar to every Swift author working on Apple
platforms today.

These two starting points lead to materially different APIs.

## Decision

SwiftTUI is shaped after **SwiftUI**, not after Bubble Tea.

The framework implements a useful subset of SwiftUI sized to the terminal
domain, with terminal-native reinterpretation permitted only when:

1. The deviation is well-considered and explicitly justified.
2. It solves a real terminal problem rather than copying another TUI
   framework by habit.
3. It is documented and reflected in the public API inventory.

When SwiftUI precedent and terminal-native practice disagree, the
framework keeps the SwiftUI-shaped authoring story only if it still
produces a good terminal experience. Otherwise it reinterprets toward
the terminal-native default.

## SwiftUI API Subset Policy

SwiftTUI reimplements a subset of SwiftUI, readapted to the terminal.
When a SwiftUI API is absent from SwiftTUI, the absence should fall into
one of a few categories:

- It is on the list, or should be on the list, but is not implemented yet.
- It is hard to map to TUI capabilities and the project does not yet have a
  good terminal-native philosophy for it.
- It is a deprecated SwiftUI API.
- It is not a data-oriented SwiftUI API.

The last point is principled. SwiftUI has APIs that, in this project's
judgment, are bad fits for SwiftTUI even if they remain in SwiftUI for
backward compatibility, progressive disclosure, or UIKit-developer
expectations. Environment-based dismiss and view-based `NavigationLink`
presentations are examples: they are familiar SwiftUI entry points, but they
hide routing and presentation ownership in places that make terminal apps
harder to reason about. SwiftTUI should prefer explicit, data-oriented
presentation and navigation state when that produces a clearer terminal API.

That policy does not require renaming every terminal-native reinterpretation.
When the authored role remains recognizably SwiftUI-shaped, SwiftTUI keeps the
SwiftUI spelling and records the narrower terminal contract. `NavigationStack`
and `.navigationDestination(...)` are the canonical shipped example: the names
are intentionally retained, while the source of truth is explicit Boolean or
item bindings instead of public `NavigationLink`, public `NavigationPath`, or an
environment navigation controller.

`@Environment(\.dismiss)` is intentionally excluded by the same policy. Terminal
presentation dismissal should stay owned by explicit bindings, explicit
callbacks, and runtime dismiss-stack behavior such as Escape handling. A future
API can add a dismissal surface only if it preserves that ownership clarity; the
absence of SwiftUI's environment dismiss action is not an accidental gap.

## Consequences

**Enabled:**

- The same Swift authors who already write SwiftUI on Apple platforms can
  build TUIs without a second mental model.
- Authored apps flow into multiple execution modes (terminal-native,
  WASI, embedded SwiftUI host, browser host) because the runtime
  contract is shared.
- Lip Gloss / Bubble Tea concepts remain useful as **evidence** of what
  TUIs need, not as templates of what the API looks like
  (see [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](../LIPGLOSS_SWIFTUI_EQUIVALENTS.md)).

**Foreclosed:**

- The framework does not adopt Elm-style `Msg` / `update` / `view`
  triples even when terminal apps are commonly written that way.
- It does not adopt domain-specific authoring DSLs (e.g. dedicated
  command-table builders).
- Some SwiftUI concepts remain deferred or rejected until their
  terminal-native reinterpretation is clear. `NavigationStack` has landed under
  this rule with binding-driven destinations; `NavigationLink`, public
  `NavigationPath`, and `@Environment(\.dismiss)` remain outside the shipped
  policy surface.

**Discipline imposed:**

- Every public API addition is reviewed against
  [PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md) for SwiftUI
  faithfulness.
- The [Terminal-Native Doctrine](../TERMINAL_NATIVE_DOCTRINE.md) provides
  the override rules — what reinterpretation looks like in practice, with
  the 10 principles as the bar.

This decision is the foundation of every other design ADR in this
directory.
