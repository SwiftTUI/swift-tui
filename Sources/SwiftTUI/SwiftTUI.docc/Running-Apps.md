# Running Apps

## Overview

`SwiftTUI` supports both low-level and high-level runtime entry points.

Choose the level that matches your app:

- use ``DefaultRenderer`` when you need frame artifacts or textual previews
- use ``RunLoop`` when you want full control over state, focus, input handling, and terminal hosting
- use ``SceneManifest`` and ``HostedSceneSession`` when you want a host product
  to retain scenes on top of the shared runtime

`App`, `Scene`, and `DefaultRenderer` are `@MainActor` authoring APIs. Construct app values and evaluate fresh `View` trees on the main actor, then hand the resulting runtime or pipeline artifacts to whichever layer you need next.

## `DefaultRenderer`

`DefaultRenderer` is the simplest way to turn a `View` into inspectable output from the main actor.

It gives you:

- resolved, measured, placed, semantic, draw, and raster products
- a `CommitPlan`
- diagnostics about computed versus reused work, worker timing, and main-actor
  blocked versus suspended render time

That makes it useful for snapshot tests, previews, and deep debugging.

When there is no invalidating runtime graph, `DefaultRenderer` keeps snapshot
tests ergonomic: reusing the same stateful view instance can carry imperative
writes into later snapshots of that instance. In an interactive ``RunLoop``
session, the same callback paths are scoped to the view graph that registered
them so reused view values do not leak state across live sessions.

## `RunLoop`

`RunLoop` is the interactive runtime. It coordinates:

- terminal host ownership
- input parsing
- signal handling
- state invalidation
- focus routing
- lifecycle staging
- task reconciliation

Use it when your app wants explicit control over state containers, focus trackers, and rendered frames.

When a ``FrameDiagnosticsLogger`` is installed, `RunLoop` writes one
tab-separated row per presented frame. The timing columns include pipeline
phase timings, worker queue/compute timings, `main_actor_blocked_ms`,
`main_actor_suspended_ms`, geometry resolution miss counters, and
`input_events_during_render_suspension`.

## Scene-Based Apps

The public scene declarations live in `SwiftTUI`, while platform integration
lives in sibling root package products.

The same authored `App` and `Scene` declarations can feed three execution
modes:

- terminal-native execution through the `SwiftTUICLI` runner product
- WASI execution through the `SwiftTUIWASI` runner product
- localhost-browser execution through the compound `SwiftTUIWebHost` product
- host-managed embedding through a host product

`SwiftTUI` itself is library-only. It owns scene declarations, manifests, and
hosted-session APIs, but it does not provide a default `App.main()` or an
executable product on its own.

### Executable runners

For terminal-native apps, import `SwiftTUICLI` and mark your app type with
`@main` to use the default CLI `App.main()`. When you need an explicit
launcher, call:

```swift
try await TerminalRunner.run(MyApp.self)
```

For WASI apps, import `SwiftTUIWASI` and either rely on its default
`App.main()` or call `WASIRunner.run(MyApp.self)` explicitly.

### Host products

For host-managed embedding, keep the authored `App` in `SwiftTUI`, then let an
host product build `SceneManifest` values and retain one or more
`HostedSceneSession` values.

`SwiftUIHost` uses that path to embed SwiftTUI scenes inside a SwiftUI
app on Apple platforms. `Platforms/Web` uses the same authored scene model for
browser hosting on top of a `SwiftTUIWASI` build.

`SwiftTUIWebHost` is deliberately compound: `SwiftTUIWebHost` provides
`WebHostRunner` for localhost-browser launch, while `SwiftTUIWebHostCLI`
provides `WebHostCLIRunner` for binaries that intentionally support both
terminal-native and `--web` launch.
