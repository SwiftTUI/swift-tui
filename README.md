# SwiftTUI

**SwiftUI semantics, drawn in terminal cells.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20Linux%20%C2%B7%20iOS%20%C2%B7%20WASI-1E90FF)
![Status](https://img.shields.io/badge/status-0.1.0%20alpha-DAA520)
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
  one package; opting into a heavier surface (a web server, a terminal
  emulator) is explicit and never linked unless you ask for it.
- **Batteries included.** Argument parsing, charts, animated images, embedded
  terminal panes, and split-pane workspaces ship as peer products.

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
  .upToNextMinor(from: "0.1.0")
)
```

For a terminal-native executable, depend on the `SwiftTUI` convenience product:

```swift
.product(name: "SwiftTUI", package: "swift-tui")
```

That single import re-exports the platform-neutral runtime, the standard
argument-parsing surface, and the terminal runner.

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
you exit, then restores your shell. When you want an explicit launcher instead
of `@main`, call the terminal runner directly:

```swift
try await TerminalRunner.run(DemoApp.self)
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
[Examples/argparse](Examples/argparse) for a working demo.

### Lower-level rendering

If you need a single deterministic frame rather than an interactive session —
for snapshots, previews, or non-interactive command output — resolve a `View`
directly with `DefaultRenderer` and `TerminalSurfaceRenderer`. See
[Examples/minimal](Examples/minimal) for the pattern and
[docs/RENDER-PIPELINE.md](docs/RENDER-PIPELINE.md) for the frame model.

## Using SwiftTUI from the web

The same `App` and `Scene` declarations deploy to the browser — no terminal
emulator, no rewrite. SwiftTUI compiles your app to WASI and streams a
structured raster surface that a small browser host draws into a `<canvas>`.

Two npm packages make this a first-class web-consumer story:

| Package | Role |
| --- | --- |
| [`@swifttui/web`](https://www.npmjs.com/package/@swifttui/web) | Browser runtime — manifest loading, canvas rendering, ARIA mounting, WASI/WebSocket scene bridges |
| [`@swifttui/build`](https://www.npmjs.com/package/@swifttui/build) | Build tooling — the `swifttui-web` CLI that compiles a SwiftTUI app into a WASI `app.wasm` and `scene-manifest.json` |

Add both to your web project:

```bash
npm install @swifttui/web @swifttui/build
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

[Examples/WebExample](Examples/WebExample) is the reference template — a
complete Bun-served browser app whose load-bearing embedding code is roughly 60
lines. Copy that pattern to adopt SwiftTUI in a web project.

If you only want a native process that can *also* open a browser window on
`--web`, skip the build pipeline and import `SwiftTUIWebHostCLI` instead; it
routes normal launches to the terminal runner and `--web` launches through the
localhost WebHost bridge.

## Execution modes & products

Author once; pick the product that matches how you ship.

| Product | Use when |
| --- | --- |
| `SwiftTUI` | Building a terminal-native executable with the default `App.main()` runner |
| `SwiftTUIRuntime` | Composing a custom runner or host on the platform-neutral runtime |
| `SwiftTUICLI` / `SwiftTUIWASI` | You need an explicit terminal or WASI runner product |
| `SwiftTUIWebHost` / `SwiftTUIWebHostCLI` | Opting a native process into localhost browser hosting |
| `SwiftUIHost` | Embedding SwiftTUI scenes inside a host-managed SwiftUI surface (Apple platforms) |
| `SwiftTUITerminal` / `SwiftTUITerminalWorkspace` | Embedding terminal child processes or building split-pane workspaces |
| `SwiftTUIAnimatedImage` / `SwiftTUICharts` | You need the peer animated-image or charting surfaces |
| `@swifttui/web` / `@swifttui/build` | Packaging a browser/WASI deployment |

A *runner* owns process startup or launch routing; a *host* owns an external
presentation environment. [docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md)
covers that boundary and the platform support matrix.

## Examples

The maintained examples are indexed in
[Examples/README.md](Examples/README.md) — the fastest way to find a sample for
a given product surface or run mode.

| Example | Demonstrates | Run |
| --- | --- | --- |
| [minimal](Examples/minimal) | Lowest-level snapshot rendering | `swiftly run swift run --package-path Examples/minimal minimal` |
| [argparse](Examples/argparse) | `SwiftTUICommand`, consumer + framework flags, completions | `swiftly run swift run --package-path Examples/argparse argparse-demo --help` |
| [gallery](Examples/gallery) | Component workbench: tabs, controls, input, images, charts, animation | `swiftly run swift run --package-path Examples/gallery gallery-demo` |
| [layouts](Examples/layouts) | Layout catalog: stacks, frames, geometry, scrolling, overlays, shapes | `swiftly run swift run --package-path Examples/layouts layouts-demo` |
| [LayoutsSwiftUI](Examples/LayoutsSwiftUI) | Native SwiftUI layout catalog beside the embedded SwiftTUI one | `swiftly run swift run --package-path Examples/LayoutsSwiftUI layouts-swiftui-demo` |
| [file-previewer](Examples/file-previewer) | Miller-column browser with embedded terminal previews | `swiftly run swift run --package-path Examples/file-previewer FilePreviewerApp` |
| [terminal-workspace](Examples/terminal-workspace) | Zellij-style tabs, split panes, command palette, persisted layout | `swiftly run swift run --package-path Examples/terminal-workspace terminal-workspace` |
| [gitviz](Examples/gitviz) | Non-interactive `SwiftTUICharts` command suite over git history | `swiftly run swift run --package-path Examples/gitviz gitviz dashboard --path .` |
| [gifcat](Examples/gifcat) | Terminal-native animated GIF playback | `swiftly run swift run --package-path Examples/gifcat gifcat nyan.gif` |
| [gifeditor](Examples/gifeditor) | Full terminal GIF editor: canvas, layers, timeline, import/export | `swiftly run swift run --package-path Examples/gifeditor gifeditor` |
| [SwiftUIExample](Examples/SwiftUIExample) | Native Apple app embedding SwiftTUI scenes via `SwiftUIHost` | Open `Examples/SwiftUIExample/SwiftUIExample.xcodeproj` |
| [WebHostExample](Examples/WebHostExample) | Smallest app that opts into the localhost browser runner | `swiftly run swift run --package-path Examples/WebHostExample WebHostExample --web` |
| [WebExample](Examples/WebExample) | Static browser/WASI deployment with `@swifttui/web` + `@swifttui/build` | `bun --cwd Examples/WebExample dev` |

## Documentation

Live API reference: <https://swifttui.io/docs/documentation/>

[docs/README.md](docs/README.md) is the canonical index for architecture and
project documentation. Common entry points:

- [docs/VISION.md](docs/VISION.md) — what SwiftTUI is for.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules, products, layout model.
- [docs/RENDER-PIPELINE.md](docs/RENDER-PIPELINE.md) — the frame pipeline and frame-drop policy.
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
