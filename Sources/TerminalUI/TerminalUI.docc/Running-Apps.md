# Running Apps

## Overview

`TerminalUI` supports both low-level and high-level runtime entry points.

Choose the level that matches your app:

- use ``DefaultRenderer`` when you need frame artifacts or textual previews
- use ``RunLoop`` when you want full control over state, focus, input handling, and terminal hosting
- use ``TerminalUISceneManifest`` and ``HostedSceneSession`` when you want host-managed scene hosting on top of the shared runtime

`App`, `Scene`, and `DefaultRenderer` are `@MainActor` authoring APIs. Construct app values and evaluate fresh `View` trees on the main actor, then hand the resulting runtime or pipeline artifacts to whichever layer you need next.

## `DefaultRenderer`

`DefaultRenderer` is the simplest way to turn a `View` into inspectable output from the main actor.

It gives you:

- resolved, measured, placed, semantic, draw, and raster products
- a `CommitPlan`
- diagnostics about computed versus reused work, worker timing, and main-actor
  blocked versus suspended render time

That makes it useful for snapshot tests, previews, and deep debugging.

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

The public scene declarations live in `TerminalUI`, but platform integration
lives in peer packages.

The same authored `App` and `Scene` declarations can feed three execution
modes:

- terminal-native execution through an executable runner package
- WASI execution through an executable runner package
- host-managed embedding through an embedded host package

`TerminalUI` itself is library-only. It owns scene declarations, manifests, and
hosted-session APIs, but it does not provide a default `App.main()` or an
executable product on its own.

### Executable runners

For terminal-native apps, import `TerminalUICLI` and mark your app type with
`@main` to use the default CLI `App.main()`. When you need an explicit
launcher, call:

```swift
try await TerminalCLIAppRunner.run(MyApp.self)
```

For WASI apps, import `TerminalUIWASI` and either rely on its default
`App.main()` or call `TerminalWASIAppRunner.run(MyApp.self)` explicitly.

### Embedded hosts

For host-managed embedding, keep the authored `App` in `TerminalUI`, then let a
peer host package build `TerminalUISceneManifest` values and retain one or more
`HostedSceneSession` values.

`GUI/SwiftUITUIGUI` uses that path to embed TerminalUI scenes inside a SwiftUI
app on Apple platforms. `GUI/WebTUIGUI` and `GUI/XtermWebTUIGUI` use the same
authored scene model for browser hosting on top of a `TerminalUIWASI` build.
