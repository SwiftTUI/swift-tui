# SwiftTUI

Build terminal applications in Swift with a view system, layout model, and runtime shaped after SwiftUI rather than after a terminal-specific DSL.

SwiftTUI is for teams who want the ergonomics of declarative SwiftUI authoring without throwing away the discipline that interactive terminal software still needs: cell-based layout, focus and selection routing, capability-aware presentation, lifecycle ownership, task reconciliation, and incremental screen updates.

## Why SwiftTUI

- SwiftUI-shaped authoring. You write body-only `View` types, `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, repo-owned `@Bindable`, `Layout`, `PreferenceKey`-driven upward data flow, environment modifiers, and scene declarations with familiar SwiftUI structure.
- SwiftUI-style actor isolation. `View`, `Scene`, `App`, `Resolver.resolve`, and `DefaultRenderer.render` are `@MainActor` authoring APIs, while the pure `Core` pipeline stays nonisolated.
- A real rendering pipeline. Frames move through a strict `resolve -> measure -> place -> semantics -> draw -> raster -> commit` pipeline, which keeps layout, interaction, presentation, and lifecycle work separate and testable.
- Runtime behavior designed for real TUIs. The runtime owns alternate-screen presentation, terminal sizing, keyboard and mouse input, Unix signals, focus routing, lifecycle staging, and task start or cancellation after commit.
- Capability-aware output. The same frame artifacts can be rendered for previews, snapshot tests, or live terminals with ASCII, ANSI16, ANSI256, or true-color output.
- Layered products instead of one monolith. `View` handles authoring, `Core` handles the pure pipeline, `SwiftTUI` handles shared runtime integration plus host-facing scene hosting, and `SwiftTUICharts` adds compact charting. Platform integration lives in peer packages: executable runner packages in `Runners/` and embedded host packages in `GUI/`.

## A Quick Look

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

The same authored `App` and `Scene` declarations can then flow into three
execution modes:

- terminal-native execution via the executable runner package `Runners/SwiftTUICLI`
- WASI execution via the executable runner package `Runners/SwiftTUIWASI`
- host-managed embedding via the embedded host packages `GUI/SwiftUIHost`
  and `GUI/WebHost`

`SwiftTUI` on its own is library-only. It provides the shared runtime,
`SceneManifest`, and `HostedSceneSession`, but it does not provide an
executable product or default `App.main()`.

## What Ships Today

- Layout and containers: `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, and custom `Layout`
- State and focus: `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, focused values, focus effect controls, and default-focus modifiers
- Controls and content: `Text`, `TextFigure` (banner text backed by embedded FIGlet fonts), `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, `ProgressView`, `Label`, `GroupBox`, `ControlGroup`, `TabView`, and `Image` (PNG, JPEG, and GIF, dispatched on magic bytes)
- Presentation and workflow surfaces: `alert`, `confirmationDialog`, `sheet`, `toast`
- Action scopes and commands: `Panel`, `.keyCommand`, `.paletteCommand`, `.toolbar`, `.toolbarItem`, with shallowest-wins focus-chain dispatch
- Runtime integration: `Resolver`, `DefaultRenderer`, `RunLoop`, terminal input parsing, signal handling, alternate-screen ownership, capability-aware presentation, and lifecycle or task staging
- Platform integration packages: executable runners `Runners/SwiftTUICLI` and `Runners/SwiftTUIWASI`, plus embedded hosts `GUI/SwiftUIHost` and `GUI/WebHost`
- Compact metrics and charts: `ProgressView`, `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, and related support types in `SwiftTUICharts`

## Package Products

| Library Product | Role |
| --- | --- |
| `View` | SwiftUI-shaped authoring surface: `View`, builders, property wrappers, environment, focus, layouts, containers, and controls. |
| `SwiftTUI` | Terminal runtime integration plus low-level rendering entry points, scene manifests, and retained hosted-scene sessions for embedded host packages. This product re-exports the `View` and `Core` layers used by the runtime. |
| `SwiftTUICharts` | Compact chart and metric views built on `View` and the shared pipeline types re-exported through `SwiftTUI`. |

`Core` remains the shared pipeline and data-model target that powers these
products, but it is not shipped as a separate library product today.

Showcase code may still live in this repository through example packages, but
it is intentionally not part of the supported package product surface.

## Platform Integration Model

Authored `View`, `Scene`, and `App` values feed a shared runtime in
`SwiftTUI`, then a peer platform integration package connects that runtime to
the concrete shell:

- authored app surface: `View`, `Scene`, and `App`
- shared runtime: `RunLoop`, `SceneManifest`, and `HostedSceneSession`
- peer platform integration package: an executable runner package or an embedded host package
- platform shell: a terminal process, a WASI runtime, a SwiftUI app, or a browser host

Executable runner packages own top-level execution and default `App.main()`
stories. Embedded host packages retain one or more hosted scene sessions inside
another app or runtime lifecycle.

## Platform Integration Packages

- executable runner packages:
  - `Runners/SwiftTUICLI`: terminal-native executable runner, scene discovery, ptys, and attach flows
  - `Runners/SwiftTUIWASI`: WASI executable runner plus manifest mode
- embedded host packages:
  - `GUI/SwiftUIHost`: native SwiftUI host package for macOS and iOS
  - `GUI/WebHost`: Bun-based browser host that consumes a `SwiftTUIWASI` build and a canvas surface transport (no terminal emulator dependency)

## Requirements

- macOS 15+ for local package development on Apple platforms
- Swift 6.3.1 managed through `swiftly`

The repo pins Swift `6.3.1` in [`.swift-version`](.swift-version) and uses
`swiftly` as the default SwiftPM driver. See
[docs/TOOLCHAINS.md](docs/TOOLCHAINS.md) for the full native, wasm, Bun, Xcode,
and Android toolchain story.

## Build And Test

```bash
swiftly run swift build
swiftly run swift test
Scripts/test_all.sh
bun run test
```

`swiftly run swift test` covers the root package. `Scripts/test_all.sh` is the
single repo-level entrypoint for the full checked-in test surface across the
runner packages, GUI packages, and example projects, and it verifies the Swift
and Bun environment first. On Linux, it exports
`DISABLE_EXPLICIT_PLATFORMS=1` and skips the Apple-only
`GUI/SwiftUIHost` SwiftUI host tests. If you're
already using the repo's root Bun workspace, `bun run test` is a thin
entrypoint to the same script.

## API Documentation

Live API reference is published at:

- <https://swifttui.io/docs/documentation/swifttui/>

The same content is mirrored by the Swift Package Index:

- <https://swiftpackageindex.com/GoodHatsLLC/swift-tui/documentation/swifttui>

To build the docs locally, generate per-module DocC archives with:

```bash
swiftly run swift package generate-documentation --target SwiftTUI
```

Or build the combined archive that powers the public site:

```bash
swiftly run swift package \
  --allow-writing-to-directory .build-docs \
  generate-documentation \
  --target View --target SwiftTUI --target SwiftTUICharts \
  --enable-experimental-combined-documentation \
  --transform-for-static-hosting \
  --output-path .build-docs
```

## Current Constraints

- The core `SwiftTUI` runtime is intentionally narrow: one active terminal host, one active scene, and one full-canvas `WindowGroup` per session.
- Platform integration lives outside the root package. Use executable runner packages for terminal-native or WASI execution, and embedded host packages for SwiftUI or browser embedding.

## Deferred By Design

- `NavigationStack` and richer popover-style presentation beyond the current sheet support
- Richer focus ergonomics and scroll control
- Animated GIF playback, broader media formats (WebP, AVIF, video), remote fetching, and asset bundles beyond the current PNG / JPEG / GIF still-image surface

## Documentation

Start with [docs/README.md](docs/README.md) — it is the canonical index for every
design doc, active proposal, and background note in this repository. Per-module
API reference lives in the `*.docc` catalogs under `Sources/`, generated with
the DocC command above.

Common entry points:

- [docs/STATUS.md](docs/STATUS.md): shipped surface and current constraints
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): target boundaries and frame pipeline
- [docs/RUNTIME.md](docs/RUNTIME.md): lifecycle, state, and incremental rendering behavior
- [docs/VISION.md](docs/VISION.md): philosophy, scope, and deferred work
- [Examples/README.md](Examples/README.md): maintained example apps
