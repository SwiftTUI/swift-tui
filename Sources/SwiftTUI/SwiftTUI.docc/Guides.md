# All Guides

Every developer guide in the published documentation, organized by task.

## Overview

The reference documentation is organized by module; the guides below are the
task-oriented spine across it. Because each guide ships in the catalog of the
module that owns its subject, the links here cross module boundaries and use
the published site URLs. The website collects the same spine, with the
site-hosted primers, at [swifttui.sh/guides](https://swifttui.sh/guides/).

### Your first hour

Read these in order the first time through:

1. <doc:Choosing-Modules-And-Platforms> — one dependency and one import for
   most apps, plus the product matrix when you need a narrower build.
2. [Authoring Views](https://swifttui.sh/docs/documentation/swifttuiviews/authoring-views)
   — containers, local state, focused controls, and modifiers around a
   body-driven tree.
3. [State, Environment, and Focus](https://swifttui.sh/docs/documentation/swifttuiviews/state-environment-and-focus)
   — state, observation, environment, and focus on one runtime invalidation
   path.
4. [Running Apps](https://swifttui.sh/docs/documentation/swifttuiruntime/running-apps)
   — runtime entry points from the `@main` convenience down to hosted scene
   sessions.
5. [Coming from SwiftUI](https://swifttui.sh/docs/documentation/swifttuiviews/coming-from-swiftui)
   — what transfers unchanged, which reflexes need retraining, and what is not
   here yet.

### Building your interface

These guides ship in the `SwiftTUIViews` catalog, the authoring surface that
every app product re-exports.

- [Understanding Focus](https://swifttui.sh/docs/documentation/swifttuiviews/focus)
  — the runtime focus model for input routing, state control, and context
  export.
- [Lists and Tables](https://swifttui.sh/docs/documentation/swifttuiviews/collections)
  — collections with authored row content, selection, and viewport-backed
  data sources.
- [Geometry and Preferences](https://swifttui.sh/docs/documentation/swifttuiviews/geometry-and-preferences)
  — anchor preferences that publish subtree geometry for post-layout
  resolution.
- [Shapes](https://swifttui.sh/docs/documentation/swifttuiviews/shapes) —
  fill, stroke, and inset built-in and custom `Path` shapes, rasterized to
  Braille subpixels.
- [Aspect-correct shapes in terminals](https://swifttui.sh/docs/documentation/swifttuiviews/aspectcorrectshapes)
  — cell pixel metrics keep circles circular across terminal fonts.
- [Pointer and Canvas Coordinates](https://swifttui.sh/docs/documentation/swifttuiviews/pointer-and-canvas)
  — one continuous cell coordinate space for gestures, hover, and drawing.
- [Accessibility](https://swifttui.sh/docs/documentation/swifttuiviews/accessibility)
  — semantic metadata for terminal screen readers, browser ARIA trees,
  VoiceOver, and TalkBack.
- [Custom Dynamic Properties](https://swifttui.sh/docs/documentation/swifttuiviews/custom-dynamic-properties)
  — property wrappers built on the `DynamicProperty` extension point.
- [State Keying](https://swifttui.sh/docs/documentation/swifttuiviews/state-keying)
  — how `@State` storage is keyed across evaluations, and where owners
  survive lazy seams.
- [Dormant Tab State](https://swifttui.sh/docs/documentation/swifttuiviews/dormant-tab-state)
  — what happens to a tab's persistent state while the tab is not selected.
- [Dismissal Is Data](https://swifttui.sh/docs/documentation/swifttuiviews/dismissal-is-data)
  — presentations driven by Boolean bindings and identifiable items.

### Charts

- [Getting Started with SwiftTUICharts](https://swifttui.sh/docs/charts/documentation/swifttuicharts/getting-started)
  — install the package, add your first chart, and migrate from the
  in-framework module.
- [Building Dashboards](https://swifttui.sh/docs/charts/documentation/swifttuicharts/building-dashboards)
  — the `SwiftTUICharts` guide, from the separate
  [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package.

### Running your app

These guides ship in the `SwiftTUIRuntime` and platform catalogs.

- [Command-Line Options and Subcommands](https://swifttui.sh/docs/documentation/swifttuiarguments)
  — the standard `SwiftTUIOptions` flag surface, custom app flags, and verb
  routing under a positional root.
- [Profiling](https://swifttui.sh/docs/documentation/swifttuiprofiling)
  — opt-in frame and present instrumentation with TSV sinks.
- [Terminal Embedding](https://swifttui.sh/docs/documentation/swifttuiruntime/terminalembedding)
  — hosting external terminal programs inside SwiftTUI layout.
- [Terminal Handoffs](https://swifttui.sh/docs/documentation/swifttuiruntime/terminal-handoffs)
  — temporarily returning the interactive terminal to the user's shell.
- [Environment Variables](https://swifttui.sh/docs/documentation/swifttuiruntime/environment-variables)
  — every `SWIFTTUI_*` variable the framework reads.

### Beyond the terminal

The same authored `App`, on other hosts.

- [Deploying to the Browser](https://swifttui.sh/docs/documentation/swifttuiwasi/deploying-to-the-browser)
  — `--web` for localhost, or a static WASI bundle packaged with
  [`@swifttui/build`](https://github.com/SwiftTUI/swift-tui-web) and mounted
  with `@swifttui/web`.
- [Hosts and Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms)
  — the host and distribution matrix: terminal, browser, Android, and native
  SwiftUI embedding.
- [Embedding in a SwiftUI App](https://github.com/SwiftTUI/swift-tui-swiftui#readme)
  — the native macOS/iOS host from the
  [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui)
  package; its DocC ships with that package.
- [Hosting on Android](https://swifttui.sh/docs/documentation/swifttuiandroidhost/hosting-on-android)
  — the Gradle plugin and Compose host, with the Kotlin-side reference in
  [`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android).
- [Runner and Host Integration](https://swifttui.sh/docs/documentation/swifttuiruntime/host-integration)
  — how apps launch through runner products or live inside host products.

### Concepts and background

- [About SwiftTUI](https://swifttui.sh/docs/documentation/swifttuiruntime/vision)
  — why the framework exists and what it optimizes for.
- [Runtime Render Pipeline](https://swifttui.sh/docs/documentation/swifttuiruntime/runtime-render-pipeline)
  — phases, frame products, commit policy, diagnostics, and host handoff.
- [Divergences and gaps](https://swifttui.sh/docs/documentation/swifttuiviews/divergences-and-gaps)
  — the public register of API departures from SwiftUI and known gaps.
