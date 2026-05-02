---
adr: "0009"
title: "Theme is host-owned; views write semantic tokens"
status: accepted
date: 2026-04-29
sources:
  - docs/ARCHITECTURE.md
  - docs/RUNTIME.md
  - docs/HOST_PACKAGES.md
  - docs/PUBLIC_SURFACE_POLICY.md
---

# ADR-0009: Theme is host-owned; views write semantic tokens

## Context

SwiftTUI apps render in environments with wildly different color
expectations:

- a user's terminal with a light or dark profile chosen long ago,
- a SwiftUI host with system-managed light/dark mode that switches at
  runtime,
- a browser host where the embedding page picks the theme,
- snapshot tests that need deterministic output regardless of
  environment.

The natural-but-wrong shape is to let views read the active terminal
theme directly and branch:

```swift
// WRONG
if Color.terminalBackground == .black { ... }
```

That couples authored views to host environment, breaks snapshot
determinism, and makes runtime theme-swap a recursive view-tree
invalidation problem.

The framework also went through an earlier phase that exposed
string-based style helpers (`foregroundStyle("red")`,
`backgroundStyle("subtle")`) and a public `Theme` shim on the `View`
surface. That surface let authored apps depend on host theme details
in ways that broke under host-managed theme swapping.

## Decision

Authored views write **semantic tokens**, not literal colors:

```swift
Text("Warning")
  .foregroundStyle(.warning)
  .background(.surface)
  .border(.tint)
```

Tokens like `.foreground`, `.background`, `.warning`, `.tint`,
`.surface`, etc., are mapped to concrete colors by the **active
host's theme**. The view does not branch on which theme is active.

Host responsibilities:

- The host package picks the active theme variant (light, dark, or
  custom).
- The host can swap themes at runtime through a paired control-message
  channel; the runtime delivers the change to all hosted scene
  sessions on the same invalidation path as `SIGWINCH` resize.
- The host owns the mapping from semantic tokens to concrete colors
  and ANSI / true-color encoding decisions.

Library responsibilities:

- The Core / View / SwiftTUI layers carry semantic tokens through
  the pipeline as opaque values.
- Terminal appearance can be inferred heuristically or queried
  actively from the host; the runtime synthesizes a default semantic
  theme when no explicit host theme is provided.

The `Theme` type remains in `Core` for low-level styling support
but is **not** part of the main `View` authoring surface. The earlier
public string-based style helpers were removed.

## Status

Accepted. The four shipped host packages own their own theme objects:

- terminal-native runners (`SwiftTUICLI` / `SwiftTUIWASI`) infer
  the appearance from the terminal and pair it with a default semantic
  theme,
- `GUI/SwiftUIHost` exposes explicit light / dark variants paired
  with native renderer palette state,
- `GUI/WebHost` mirrors the same shape and binds to the embedding
  page's color scheme.

Host packages own their style mapping; the root package does not
ship a cross-platform color database.

## Consequences

**Enabled:**

- The same authored app renders correctly across all four hosts
  without inspecting host environment.
- Runtime theme swap is a single control-message round-trip — no
  view-tree invalidation, no authored-state churn.
- Snapshot tests author against semantic tokens and produce the same
  output under any explicit test theme.

**Foreclosed:**

- Authored views cannot read the active host theme directly. If a
  view needs to look different in light vs dark, it expresses that
  through different semantic tokens, not a runtime branch.
- The `View` surface does not expose string-based style helpers or a
  public `Theme` shim. New control / container style families
  converge on public protocol-based style APIs instead of closed
  string surfaces.

**Discipline imposed:**

- Adding a new public color-affecting API requires a corresponding
  semantic token, not a literal-color signature.
- Host packages cannot expose package-only internals through their
  theme APIs; the supported boundary is semantic tokens plus the
  paired render-style update message.

The bet: the same authored view surface composes cleanly across
terminal, native, and browser hosts because the tree never knew
which host it was running in.
