# SwiftTUI

**SwiftUI semantics, drawn in terminal cells.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20Linux%20%C2%B7%20iOS%20%C2%B7%20WASI-1E90FF)
![Status](https://img.shields.io/badge/status-0.0.27%20alpha-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

SwiftTUI is a SwiftUI-shaped UI framework for the terminal, written in Swift.
You author `View`, `Scene`, and `App` values exactly the way you would for
SwiftUI — `VStack`, `Text`, `@State`, `ProgressView`, view modifiers — and
SwiftTUI resolves, lays out, and renders them as terminal text, a browser
canvas, or a raster surface embedded in a host app.

There is no `curses`, no virtual DOM, and no global constraint solver. Every
view is lowered through a strict, inspectable pipeline — resolve → measure →
place → semantics → draw → raster → commit — so layout is deterministic and
every frame is snapshot-testable.

**One `App` declaration, four execution modes.** The same authored scene runs
as a terminal executable, as a browser deployment compiled to WASI, through a
native localhost WebHost launch, or embedded inside a host-managed SwiftUI
surface — without rewriting view code.

## Why SwiftTUI

- **You already know the API.** Stacks, frames, `@State`, `@Environment`,
  `ProgressView`, `LabeledContent`, custom `Layout` types, and view modifiers
  behave the way SwiftUI taught you to expect.
- **Deterministic, testable frames.** Rendering is a pure function of the view
  tree and a size proposal. The same input always produces the same cells,
  which makes snapshot tests trivial and regressions cheap to catch.
- **Accessible by construction.** A semantic substrate sits under every frame,
  driving a linear accessible output path, `--no-color` / `--ascii` fallbacks,
  and reduce-motion behavior — see [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).
- **Portable.** Terminal, browser, and embedded hosts are sibling products of
  one package; use the default `SwiftTUI` import for terminal plus local
  WebHost launch, or compose narrower products directly.
- **Batteries included.** The default `SwiftTUI` import includes argument
  parsing, terminal launch, localhost WebHost launch, and animated GIF/image
  playback. Charts and terminal embedding remain opt-in peer products.

## Requirements

| | |
| --- | --- |
| Swift toolchain | Swift 6.3 (`swift-tools-version: 6.3`) |
| Apple package platforms | macOS 15+, iOS 18+ |
| Terminal / WASI builds | Linux and WASI supported via the Swift open-source toolchain |
| Local development | macOS 26+ with Swift 6.3.1, managed through `swiftly` |

`SwiftTUITerminal` / PTY embedding is macOS and Linux only. See
[docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md) for the full
platform-by-product matrix.

## Installation

Add SwiftTUI to your `Package.swift`. While the package is pre-1.0, pin to the
current alpha with `.upToNextMinor` so a minor release cannot break your build:

```swift
.package(
  url: "https://github.com/SwiftTUI/swift-tui",
  .upToNextMinor(from: "0.0.27")
)
```

For a batteries-included executable, depend on the `SwiftTUI` convenience
product:

```swift
.product(name: "SwiftTUI", package: "swift-tui")
```

That single import re-exports the platform-neutral runtime, the standard
argument-parsing surface, the combined terminal/WebHost runner, and animated
GIF/image support. Charts are still explicit: add `SwiftTUICharts` only when
your app uses chart views.

A complete minimal `Package.swift` for a terminal app:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DeployDashboard",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(
      url: "https://github.com/SwiftTUI/swift-tui",
      .upToNextMinor(from: "0.0.27")
    )
  ],
  targets: [
    .executableTarget(
      name: "DeployDashboard",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ]
    )
  ]
)
```

## Building a terminal app

Author a view, then an `@main` `App` — the same shapes you would write for
SwiftUI:

```swift
import SwiftTUI

struct BuildSummary: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Deploy Queue").bold()
      Divider()
      ProgressView("Release", value: 18, total: 24)
      LabeledContent("Window", value: "staging")
      LabeledContent("Owner", value: "infra")
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`swift run` builds and launches it; the app takes the alternate screen until
you exit, then restores your shell. Passing `--web` launches the same app
through the localhost WebHost bridge. When you want an explicit launcher
instead of `@main`, call the combined runner directly:

```swift
try await WebHostCLIRunner.run(DemoApp.self)
```

### Standard CLI flags

Conform your `App` to `SwiftTUICommand` to get the framework's standard flag
surface (`--accessible`, `--no-color`, `--ascii`, `--reduce-motion`, `--json`,
`--linear`, `--debug`, …) alongside your own options. Both the protocol and the
options come from the same `SwiftTUI` import:

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

Apps without `SwiftTUICommand` still honor `NO_COLOR`, `LANG=C`, and the
`SWIFTTUI_*` environment variables automatically. See
[`swift-tui-examples/argparse`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/argparse)
for a working demo.

### Lower-level rendering

If you need a single deterministic frame rather than an interactive session —
for snapshots, previews, or non-interactive command output — resolve a `View`
directly with `DefaultRenderer` and `TerminalSurfaceRenderer`. See
[`swift-tui-examples/minimal`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/minimal)
for the pattern and
[SwiftTUIRuntime DocC](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md)
for the runtime callpath, frame model, diagnostics, and host handoff.

## Using SwiftTUI from the web

The same `App` and `Scene` declarations deploy to the browser — no terminal
emulator, no rewrite. SwiftTUI compiles your app to WASI and streams a
structured raster surface that a small browser host draws into a `<canvas>`.

Two npm packages make this a first-class web-consumer story:

| Package | Role |
| --- | --- |
| [`@swifttui/web`](https://www.npmjs.com/package/@swifttui/web) | Browser runtime — manifest loading, canvas rendering, ARIA mounting, WASI/WebSocket scene bridges |
| [`@swifttui/build`](https://www.npmjs.com/package/@swifttui/build) | Build tooling — the `swifttui-web` CLI that compiles a SwiftTUI app into a WASI `app.wasm` and `scene-manifest.json` |

Both packages are published to the public npm registry:

```bash
npm install @swifttui/web @swifttui/build
```

They are also attached to each
[`swift-tui-web` GitHub release](https://github.com/SwiftTUI/swift-tui-web/releases/tag/0.0.27)
as npm-compatible tarballs, if you prefer to pin a specific release asset:

```bash
npm install \
  https://github.com/SwiftTUI/swift-tui-web/releases/download/0.0.27/swifttui-web-0.0.27.tgz \
  https://github.com/SwiftTUI/swift-tui-web/releases/download/0.0.27/swifttui-build-0.0.27.tgz
```

Compile your SwiftTUI `App` to WASI with the `swifttui-web` CLI — it drives the
Swift toolchain and emits `app.wasm` plus a `scene-manifest.json` into your
output directory:

```bash
npx swifttui-web build
```

Then mount the built app onto a DOM element:

```ts
import { createWebHostApp } from "@swifttui/web";
import { createWasmSceneRuntimeFactory } from "@swifttui/web/wasi";

const controller = await createWebHostApp({
  mount: document.querySelector(".terminal-shell")!,
  manifestUrl: new URL("./scene-manifest.json", import.meta.url),
  sceneRuntimeFactory: createWasmSceneRuntimeFactory(
    new URL("./assets/app.wasm", import.meta.url),
  ),
});
```

The host page only needs to serve `Cross-Origin-Opener-Policy: same-origin`
and `Cross-Origin-Embedder-Policy: require-corp` so the `SharedArrayBuffer`-backed
stdin works; everything around the mount element is your own page chrome.

[`swift-tui-examples/WebExample`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebExample)
is the reference template — a complete Bun-served browser app whose
load-bearing embedding code is roughly 60 lines. Copy that pattern to adopt
SwiftTUI in a web project.

If you only want a native process that can open a browser window on `--web`,
use the normal `SwiftTUI` dependency. For a narrower custom launcher, compose
`SwiftTUIRuntime` with `SwiftTUICLI`, `SwiftTUIWebHost`, or
`SwiftTUIWebHostCLI` directly.

## Execution modes & products

Author once; pick the product that matches how you ship.

| Product | Use when |
| --- | --- |
| `SwiftTUI` | Building a batteries-included executable with terminal launch, `--web` local hosting, and animated GIF/image support |
| `SwiftTUIRuntime` | Composing a custom runner or host on the platform-neutral runtime |
| `SwiftTUICLI` / `SwiftTUIWASI` | You need an explicit terminal or WASI runner product |
| `SwiftTUIWebHost` / `SwiftTUIWebHostCLI` | Composing localhost browser hosting without the full `SwiftTUI` convenience product |
| `SwiftTUITerminal` / `SwiftTUITerminalWorkspace` | Embedding terminal child processes or building split-pane workspaces |
| `SwiftTUIAnimatedImage` | Composing animated-image support without the full `SwiftTUI` convenience product |
| `SwiftTUICharts` | You need charting/graph views |
| `SwiftTUIProfiling` | Opt-in profiling: add `.profiling()` and set `SWIFTTUI_PROFILE` for frame, memory-occupancy, and CPU/RSS signals (debug or release) |
| `@swifttui/web` / `@swifttui/build` | Packaging a browser/WASI deployment |

A *runner* owns process startup or launch routing; a *host* owns an external
presentation environment. [docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md)
covers that boundary and the platform support matrix.

## Examples

The maintained examples live in the sibling
[`SwiftTUI/swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples)
repository — the fastest way to find a sample for a given product surface or
run mode.

| Example | Demonstrates | Run |
| --- | --- | --- |
| [minimal](https://github.com/SwiftTUI/swift-tui-examples/tree/main/minimal) | Lowest-level snapshot rendering | `swiftly run swift run --package-path ../swift-tui-examples/minimal minimal` |
| [argparse](https://github.com/SwiftTUI/swift-tui-examples/tree/main/argparse) | `SwiftTUICommand`, consumer + framework flags, completions | `swiftly run swift run --package-path ../swift-tui-examples/argparse argparse-demo --help` |
| [gallery](https://github.com/SwiftTUI/swift-tui-examples/tree/main/gallery) | Component workbench: tabs, controls, input, images, charts, animation | `swiftly run swift run --package-path ../swift-tui-examples/gallery gallery-demo` |
| [layouts](https://github.com/SwiftTUI/swift-tui-examples/tree/main/layouts) | Layout catalog: stacks, frames, geometry, scrolling, overlays, shapes | `swiftly run swift run --package-path ../swift-tui-examples/layouts layouts-demo` |
| [LayoutsSwiftUI](https://github.com/SwiftTUI/swift-tui-examples/tree/main/LayoutsSwiftUI) | Native SwiftUI layout catalog beside the embedded SwiftTUI one | `swiftly run swift run --package-path ../swift-tui-examples/LayoutsSwiftUI layouts-swiftui-demo` |
| [file-previewer](https://github.com/SwiftTUI/swift-tui-examples/tree/main/file-previewer) | Miller-column browser with embedded terminal previews | `swiftly run swift run --package-path ../swift-tui-examples/file-previewer FilePreviewerApp` |
| [terminal-workspace](https://github.com/SwiftTUI/swift-tui-examples/tree/main/terminal-workspace) | Zellij-style tabs, split panes, command palette, persisted layout | `swiftly run swift run --package-path ../swift-tui-examples/terminal-workspace terminal-workspace` |
| [gitviz](https://github.com/SwiftTUI/swift-tui-examples/tree/main/gitviz) | Non-interactive `SwiftTUICharts` command suite over git history | `swiftly run swift run --package-path ../swift-tui-examples/gitviz gitviz dashboard --path .` |
| [gifcat](https://github.com/SwiftTUI/swift-tui-examples/tree/main/gifcat) | Terminal-native animated GIF playback | `swiftly run swift run --package-path ../swift-tui-examples/gifcat gifcat nyan.gif` |
| [gifeditor](https://github.com/SwiftTUI/swift-tui-examples/tree/main/gifeditor) | Full terminal GIF editor: canvas, layers, timeline, import/export | `swiftly run swift run --package-path ../swift-tui-examples/gifeditor gifeditor` |
| [SwiftUIExample](https://github.com/SwiftTUI/swift-tui-examples/tree/main/SwiftUIExample) | Native Apple app embedding SwiftTUI scenes via the [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) host package | Open `../swift-tui-examples/SwiftUIExample/SwiftUIExample.xcodeproj` |
| [WebHostExample](https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebHostExample) | Smallest `SwiftTUI` convenience app with terminal and `--web` launch | `swiftly run swift run --package-path ../swift-tui-examples/WebHostExample WebHostExample --web` |
| [WebExample](https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebExample) | Static browser/WASI deployment with `@swifttui/web` + `@swifttui/build` | `bun --cwd ../swift-tui-examples/WebExample dev` |

## Documentation

Live API reference: <https://swifttui.sh/docs/documentation/>

[docs/README.md](docs/README.md) indexes internal architecture and project
documentation. Developer-facing guides live in DocC. Common entry points:

- [docs/VISION.md](docs/VISION.md) — what SwiftTUI is for.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules, products, layout model.
- [SwiftTUIRuntime DocC render pipeline](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md) — the runtime callpath, frame pipeline, diagnostics, and host handoff.
- [docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md) — execution modes and platform support.
- [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) — the semantic substrate.
- [docs/PUBLIC-API.md](docs/PUBLIC-API.md) — the public surface policy.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — toolchains, the test gate, the release process.

Build the combined DocC archive locally with:

```bash
Scripts/build_docc_archive.sh
```

## Project status

SwiftTUI is pre-1.0. The `0.x` line is usable for real terminal interfaces, but
minor releases may still make source-breaking API adjustments while the public
surface is being proven — keep your dependency pinned with `.upToNextMinor`. It
is currently an alpha, single-maintainer, AI-assisted project. See
[docs/VISION-GAP.md](docs/VISION-GAP.md) for where the code differs from intent
and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the release policy.

**Known issues.** A non-deterministic memory-corruption crash (`SIGSEGV` /
`SIGBUS` on the main thread) has been observed in the async-render path under
heavy concurrent test-suite load, tracked as
[`#12`](https://github.com/SwiftTUI/swift-tui/issues/12) and documented in
[docs/KNOWN-TEST-FLAKES.md](docs/KNOWN-TEST-FLAKES.md). It is load- and
timing-sensitive, not reproducible on demand, and clean under both
AddressSanitizer and ThreadSanitizer; the mechanism is not yet identified. It
has not been observed in normal single-app use, but is disclosed here for
transparency — if you hit it, a reproduction on the issue would help.

The sibling `swift-tui-web`, `swift-tui-examples`, and `swift-tui-site` repos
are public pre-release repositories as well. Each has its own `0.0.27` tag, and
cross-repo defaults use public release tags or release artifacts rather than
requiring sibling source checkouts.

## Contributing

Small, well-scoped issues and pull requests are easiest to review. The repo
uses the pinned Swift 6.3.1 toolchain through `swiftly`; build and test with:

```bash
swiftly run swift test
bun run test
```

`bun run test` is the repo gate. Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md) for the full build, test, style, and pull-request rules,
and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the exhaustive test surface
and the performance-evaluation harness.

## License

SwiftTUI first-party code is licensed under the MIT License (`MIT`).
Vendored third-party code under `Vendor/` keeps its own license and
provenance notices. See [LICENSE](LICENSE).
