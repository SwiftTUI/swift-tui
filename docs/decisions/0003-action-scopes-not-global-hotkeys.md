---
adr: "0003"
title: "ActionScope-based commands, not global hotkeys"
status: accepted
date: 2026-04-29
sources:
  - docs/proposals/ACTION_SCOPES_AND_COMMANDS.md
  - docs/proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md
  - docs/STATUS.md
---

# ADR-0003: ActionScope-based commands, not global hotkeys

## Context

After an earlier toolbar/command-palette/help-sheet system was reverted
(it crashed the demo on trivial interactions), the framework was left
with two thin keybinding surfaces that didn't compose:

- `.onKeyPress(_:)` — a public view modifier that wrote into a global
  `HotkeyRegistry`. It fired only while the authoring view was resolved,
  which made the modifier's *syntax* imply locality while the
  *semantics* required tree-stable placement. Consumers who co-located
  handlers with the view they "logically belonged to" wrote fragile
  bindings.
- `LocalKeyHandlerRegistry` — package-internal, focus-identity-keyed,
  used by built-in controls (List, Picker, TabView, Stepper, TextField)
  for single-key widget behavior.

Neither matched how users think about command availability. Users
think about **what they can do right now**, which is determined by
where they are in the app, what's focused, and what's selected — not
by "which view is currently rendering."

## Decision

Introduce a single primitive — `ActionScope` — that captures all of
these. A scope is a tree-authored focus region with stable identity. A
scope is **active iff its anchor is on the current focus chain**. Tree
presence is a prerequisite; focus-chain membership is the activation
condition.

Three concrete kinds: `Scene`, presentation modifiers (`.sheet`,
`.alert`, `.confirmationDialog`), and the consumer-facing `Panel`
view. Selection is expressed as an `isEnabled` predicate on commands,
not as a fourth scope kind — keeping the kind-set small and preserving
the "every scope is a focus region" invariant.

Commands attach to scope roots via `.keyCommand(...)` and
`.paletteCommand(...)`. Toolbar items hoist *up* via
`.toolbarItem(...)` and land in the nearest enclosing scope that
declared a `.toolbar(style:)` surface — commands are top-down, items
are bottom-up.

**Key dispatch is shallowest-wins.** The runtime walks the current
focus chain root-to-leaf; the first scope with a matching binding
takes the event. A disabled match still consumes the event and blocks
deeper scopes (presence is an authoritative claim).

**Single-key dispatch stays framework-owned.** Typing, arrow keys,
Tab, Enter, and Escape are routed internally to focused widgets and
focus-traversal policy. Consumer API accepts only `modifier + key`
bindings; modifier-less registrations are silently dropped. This
eliminates typing/shortcut ambiguity entirely.

**Discoverability is consumer-wrapped.** The framework provides
annotations (`.paletteCommand`, `.toolbarItem`) and an
`EnvironmentValues.activePaletteCommands` query surface, but ships no
default palette view or help overlay. Declarations always succeed;
consumption is optional; absent-consumer = inert-declaration.

## Status

Accepted. The full rollout has landed, including `Panel`,
`FocusContainment`, the four command/toolbar modifiers, the
shallowest-wins dispatcher, and the palette query environment. The
deleted public surface (`.onKeyPress`, `HotkeyRegistry`,
`HotkeyBinding`) ships no migration shim — consumers rewrite to
`keyCommand` attached to a scope root.

## Consequences

**Enabled:**

- Command authority lives at authorial scopes. A deep dependency
  cannot silently override a shortcut claimed by a shell-level scope.
- Presentation overlays (`.alert`, `.sheet`, `.confirmationDialog`)
  inherit ActionScope conformance for free, so commands declared on
  them attach naturally to the modal.
- `NavigationStack` destinations, when that surface lands, get
  ActionScope conformance automatically; nothing in this design blocks
  the eventual addition.
- `Panel` gives consumers a pure focus/scope primitive with no
  built-in chrome, so visual treatment is composable via standard
  modifiers.

**Foreclosed:**

- No global keybinding registration. Authoring a key shortcut requires
  attaching it to a scope.
- No multi-key chords (e.g., `Ctrl+K, Ctrl+S`) in v1. Can be added
  later without breaking the surface.
- No framework-shipped palette or help UI. Consumers wrap.

**Open questions retained:**

- Cross-scope-kind precedence on collisions beyond chain depth.
- Whether state-predicate scopes should become a first-class DSL
  surface rather than living implicitly through their anchor node.

This is the foundational decision for command and keybinding
authority across the framework. Subsequent surfaces (drop
destinations, focus containment, future navigation) are positioned to
slot into the same ActionScope chain.
