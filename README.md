# SwiftTUI

## Overview

At the lowest public runtime level, you can resolve and render any `View` into terminal text:

```swift
import SwiftTUI

struct BuildSummary: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy Queue")
        .bold()
      Divider()
      ProgressView("Release", value: 18, total: 24)
      LabeledContent("Window", value: "staging")
      LabeledContent("Owner", value: "infra")
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

let output = await MainActor.run {
  let renderer = DefaultRenderer()
  let frame = renderer.render(
    BuildSummary(),
    proposal: .init(width: 40, height: 8)
  )

  return TerminalSurfaceRenderer(
    capabilityProfile: .previewUnicode
  ).render(frame.rasterSurface)
}

print(output)
```

`DefaultRenderer` is intentionally snapshot-friendly. Reusing the same
stateful view instance in no-invalidator tests or previews can carry
imperative writes into later snapshots of that instance. Interactive
`RunLoop` sessions scope those same dynamic-property writes to the runtime
view graph that registered the callback, so reused view values do not leak
state across live sessions.

For full interactive applications, choose a platform integration package. For
terminal-native executable apps, import `SwiftTUICLI`:

```swift
import SwiftTUICLI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`SwiftTUICLI` provides the default terminal-native `App.main()`. When you
want an explicit launcher instead of `@main`, call:

```swift
try await TerminalRunner.run(DemoApp.self)
```

### Argument parsing

Apps that want CLI flags plus the framework's standard flag surface
(`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--web`,
`--cursor-follows-focus`, `-v`, `--debug`, `--start-in`, ...) import
`SwiftTUIArguments` and conform to `SwiftTUIApp`:

```swift
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
@MainActor
struct MyApp: @preconcurrency SwiftTUIApp {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Option(name: .shortAndLong, help: "How many widgets to show.")
  var widgets: Int = 5

  var body: some Scene {
    WindowGroup { ContentView(widgets: widgets) }
  }
}
```

> **Note on flag-to-behavior wiring:** `--no-color`, `--force-color`, `--ascii`,
> `--plain`, `--accessible`, `--reduce-motion`, `--no-progress`, and
> `--cursor-follows-focus` now affect runtime behavior. Flags still pending
> behavior wiring: `--json` (alternative output mode),
> `--web`/`--port`/`--bind`/`--no-open` (embedded web host), `--linear`,
> `--debug`, and `--start-in`. All flags parse cleanly today; the unwired ones
> land in follow-up plans. See
> [docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md)
> for the full roadmap.

Bare-mode apps (no `SwiftTUIArguments` import) still honor `NO_COLOR`,
`LANG=C`, and the `SWIFTTUI_*` environment variables automatically. The
full design is in
[docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md);
see [Examples/argparse](Examples/argparse) for a working consumer-flags +
framework-flags demo.

The same authored `App` and `Scene` declarations can then flow into three
execution modes:

- terminal-native execution via the executable runner package `Platforms/CLI`
- WASI execution via the executable runner package `Platforms/WASI`
- host-managed embedding via the embedded host packages `Platforms/SwiftUI`
  and `Platforms/Web`

`SwiftTUI` on its own is library-only. It provides the shared runtime,
`SceneManifest`, and `HostedSceneSession`, but it does not provide an
executable product or default `App.main()`.

## Development Requirements

Currently fully supported:
- macOS 15+ for local package development on Apple platforms
- Swift 6.3.1 managed through `swiftly`

## Build And Test

```bash
swiftly run swift test
Scripts/test_all.sh
```

`swiftly run swift test` covers the root package. `Scripts/test_all.sh` is the
single repo-level entrypoint for the full checked-in test surface across the
runner packages, GUI packages, and example projects, and it verifies the Swift
and Bun environment first. On Linux, it exports
`DISABLE_EXPLICIT_PLATFORMS=1` and skips the Apple-only
`Platforms/SwiftUI` SwiftUI host tests. If you're
already using the repo's root Bun workspace, `bun run test` is a thin
entrypoint to the same script.

## Performance Evaluation

Use the repo-local perf tool when changing async rendering, frame scheduling,
presentation, layout fallback behavior, or other runtime paths where input
latency and CPU cost need to be compared. The full operator guide is
[docs/PERFORMANCE_EVALUATION.md](docs/PERFORMANCE_EVALUATION.md).

List the checked-in scenarios:

```bash
bun run perf:list
```

Run a quick same-binary sync versus async comparison:

```bash
bun run perf:run -- --scenario gallery-animation-click --modes sync,async --iterations 3
```

The run command prints one artifact directory per mode under `.perf/runs/`.
Compare the printed sync directory with the printed async directory:

```bash
bun run perf:compare -- .perf/runs/<sync-run> .perf/runs/<async-run>
```

Each run directory contains `run.json`, `frames.tsv`, `events.tsv`, `cpu.tsv`,
and `summary.json`. Keep the full directory when citing a result; the TSV files
explain why the summary moved.

## API Documentation

Live API reference is published at:

- <https://swifttui.io/docs/documentation/swifttui/>

To build the docs locally, generate per-module DocC archives with:

```bash
swiftly run swift package generate-documentation --target SwiftTUI
```

Or build the combined archive that powers the public site:

```bash
swiftly run swift package \
  --allow-writing-to-directory .build-docs \
  generate-documentation \
  --target SwiftTUIViews --target SwiftTUI --target SwiftTUICharts \
  --enable-experimental-combined-documentation \
  --transform-for-static-hosting \
  --output-path .build-docs
```

## Documentation

Start with [docs/README.md](docs/README.md) — it is the canonical index for every
design doc, active proposal, and background note in this repository. Per-module
API reference lives in the `*.docc` catalogs under `Sources/`, generated with
the DocC command above.

Common entry points:

- [docs/STATUS.md](docs/STATUS.md): shipped surface and current constraints
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): target boundaries and frame pipeline
- [docs/RUNTIME.md](docs/RUNTIME.md): lifecycle, graph-scoped state,
  terminal presentation safety, and incremental rendering behavior
- [docs/VISION.md](docs/VISION.md): philosophy, scope, and deferred work
- [docs/PERFORMANCE_EVALUATION.md](docs/PERFORMANCE_EVALUATION.md): CPU and input-latency evaluation workflow
- [Examples/README.md](Examples/README.md): maintained example apps
