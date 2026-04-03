# Running Apps

## Overview

`TerminalUI` supports both low-level and high-level runtime entry points.

Choose the level that matches your app:

- use ``DefaultRenderer`` when you need frame artifacts or textual previews
- use ``RunLoop`` when you want full control over state, focus, input handling, and terminal hosting
- use ``TerminalUISceneManifest`` and ``HostedSceneSession`` when you want wrapper-driven scene hosting on top of the shared runtime

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

The public scene declarations live in `TerminalUI`, but executable launch lives
in peer runner packages.

For terminal-native apps, import `TerminalUICLI` and mark your app type with
`@main` to use the default CLI `App.main()`. When you need an explicit
launcher, call:

```swift
try await TerminalCLIAppRunner.run(MyApp.self)
```

For WASI apps, import `TerminalUIWASI` and either rely on its default
`App.main()` or call `TerminalWASIAppRunner.run(MyApp.self)` explicitly.

`TerminalUI` itself is library-only. It owns scene declarations, manifests, and
hosted-session APIs, but it does not provide a default `App.main()` or an
executable product on its own.
