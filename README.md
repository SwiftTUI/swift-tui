# SwiftTUI

**SwiftUI semantics, drawn in terminal cells.**

![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%C2%B7%20Linux%20%C2%B7%20Windows%20%C2%B7%20iOS%20%C2%B7%20WASI%20%C2%B7%20Android-1E90FF)
![Status](https://img.shields.io/badge/beta-0.9.5-DAA520)
![License](https://img.shields.io/badge/license-MIT-3DA639)

> Run the live demo and read the API reference at **<https://swifttui.sh>**.

SwiftTUI borrows the take model SwiftUI has proven at scale — that interface is a function of state — and aims it at terminal cells. Declare
views with `View`, `Scene`, `@State`, `@FocusState`, `VStack`, `ProgressView`,
and custom `Layout` types; the framework owns layout, focus, redraw, and the
terminal itself. Terminal first, not terminal only: the same view tree also
ships as a static WASI bundle, a localhost WebHost, a native SwiftUI surface,
or a native Android surface, with no rewrite per target. Both browser paths
paint to the DOM with a real accessibility tree, not a terminal emulator.

SwiftTUI uses no global constraint solver, no virtual DOM, and no `curses`.
Every view is lowered through a strict, inspectable pipeline (resolve →
measure → place → semantics → draw → raster → commit), so layout is
deterministic and every frame is snapshot-testable.

## Project State

> [!IMPORTANT]
> SwiftTUI is being developed and is pre-SemVer `1.0.0`.  

The API has now stabilized but there may still be breaking changes made
before `1.0.0`. These will be documented in the [CHANGELOG](https://github.com/SwiftTUI/swift-tui/blob/main/CHANGELOG.md).

Please [open a github issue](https://github.com/SwiftTUI/swift-tui/issues/new/choose) for SwiftUI-style APIs that you notice are missing — as well as any bugs, behavior questions, or difficulties you hit.

## Why SwiftTUI

- **State in, screen out.** Views are a pure function of your app's state:
  change a value and the runtime recomputes layout and rewrites exactly the
  cells that changed. There is no draw loop, no buffer diffing, and no repaint
  bookkeeping.
- **Real components, real focus.** Buttons, text fields, pickers, sliders,
  scroll views, and charts come with a focus engine, tab traversal, keyboard
  chords, tap · drag · hover gestures, and animation built in. You compose
  behavior instead of hand-routing key events to widgets.
- **The terminal, negotiated for you.** Truecolor, Kitty and Sixel images,
  OSC 8 hyperlinks, and mouse reporting are probed per session and degrade
  gracefully: one binary is correct in kitty, a bare SSH session, or CI. You
  write views, not escape codes.
- **One compiled binary.** Swift 6 compiles your interface into a single fast
  executable with checked concurrency. Frames are a pure function of the view
  tree and a size proposal (the same input always produces the same cells),
  and tests render them as integer-cell rasters without a TTY.
- **Accessibility ships with the frame.** A semantic substrate under every frame
  drives the terminal's cursor-follows-focus mode (`--accessible`), the
  browser ARIA tree, and the native host overlays. It also drives
  `--no-color` / `--ascii` fallbacks and reduce-motion behavior. See
  [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).
- **One source across host presentations.** The same authored app reaches the
  [canonical host matrix](docs/HOSTS-AND-PLATFORMS.md#canonical-host-matrix);
  that owner records which integrations ship in this package and which are
  distributed separately.

## Quick start

SwiftTUI apps are plain SwiftPM packages: any Swift 6.3+ toolchain builds and
runs them from the command line, on macOS, Linux, or Windows, with no Xcode
project, no simulator, and no app store. Author a view and an `@main` `App`:

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

Add SwiftTUI to your `Package.swift`. While the package is before version 1.0,
pin to the current beta with `.upToNextMinor`. This requirement prevents a
minor release from breaking your build. Then add the `SwiftTUI` product:

```swift
.package(url: "https://github.com/SwiftTUI/swift-tui", .upToNextMinor(from: "0.9.5"))
// in your executable target:
.product(name: "SwiftTUI", package: "swift-tui")
```

`swift run` builds the app and launches it in the terminal. The app uses the
alternate screen until you exit. Then it restores your shell. Add `--web` to
run the same app through the localhost WebHost in a browser. This mode requires
no code change. On Windows the `SwiftTUI` import serves the terminal surface
only, so `--web` is unavailable there.

The `SwiftTUI` import re-exports the platform-neutral runtime, argument parser,
combined terminal/WebHost runner, and animated-image playback. Charts ship in
[`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts).

<details>
<summary>Full <code>Package.swift</code>, platform requirements, standard CLI flags, and lower-level rendering</summary>

Use this minimal `Package.swift` for a terminal app:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DeployDashboard",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(
      url: "https://github.com/SwiftTUI/swift-tui",
      .upToNextMinor(from: "0.9.5")
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
| Windows terminal builds | Windows 10 1809+ (build 17763) / Windows Server 2019+, `aarch64-` / `x86_64-unknown-windows-msvc` |

`SwiftTUITerminal` / PTY embedding is macOS and Linux only. On Windows the
umbrella serves the terminal launch surface only (no `--web`), and real apps
should link with `-Xlinker /STACK:16777216` — release builds included — or the
runtime degrades to the stack-lean engine profile below the 8 MiB main-thread
stack floor. See the
[Hosts And Platforms](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md)
DocC article for the full platform-by-product matrix.

**Standard CLI flags.** Conform your `App` to `SwiftTUICommand`. This protocol
adds the
framework's standard flag surface (`--accessible`, `--no-color`, `--ascii`,
`--reduce-motion`, `--stable-output`, `--json`, `--debug`, …) alongside your own
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

Apps without `SwiftTUICommand` still use `NO_COLOR`, `LANG=C`, and the
`SWIFTTUI_*` environment variables. See the
[`argparse`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/argparse)
example.

**Lower-level rendering.** For one deterministic frame, resolve a `View`
directly with `DefaultRenderer` and `TerminalSurfaceRenderer`. This method
supports snapshots, previews, and non-interactive output. See the
[`minimal`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/minimal)
example and the
[SwiftTUIRuntime DocC](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md).

</details>

## Ship it five ways

Terminal first, not terminal only. Author the app once and select the product
that matches the delivery method. The
full platform-by-product matrix lives in the
[Hosts And Platforms](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md)
DocC article.

| Ship as | Product | Start here |
| --- | --- | --- |
| Terminal executable (+ `--web` outside Windows) | `SwiftTUI` (or the explicit `SwiftTUICLI` runner) | the sample above |
| Static WASI / browser bundle | `SwiftTUIWASI` → `@swifttui/web` + `@swifttui/build` | [swift-tui-web](https://github.com/SwiftTUI/swift-tui-web) |
| Native SwiftUI surface (macOS · iOS) | `SwiftUIHost` | [swift-tui-swiftui](https://github.com/SwiftTUI/swift-tui-swiftui) |
| Native Android surface (arm64-v8a) | `SwiftTUIAndroidHost` | [swift-tui-android](https://github.com/SwiftTUI/swift-tui-android) |
| Custom runner / host | `SwiftTUIRuntime` + composed products | [Hosts And Platforms](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md) |

**Using SwiftTUI from the web.** The same `App` compiles to `wasm32-wasi` and
streams a structured raster surface. A small browser host paints this surface
to the DOM and mounts a real accessibility tree. This path does not use a
terminal emulator. It requires no application rewrite. The two npm packages
[`@swifttui/web`](https://www.npmjs.com/package/@swifttui/web) and
[`@swifttui/build`](https://www.npmjs.com/package/@swifttui/build) own that path.
[`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web) documents it, and
[`swift-tui-examples/WebExample`](https://github.com/SwiftTUI/swift-tui-examples/tree/main/WebExample)
is the reference template. You can copy this complete Bun-served browser app.

## Examples

The maintained examples live in the sibling
[`SwiftTUI/swift-tui-examples`](https://github.com/SwiftTUI/swift-tui-examples)
repository. Use these examples to find a sample for a product surface or run
mode.

## Documentation

**Using SwiftTUI?** The live API reference and guides are at
<https://swifttui.sh/docs/documentation/>. The same articles are authored as
DocC catalogs in this repository. Start with:

- [Choosing Modules And Platforms](Sources/SwiftTUI/SwiftTUI.docc/Choosing-Modules-And-Platforms.md): which product to import.
- [Hosts And Platforms](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md): execution modes, engine profiles, and platform support.
- [About SwiftTUI](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Vision.md): SwiftUI faithfulness and the principled API omissions.
- [Runtime Render Pipeline](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md): the runtime callpath, frame pipeline, diagnostics, and host handoff.
- [Accessibility](Sources/SwiftTUIViews/SwiftTUIViews.docc/Accessibility.md): semantic modifiers, announcements, and reduced motion.
- [Environment Variables](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Environment-Variables.md): every `SWIFTTUI_*` variable.

**Working on SwiftTUI?** [docs/README.md](docs/README.md) indexes the
`HEAD`-state architecture and contract documentation
([ARCHITECTURE](docs/ARCHITECTURE.md), the
[public surface policy](docs/PUBLIC-API.md), and more). Maintainer
development docs (the codebase guide, the build/test/release process, and
the flake register) live in the
[`swift-tui-org` coordination repository](https://github.com/SwiftTUI/swift-tui-org/tree/main/docs/swift-tui).

Questions? Join the community on
[Discord](https://discord.gg/8j35kYDFxn).

Build the combined DocC archive locally with:

```bash
Scripts/build_docc_archive.sh
```

## Contributing

Small, well-scoped issues and pull requests are easiest to review. The repo uses
the pinned Swift 6.3.3 toolchain through `swiftly`. Build and run tests with:

```bash
swiftly run swift test
bun run test
```

`bun run test` is the repo gate. Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md) for the full build, test, style, and pull-request rules.
Read [DEVELOPMENT.md](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/DEVELOPMENT.md)
in the `swift-tui-org` coordination repository for the complete test surface
and performance-evaluation harness.

## License

SwiftTUI first-party code is licensed under the MIT License (`MIT`). Vendored
third-party code under `Vendor/` keeps its own license and provenance notices.
See [LICENSE](LICENSE).
