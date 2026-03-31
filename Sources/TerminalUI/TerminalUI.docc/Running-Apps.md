# Running Apps

## Overview

`TerminalUI` supports both low-level and high-level runtime entry points.

Choose the level that matches your app:

- use ``DefaultRenderer`` when you need frame artifacts or textual previews
- use ``RunLoop`` when you want full control over state, focus, input handling, and terminal hosting
- use scene declarations plus `TerminalUIScenes.MultiSceneLauncher` when you want the higher-level app story that also scales to multiple windows

`App`, `Scene`, and `DefaultRenderer` are `@MainActor` authoring APIs. Construct app values and evaluate fresh `View` trees on the main actor, then hand the resulting runtime or pipeline artifacts to whichever layer you need next.

## `DefaultRenderer`

`DefaultRenderer` is the simplest way to turn a `View` into inspectable output from the main actor.

It gives you:

- resolved, measured, placed, semantic, draw, and raster products
- a `CommitPlan`
- diagnostics about computed versus reused work

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

## Scene-Based Apps

The public scene declarations live in `TerminalUI`, but the default `@main`
launch path currently comes from `TerminalUIScenes`.

Import `TerminalUIScenes` and mark your app type with `@main` to use the
default `App.main()` that forwards to `MultiSceneLauncher`. When you need an
explicit launcher instead, call:

```swift
try await MultiSceneLauncher.run(MyApp.self)
```

That launcher also supports the single-window case today, so scene-based apps
can start on that path without committing to a multi-window design.
