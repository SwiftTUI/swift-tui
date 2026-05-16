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
- Some SwiftUI concepts are deferred until their terminal-native
  reinterpretation is clear. `NavigationStack` is the canonical example —
  it will land only when the terminal-specific interaction model reads
  like the same product.

**Discipline imposed:**

- Every public API addition is reviewed against
  [PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md) for SwiftUI
  faithfulness.
- The [Terminal-Native Doctrine](../TERMINAL_NATIVE_DOCTRINE.md) provides
  the override rules — what reinterpretation looks like in practice, with
  the 10 principles as the bar.

This decision is the foundation of every other design ADR in this
directory.
