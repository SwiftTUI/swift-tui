# Running Apps

## Overview

`SwiftTUIRuntime` supports both low-level and high-level runtime entry points.

Choose the level that matches your app:

- use ``DefaultRenderer`` when you need a committed render snapshot or textual previews
- use ``RunLoop`` when you want full control over state, focus, input handling, and terminal hosting
- use ``SceneManifest`` and ``HostedSceneSession`` when you want a host product
  to retain scenes on top of the shared runtime

`App`, `Scene`, and `DefaultRenderer` are `@MainActor` authoring APIs. Construct
app values on the main actor. Evaluate fresh `View` trees there. Then give the
resulting snapshot or runtime object to the next layer.

## `DefaultRenderer`

`DefaultRenderer` turns a `View` into inspectable output from the main actor.

It gives you:

- a public `RenderSnapshot`
- a `RasterSurface` plus `SemanticSnapshot`
- diagnostics about computed versus reused work, worker timing, and main-actor
  blocked versus suspended render time

Use it for snapshot tests, previews, and debugging.

When there is no invalidating runtime graph, `DefaultRenderer` keeps snapshot
tests convenient. The same stateful view instance can carry imperative writes
into its later snapshots. In an interactive ``RunLoop`` session, the view graph
that registered the callback owns its paths. Thus, reused view values do not
leak state across live sessions.

## `RunLoop`

`RunLoop` is the interactive runtime. It coordinates:

- terminal host ownership
- input parsing
- signal handling
- state invalidation
- focus routing
- lifecycle staging
- task reconciliation

Use it when your app needs explicit control over state containers, focus
trackers, and rendered frames.

When frame diagnostics are installed, `RunLoop` writes one tab-separated row per
presented frame. The timing columns include pipeline phase timings, worker
queue/compute timings, `main_actor_blocked_ms`, `main_actor_suspended_ms`,
geometry resolution miss counters, and `input_events_during_render_suspension`.

## Scene-Based Apps

The public scene declarations live in `SwiftTUIRuntime`, while integration
lives in in-package runner/host products and externally distributed hosts. The
`SwiftTUI` convenience product re-exports this module plus the combined
terminal/WebHost launch surface and animated GIF/image support for ordinary app
binaries.

The same authored `App` and `Scene` declarations feed every integration in the
canonical [host matrix](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md).
That owner
records the execution modes, packaging boundaries, and per-host engine
profiles. This article describes the shared runtime entry points.

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
and never starts the runtime. SwiftTUI rejects that path with a precise
diagnostic in DEBUG and release builds. Mark the app type `@main`. Do not add
an explicit `main()` call.

When you need a terminal-only explicit launcher, compose `SwiftTUIRuntime` with
`SwiftTUICLI` and call:

```swift
try await TerminalRunner.run(MyApp.self)
```

For WASI apps, import `SwiftTUIWASI` and either rely on its default
`App.main()` or call `WASIRunner.run(MyApp.self)` explicitly.

### Host products

For host-managed embedding, keep the authored `App` in `SwiftTUIRuntime`. Let a
host product build `SceneManifest` values and retain one or more
`HostedSceneSession` values. Provide explicit presentation surfaces such as
`HostedRasterSurface`. Hosted raster surfaces deliver ``SemanticHostFrame``
values so host shells receive producer sequence, raster output, semantics,
focus, and raster damage as one committed frame.

The in-package `SwiftTUIAndroidHost` product uses this path for Android
embedding. The external
[`SwiftUIHost`](https://github.com/SwiftTUI/swift-tui-swiftui) product uses it
to embed SwiftTUI scenes inside a SwiftUI app. The `@swifttui/web` product
consumes the same authored scene model on top of a `SwiftTUIWASI` build.

`SwiftTUIWebHost` is deliberately compound: `SwiftTUIWebHost` provides
`WebHostRunner` for localhost-browser launch, while `SwiftTUIWebHostCLI`
provides `WebHostCLIRunner` for binaries that support both terminal-native and
`--web` launch. `SwiftTUI` includes that combined runner by default. Import
`SwiftTUIWebHostCLI` directly only for a narrower graph.

## See Also

- <doc:Runtime-Render-Pipeline>
- <doc:Runtime>
- <doc:Host-Integration>
