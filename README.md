# SwiftTUI

SwiftTUI is a pre-1.0, single-maintainer, AI-assisted Swift package. The
`0.x` line is usable for real terminal interfaces, but minor releases may still
make source-breaking API adjustments while the public surface is being proven.

## Install

Depend on the current alpha release instead of `main`:

```swift
// Package.swift
.package(
  url: "https://github.com/GoodHatsLLC/SwiftTUI",
  .upToNextMinor(from: "0.1.0")
)
```

For a terminal app executable target, add the convenience product:

```swift
.product(name: "SwiftTUI", package: "SwiftTUI")
```

Use `SwiftTUIRuntime` plus explicit host/runner products when embedding or
building non-terminal launch paths. See [docs/RELEASES.md](docs/RELEASES.md)
for release policy and support details.

## Support Matrix

| Surface | Status |
| --- | --- |
| macOS 26+ package development and CI | Primary supported Apple-host path; GitHub `macos-26` is the public macOS CI floor |
| Linux terminal package builds/tests | Supported through `swiftly` and `bun run test` |
| iOS 18+ package builds | Supported for host-compatible products; PTY products are excluded |
| WASI/browser deployment | Supported through `SwiftTUIWASI`, `@swifttui/web`, and `@swifttui/build` |
| `SwiftTUITerminal` / PTY embedding | macOS and Linux only |

## Overview

At the lowest public runtime level, you can resolve and render any `View` into
terminal text:

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

For full interactive terminal applications, depend on the `SwiftTUI` product
and import only `SwiftTUI`:

```swift
import SwiftTUI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`SwiftTUI` re-exports the platform-neutral runtime, standard argument parsing,
and the terminal runner. When you want an explicit launcher instead of
`@main`, call:

```swift
try await TerminalRunner.run(DemoApp.self)
```

For binaries that intentionally support `--web`, import the opt-in combined
runner product instead:

```swift
import SwiftTUIWebHostCLI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`SwiftTUIWebHostCLI` routes normal launches to the terminal runner and routes
`--web` launches through the localhost WebHost runner/browser bridge. Apps that
import only `SwiftTUI` do not compile or link the web server, FlyingFox, or
browser bundle; `--web` is rejected before terminal raw-mode setup.

### Argument parsing

Apps that want CLI flags plus the framework's standard flag surface
(`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--web`,
`--cursor-follows-focus`, `--json`, `--linear`, `-v`, `--debug`, ...) add
`SwiftTUICommand` alongside `App`. The protocol and framework options are
available from the same `SwiftTUI` import:

```swift
import SwiftTUI

@main
struct MyApp: App, SwiftTUICommand {
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
> `--cursor-follows-focus` now affect runtime behavior. `--web`, `--port`,
> `--bind`, `--open`, and `--scene` are consumed by the opt-in `SwiftTUIWebHostCLI`
> runner. `--debug` enables the existing frame diagnostics logger. `--json`
> emits machine-readable frame JSON, and standalone `--linear` selects the
> accessible linear output path. `--scene` selects which declared `WindowGroup`
> identifier the single-scene WebHost launch should run. See
> [docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md)
> for the full roadmap.

Bare-mode apps (no `SwiftTUICommand` conformance) still honor `NO_COLOR`,
`LANG=C`, and the `SWIFTTUI_*` environment variables automatically. The
full design is in
[docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md);
see [Examples/argparse](Examples/argparse) for a working consumer-flags +
framework-flags demo.

The same authored `App` and `Scene` declarations can then flow into these
root package products:

- terminal-native execution via the `SwiftTUI` convenience product, or
  explicit composition with `SwiftTUIRuntime` plus `SwiftTUICLI`
- terminal plus localhost-browser WebHost execution via the opt-in
  `SwiftTUIWebHostCLI` runner product
- WASI execution via the `SwiftTUIWASI` runner product; the shared
  `WASISurfaceBridge` transport target is package-only plumbing used by
  `SwiftTUIWASI` and `SwiftTUIWebHost`
- host-managed native embedding via the `SwiftUIHost` product on Apple
  platforms
- terminal-program embedding via `SwiftTUITerminal` and
  `SwiftTUIPTYPrimitives`
- first-class terminal workspaces via `SwiftTUITerminalWorkspace`
- deploy-to-browser hosting through `Platforms/Web` (`@swifttui/web`) and
  `Platforms/WebBuild` (`@swifttui/build`), which consume a `SwiftTUIWASI`
  build

In repo terminology, a runner owns process startup or launch routing, while a
host owns an external presentation environment or embedding lifecycle. See
[docs/TERMINOLOGY.md](docs/TERMINOLOGY.md) for the precise boundary.

`SwiftTUIRuntime` is the platform-neutral runtime product. It provides the
shared runtime, `SceneManifest`, and `HostedSceneSession`; runner and host
behavior is exposed through sibling products in the same root package.

## Examples

The maintained examples are indexed in [Examples/README.md](Examples/README.md).
That index is the fastest way to pick the right sample for a product surface,
run command, host mode, or focused test package.

| Example | What it demonstrates | Run |
| --- | --- | --- |
| [minimal](Examples/minimal) | Lowest-level snapshot rendering with `DefaultRenderer` and `TerminalSurfaceRenderer` | `swiftly run swift run --package-path Examples/minimal minimal` |
| [argparse](Examples/argparse) | `SwiftTUICommand`, consumer flags, standard framework flags, and shell completions | `swiftly run swift run --package-path Examples/argparse argparse-demo --help` |
| [gallery](Examples/gallery) | Primary component workbench for tabs, controls, input, images, charts, animation, popovers, file drop, and WebHost opt-in | `swiftly run swift run --package-path Examples/gallery gallery-demo` |
| [layouts](Examples/layouts) | SwiftTUI layout catalog with behavior tests for stacks, frames, geometry, scrolling, overlays, shapes, and custom layouts | `swiftly run swift run --package-path Examples/layouts layouts-demo` |
| [LayoutsSwiftUI](Examples/LayoutsSwiftUI) | Native SwiftUI layout catalog beside the embedded SwiftTUI catalog through `SwiftUIHost` | `swiftly run swift run --package-path Examples/LayoutsSwiftUI layouts-swiftui-demo` |
| [file-previewer](Examples/file-previewer) | Miller-column browser with embedded terminal-process previews through `SwiftTUITerminal` | `swiftly run swift run --package-path Examples/file-previewer FilePreviewerApp` |
| [terminal-workspace](Examples/terminal-workspace) | Zellij-style tabs, split panes, retained terminal sessions, command palette, and persisted layout metadata | `swiftly run swift run --package-path Examples/terminal-workspace terminal-workspace` |
| [gitviz](Examples/gitviz) | Non-interactive `SwiftTUICharts` command suite over git history | `swiftly run swift run --package-path Examples/gitviz gitviz dashboard --path .` |
| [gifcat](Examples/gifcat) | Terminal-native animated GIF playback with `SwiftTUIAnimatedImage` | `swiftly run swift run --package-path Examples/gifcat gifcat nyan.gif` |
| [gifeditor](Examples/gifeditor) | Full terminal GIF editor with canvas drawing, layers, timeline, pointer input, and GIF import/export | `swiftly run swift run --package-path Examples/gifeditor gifeditor` |
| [SwiftUIExample](Examples/SwiftUIExample) | Native Apple app embedding SwiftTUI scenes through `SwiftUIHost` | Open `Examples/SwiftUIExample/SwiftUIExample.xcodeproj` |
| [WebHostExample](Examples/WebHostExample) | Smallest app that opts into the localhost browser runner via `SwiftTUIWebHostCLI` | `swiftly run swift run --package-path Examples/WebHostExample WebHostExample --web` |
| [WebExample](Examples/WebExample) | Static browser/WASI deployment using `SwiftTUIWASI`, `@swifttui/web`, and `@swifttui/build` | `bun --cwd Examples/WebExample dev` |

## Product Tiers

| Product/package | Use when |
| --- | --- |
| `SwiftTUI` | You are building a terminal-native executable and want the default `App.main()` runner |
| `SwiftTUIRuntime` | You are composing a custom runner or host without terminal convenience behavior |
| `SwiftTUICLI` / `SwiftTUIWASI` | You need an explicit terminal or WASI runner product |
| `SwiftTUIWebHost` / `SwiftTUIWebHostCLI` | You intentionally opt into localhost browser hosting from a native process |
| `SwiftUIHost` | You embed SwiftTUI scenes in a host-managed SwiftUI surface |
| `SwiftTUITerminal` / `SwiftTUITerminalWorkspace` | You embed terminal child processes or build split-pane terminal workspaces |
| `SwiftTUIAnimatedImage` / `SwiftTUICharts` | You need the peer animated-image or charting utility surfaces |
| `@swifttui/web` / `@swifttui/build` | You are packaging browser/WASI deployments |

## Development Requirements

Currently fully supported:
- macOS 26+ for local package development on Apple platforms
- Swift 6.3.1 managed through `swiftly`

## Build And Test

```bash
swiftly run swift test
Scripts/test_gate.sh
Scripts/test_all.sh
bun run test:coverage
```

`swiftly run swift test` covers the root package, including the Swift platform
products. `Scripts/test_gate.sh` is the repo gate: it verifies the environment,
policy checks, root products, platform packages, tooling, and `Examples/gallery`.
If you're already using the repo's root Bun workspace, `bun run test` is a thin
entrypoint to that gate.

`Scripts/test_all.sh` is the exhaustive test surface. It runs the same shared
suite plus every maintained example package/app, including browser/WASI
coverage for `Examples/WebExample`. Use `bun run test:all` for the same
exhaustive runner from the root Bun workspace.

`bun run test:coverage` runs the root SwiftPM tests with SwiftPM code coverage
enabled and prints the exported coverage JSON path plus the reported line
coverage. Coverage is informational; there is no checked-in threshold gate yet.

On Linux, both runners export `DISABLE_EXPLICIT_PLATFORMS=1` and skip
Apple-only host checks.

On macOS, the public CI support floor is GitHub Actions `macos-26`. Older macOS
hosts may work when they provide compatible Swift and Xcode tooling, but failures
there are not release-gate blockers.

For development tests, use `swiftly run swift ...` explicitly. Do not use bare
`swift test` or `xcrun swift test`; they can pick up an Xcode-selected toolchain
or stale artifacts that do not match the repo's pinned Swift `6.3.1`
environment.

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
Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs
```

Every root package product intended for external users to link or import must
have a DocC catalog and be listed in
`Scripts/lib/public_docc_targets.txt`; that manifest may also include support
targets whose symbols are part of the published reference. The root `.spi.yml`
mirrors that target set for Swift Package Index-hosted documentation. Example
apps under `Examples/` are runnable samples and regression surfaces; they do
not need DocC catalogs. `bun run build:website` generates the combined DocC
archive as part of the web build and copies it into `Website/dist/docs/`.

## Documentation

Start with [docs/README.md](docs/README.md) — it is the canonical index for every
design doc, active proposal, and background note in this repository. Per-module
API reference lives in the `*.docc` catalogs under `Sources/` and `Platforms/`,
generated with the DocC command above.

For the current incomplete work queue, use [docs/TODO.md](docs/TODO.md). It is
additive to the durable docs: keep it concise, link to supporting documents,
and remove items when they are completed. [docs/STATUS.md](docs/STATUS.md)
remains the high-level overview of shipped surface, constraints, goals, and
explicit deferrals; any planned or decision-bound status gap belongs in
`docs/TODO.md`. Completed TODO entries move to
[docs/CHANGELOG.md](docs/CHANGELOG.md), where
descriptions stay self-standing and any links to repo docs are prefixed with
the short git hash that anchors the referenced material.

Common entry points:

- [docs/STATUS.md](docs/STATUS.md): shipped surface and current constraints
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): target boundaries and frame pipeline
- [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md): accessibility semantics,
  runtime policy, target bridges, and guardrails
- [docs/RUNTIME.md](docs/RUNTIME.md): lifecycle, graph-scoped state,
  terminal presentation safety, and incremental rendering behavior
- [docs/VISION.md](docs/VISION.md): philosophy, scope, and deferred work
- [docs/PERFORMANCE_EVALUATION.md](docs/PERFORMANCE_EVALUATION.md): CPU and input-latency evaluation workflow
- [Examples/README.md](Examples/README.md): maintained example apps
- [docs/CHANGELOG.md](docs/CHANGELOG.md): concise completed-work history
