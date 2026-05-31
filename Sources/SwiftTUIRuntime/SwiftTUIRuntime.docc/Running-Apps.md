# Running Apps

## Overview

`SwiftTUIRuntime` supports both low-level and high-level runtime entry points.

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

The public scene declarations live in `SwiftTUIRuntime`, while platform
integration lives in sibling root package products. The `SwiftTUI` convenience
product re-exports this module plus the combined terminal/WebHost launch
surface and animated GIF/image support for ordinary app binaries.

The same authored `App` and `Scene` declarations can feed these execution
modes:

- terminal-native execution through the `SwiftTUI` convenience product or the
  explicit `SwiftTUICLI` runner product
- WASI execution through the `SwiftTUIWASI` runner product
- localhost-browser execution through the compound `SwiftTUIWebHost` product
- host-managed embedding through a host product

`SwiftTUIRuntime` owns scene declarations, manifests, and hosted-session APIs.
It does not pull in runner products on its own.

### Executable runners

For ordinary apps, import `SwiftTUI` and mark your app type with `@main` to use
the default launcher. It runs in the terminal by default and switches to the
localhost WebHost when `--web` is present.

`@main` is the supported launch form. Because `App` refines an
`AsyncParsableCommand`, `App.main()` is `async` and only `@main` binds it
correctly. A bare top-level `MyApp.main()` (or `await MyApp.main()`) instead
selects swift-argument-parser's synchronous `ParsableCommand.main()` overload
and never starts the runtime; SwiftTUI rejects that path with a precise
diagnostic in DEBUG and release alike rather than failing silently. Mark the
app type `@main` and do not add an explicit `main()` call.

When you need a terminal-only explicit launcher, compose `SwiftTUIRuntime` with
`SwiftTUICLI` and call:

```swift
try await TerminalRunner.run(MyApp.self)
```

For WASI apps, import `SwiftTUIWASI` and either rely on its default
`App.main()` or call `WASIRunner.run(MyApp.self)` explicitly.

### Host products

For host-managed embedding, keep the authored `App` in `SwiftTUIRuntime`, then
let a host product build `SceneManifest` values, retain one or more
`HostedSceneSession` values, and provide explicit presentation surfaces such as
`HostedRasterSurface`. Hosted raster surfaces deliver ``SemanticHostFrame``
values so host shells receive producer sequence, raster output, semantics,
focus, and raster damage as one committed frame.

`SwiftUIHost` uses that path to embed SwiftTUI scenes inside a SwiftUI
app on Apple platforms. `@swifttui/web` uses the same authored scene model for
browser hosting on top of a `SwiftTUIWASI` build.

`SwiftTUIWebHost` is deliberately compound: `SwiftTUIWebHost` provides
`WebHostRunner` for localhost-browser launch, while `SwiftTUIWebHostCLI`
provides `WebHostCLIRunner` for binaries that support both terminal-native and
`--web` launch. `SwiftTUI` includes that combined runner by default; import
`SwiftTUIWebHostCLI` directly only for a narrower graph.
