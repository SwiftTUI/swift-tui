# SwiftTUI

**SwiftUI semantics, drawn in terminal cells.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20Linux%20%C2%B7%20iOS%20%C2%B7%20WASI%20%C2%B7%20Android-1E90FF)
![Status](https://img.shields.io/badge/status-0.1.4%20pre--release-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

> Run the live demo and read the API reference at **<https://swifttui.sh>**.

Author your `App` once with the SwiftUI shapes you already know — `View`,
`Scene`, `@State`, `@FocusState`, `VStack`, `ProgressView`, custom `Layout`.
Ship that same view tree five ways: a terminal executable, a static WASI bundle,
a localhost WebHost, a native SwiftUI surface, or a native Android surface. There
is no rewrite per target — and both browser paths paint to the DOM with a real
accessibility tree, not a terminal emulator.

No global constraint solver, no virtual DOM, no `curses`. Every view is lowered
through a strict, inspectable pipeline — resolve → measure → place → semantics →
draw → raster → commit — so layout is deterministic and every frame is
snapshot-testable.

## Why SwiftTUI

- **Your SwiftUI knowledge ports unchanged.** Stacks, frames, `@State`,
  `@Environment`, `ProgressView`, `LabeledContent`, custom `Layout` types, and
  view modifiers behave the way SwiftUI taught you — so there is no second API to
  learn.
- **Frames are a pure function of the view tree and a size proposal.** The same
  input always produces the same cells, which makes snapshot tests trivial and
  regressions cheap to catch.
- **Accessibility ships with the frame.** A semantic substrate under every frame
  drives a linear accessible output path, `--no-color` / `--ascii` fallbacks, and
  reduce-motion behavior — so you get it without wiring it up. See
  [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).
- **One source, five hosts.** Terminal, static WASI bundle, localhost WebHost,
  native SwiftUI surface, and native Android surface are sibling products of one
  package — so the same authored app reaches every target.

## Quick start

Author a view and an `@main` `App` — the same shapes you would write for SwiftUI:

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

Add SwiftTUI to your `Package.swift`. While the package is pre-1.0, pin to the
current beta with `.upToNextMinor` so a minor release cannot break your
build, then depend on the batteries-included `SwiftTUI` product:

```swift
.package(url: "https://github.com/SwiftTUI/swift-tui", .upToNextMinor(from: "0.1.4"))
// in your executable target:
.product(name: "SwiftTUI", package: "swift-tui")
```

`swift run` builds and launches it in the terminal; the app takes the alternate
screen until you exit, then restores your shell. Add `--web` to run the exact
same app through the localhost WebHost in a browser — no code change. That single
`SwiftTUI` import re-exports the platform-neutral runtime, argument parsing, the
combined terminal/WebHost runner, and animated GIF/image playback; charts stay
opt-in via `SwiftTUICharts`.

<details>
<summary>Full <code>Package.swift</code>, platform requirements, standard CLI flags, and lower-level rendering</summary>

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
      .upToNextMinor(from: "0.1.4")
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

**Requirements**

| | |
| --- | --- |
| Swift toolchain | Swift 6.3 (`swift-tools-version: 6.3`) |
| Apple package platforms | macOS 15+, iOS 18+ |
| Terminal / WASI / Android builds | supported via the Swift open-source toolchain |

`SwiftTUITerminal` / PTY embedding is macOS and Linux only. See
[docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md) for the full
platform-by-product matrix.

**Standard CLI flags.** Conform your `App` to `SwiftTUICommand` to get the
framework's standard flag surface (`--accessible`, `--no-color`, `--ascii`,
`--reduce-motion`, `--json`, `--linear`, `--debug`, …) alongside your own
options:

```swift
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
`SWIFTTUI_*` environment variables automatically. See the
[`argparse`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/argparse)
example.

**Lower-level rendering.** For a single deterministic frame rather than an
interactive session — snapshots, previews, non-interactive output — resolve a
`View` directly with `DefaultRenderer` and `TerminalSurfaceRenderer`. See the
[`minimal`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/minimal)
example and the
[SwiftTUIRuntime DocC](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md).

</details>

## Ship it five ways

Author once; pick the product that matches how you ship. The full
platform-by-product matrix lives in
[docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md).

| Ship as | Product | Start here |
| --- | --- | --- |
| Terminal executable (+ `--web`) | `SwiftTUI` (or the explicit `SwiftTUICLI` runner) | the sample above |
| Static WASI / browser bundle | `SwiftTUIWASI` → `@swifttui/web` + `@swifttui/build` | [swift-tui-web](https://github.com/SwiftTUI/swift-tui-web) |
| Native SwiftUI surface (macOS · iOS) | `SwiftUIHost` | [swift-tui-swiftui](https://github.com/SwiftTUI/swift-tui-swiftui) |
| Native Android surface (arm64-v8a) | `SwiftTUIAndroidHost` | [swift-tui-android](https://github.com/SwiftTUI/swift-tui-android) |
| Custom runner / host | `SwiftTUIRuntime` + composed products | [docs/HOSTS-AND-PLATFORMS.md](docs/HOSTS-AND-PLATFORMS.md) |

**Using SwiftTUI from the web.** The same `App` compiles to `wasm32-wasi` and
streams a structured raster surface that a small browser host draws into a
`<canvas>` — no terminal emulator, no rewrite. The two npm packages
[`@swifttui/web`](https://www.npmjs.com/package/@swifttui/web) and
[`@swifttui/build`](https://www.npmjs.com/package/@swifttui/build) own that path;
[`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web) documents it, and
[`swift-tui-examples/WebExample`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebExample)
is the reference template — a complete Bun-served browser app you can copy.

## Examples

The maintained examples live in the sibling
[`SwiftTUI/swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples)
repository — the fastest way to find a sample for a given product surface or run
mode.

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

## Contributing

Small, well-scoped issues and pull requests are easiest to review. The repo uses
the pinned Swift 6.3.1 toolchain through `swiftly`; build and test with:

```bash
swiftly run swift test
bun run test
```

`bun run test` is the repo gate. Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md) for the full build, test, style, and pull-request rules,
and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the exhaustive test surface and
the performance-evaluation harness.

## License

SwiftTUI first-party code is licensed under the MIT License (`MIT`). Vendored
third-party code under `Vendor/` keeps its own license and provenance notices.
See [LICENSE](LICENSE).
