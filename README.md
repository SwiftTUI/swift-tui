# TerminalUI

Build terminal applications in Swift with a view system, layout model, and runtime shaped after SwiftUI rather than after a terminal-specific DSL.

TerminalUI is for teams who want the ergonomics of declarative SwiftUI authoring without throwing away the discipline that interactive terminal software still needs: cell-based layout, focus and selection routing, capability-aware presentation, lifecycle ownership, task reconciliation, and incremental screen updates.

## Why TerminalUI

- SwiftUI-shaped authoring. You write body-only `View` types, `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, repo-owned `@Bindable`, `Layout`, `PreferenceKey`-driven upward data flow, environment modifiers, and scene declarations with familiar SwiftUI structure.
- SwiftUI-style actor isolation. `View`, `Scene`, `App`, `Resolver.resolve`, and `DefaultRenderer.render` are `@MainActor` authoring APIs, while the pure `Core` pipeline stays nonisolated.
- A real rendering pipeline. Frames move through a strict `resolve -> measure -> place -> semantics -> draw -> raster -> commit` pipeline, which keeps layout, interaction, presentation, and lifecycle work separate and testable.
- Runtime behavior designed for real TUIs. The runtime owns alternate-screen presentation, terminal sizing, keyboard and mouse input, Unix signals, focus routing, lifecycle staging, and task start or cancellation after commit.
- Capability-aware output. The same frame artifacts can be rendered for previews, snapshot tests, or live terminals with ASCII, ANSI16, ANSI256, or true-color output.
- Layered products instead of one monolith. `View` handles authoring, `Core` handles the pure pipeline, `TerminalUI` handles shared runtime integration plus host-facing scene hosting, and `TerminalUICharts` adds compact charting. Platform integration lives in peer packages: executable runner packages in `Runners/` and embedded host packages in `GUI/`.

## A Quick Look

At the lowest public runtime level, you can resolve and render any `View` into terminal text:

```swift
import TerminalUI

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
terminal-native executable apps, import `TerminalUICLI`:

```swift
import TerminalUICLI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`TerminalUICLI` provides the default terminal-native `App.main()`. When you
want an explicit launcher instead of `@main`, call:

```swift
try await TerminalCLIAppRunner.run(DemoApp.self)
```

The same authored `App` and `Scene` declarations can then flow into three
execution modes:

- terminal-native execution via the executable runner package `Runners/TerminalUICLI`
- WASI execution via the executable runner package `Runners/TerminalUIWASI`
- host-managed embedding via the embedded host packages `GUI/SwiftUITUIGUI`,
  `GUI/SwiftTermTUIGUI`, `GUI/WebTUIGUI`, and `GUI/XtermWebTUIGUI`

`TerminalUI` on its own is library-only. It provides the shared runtime,
`TerminalUISceneManifest`, and `HostedSceneSession`, but it does not provide an
executable product or default `App.main()`.

## What Ships Today

- Layout and containers: `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, and custom `Layout`
- State and focus: `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, focused values, focus effect controls, and default-focus modifiers
- Controls and content: `Text`, `TextFigure`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, `ProgressView`, `Label`, `GroupBox`, `ControlGroup`, `TabView`, and terminal-native alert or confirmation presentation backed by embedded FIGlet fonts rather than external font files
- Presentation and workflow surfaces: `alert`, `confirmationDialog`, `sheet`, `toast`
- Runtime integration: `Resolver`, `DefaultRenderer`, `RunLoop`, terminal input parsing, signal handling, alternate-screen ownership, capability-aware presentation, and lifecycle or task staging
- Platform integration packages: executable runners `Runners/TerminalUICLI` and `Runners/TerminalUIWASI`, plus embedded hosts `GUI/SwiftUITUIGUI`, `GUI/SwiftTermTUIGUI`, `GUI/WebTUIGUI`, and `GUI/XtermWebTUIGUI`
- Compact metrics and charts: `ProgressView`, `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, and related support types in `TerminalUICharts`

## Package Products

| Library Product | Role |
| --- | --- |
| `View` | SwiftUI-shaped authoring surface: `View`, builders, property wrappers, environment, focus, layouts, containers, and controls. |
| `TerminalUI` | Terminal runtime integration plus low-level rendering entry points, scene manifests, and retained hosted-scene sessions for embedded host packages. This product re-exports the `View` and `Core` layers used by the runtime. |
| `TerminalUICharts` | Compact chart and metric views built on `View` and the shared pipeline types re-exported through `TerminalUI`. |

`Core` remains the shared pipeline and data-model target that powers these
products, but it is not shipped as a separate library product today.

Showcase code may still live in this repository through example packages, but
it is intentionally not part of the supported package product surface.

## Platform Integration Model

Authored `View`, `Scene`, and `App` values feed a shared runtime in
`TerminalUI`, then a peer platform integration package connects that runtime to
the concrete shell:

- authored app surface: `View`, `Scene`, and `App`
- shared runtime: `RunLoop`, `TerminalUISceneManifest`, and `HostedSceneSession`
- peer platform integration package: an executable runner package or an embedded host package
- platform shell: a terminal process, a WASI runtime, a SwiftUI app, or a browser host

Executable runner packages own top-level execution and default `App.main()`
stories. Embedded host packages retain one or more hosted scene sessions inside
another app or runtime lifecycle.

## Platform Integration Packages

- executable runner packages:
  - `Runners/TerminalUICLI`: terminal-native executable runner, scene discovery, ptys, and attach flows
  - `Runners/TerminalUIWASI`: WASI executable runner plus manifest mode
- embedded host packages:
  - `GUI/SwiftUITUIGUI`: native SwiftUI host package for macOS and iOS
  - `GUI/SwiftTermTUIGUI`: SwiftTerm-backed SwiftUI host package for macOS and iOS
  - `GUI/WebTUIGUI`: Bun-based browser host that consumes a `TerminalUIWASI` build and `ghostty-web`
  - `GUI/XtermWebTUIGUI`: Bun-based browser host that consumes a `TerminalUIWASI` build and xterm.js

## Requirements

- macOS 15+ for local package development on Apple platforms
- Swift 6.3.0 managed through `swiftly`

The repo pins Swift `6.3.0` in [`.swift-version`](.swift-version) and uses
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
`GUI/SwiftUITUIGUI` and `GUI/SwiftTermTUIGUI` SwiftUI host tests. If you're
already using the repo's root Bun workspace, `bun run test` is a thin
entrypoint to the same script.

## Generate API Docs

Generate per-module DocC archives with:

```bash
swiftly run swift package generate-documentation --target TerminalUI
```

## Current Constraints

- The core `TerminalUI` runtime is still intentionally narrow: one active terminal host, one active scene, and one full-canvas `WindowGroup` per session.
- Platform integration now lives outside the root package. Use executable runner packages for terminal-native or WASI execution, and embedded host packages for SwiftUI or browser embedding.
- Presentation surfaces (`alert`, `confirmationDialog`, `sheet`, `toast`) are part of the supported `View` surface. The scope-and-commands authoring surface (`ActionScope`, `Panel`, `FocusContainment`, `keyCommand`, `paletteCommand` with `EnvironmentValues.activePaletteCommands`) has landed with shallowest-wins focus-chain dispatch; toolbar surfaces are still landing against the plan in [docs/proposals/ACTION_SCOPES_AND_COMMANDS.md](docs/proposals/ACTION_SCOPES_AND_COMMANDS.md).

## Upcoming Work

- Remaining phases of the ActionScope/commands rollout: `toolbar` and `toolbarItem`
- `NavigationStack` and richer popover-style presentation beyond the current sheet support
- Richer focus ergonomics and scroll control

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
