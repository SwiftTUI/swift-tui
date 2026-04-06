# TerminalUI

Build terminal applications in Swift with a view system, layout model, and runtime shaped after SwiftUI rather than after a terminal-specific DSL.

TerminalUI is for teams who want the ergonomics of declarative SwiftUI authoring without throwing away the discipline that interactive terminal software still needs: cell-based layout, focus and selection routing, capability-aware presentation, lifecycle ownership, task reconciliation, and incremental screen updates.

## Why TerminalUI

- SwiftUI-shaped authoring. You write body-only `View` types, `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, repo-owned `@Bindable`, `Layout`, `PreferenceKey`-driven upward data flow, environment modifiers, and scene declarations with familiar SwiftUI structure.
- SwiftUI-style actor isolation. `View`, `Scene`, `App`, `Resolver.resolve`, and `DefaultRenderer.render` are `@MainActor` authoring APIs, while the pure `Core` pipeline stays nonisolated.
- A real rendering pipeline. Frames move through a strict `resolve -> measure -> place -> semantics -> draw -> raster -> commit` pipeline, which keeps layout, interaction, presentation, and lifecycle work separate and testable.
- Runtime behavior designed for real TUIs. The runtime owns alternate-screen presentation, terminal sizing, keyboard and mouse input, Unix signals, focus routing, lifecycle staging, and task start or cancellation after commit.
- Capability-aware output. The same frame artifacts can be rendered for previews, snapshot tests, or live terminals with ASCII, ANSI16, ANSI256, or true-color output.
- Layered products instead of one monolith. `View` handles authoring, `Core` handles the pure pipeline, `TerminalUI` handles shared runtime integration plus wrapper-facing scene hosting, and `TerminalUICharts` adds compact charting. Executable launch lives in peer runner packages: `Runners/TerminalUICLI`, `GUI/SwiftUITUIGUI`, and `Runners/TerminalUIWASI`; the web story is `GUI/WebTUIGUI` on top of a WASI build.

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

For full interactive applications, choose a runner package. For terminal-native
apps, import `TerminalUICLI`:

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

The same authored `App` and `Scene` declarations also feed `GUI/SwiftUITUIGUI`
for SwiftUI-hosted apps and `Runners/TerminalUIWASI` for WASI builds.
`TerminalUI` on its own is library-only and does not provide an executable
product or default `App.main()`.

## What Ships Today

- Layout and containers: `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, and custom `Layout`
- State and focus: `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, focused values, focus effect controls, and default-focus modifiers
- Controls and content: `Text`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, `ProgressView`, `Label`, `GroupBox`, `ControlGroup`, `TabView`, `NavigationSplitView`, and terminal-native alert or confirmation presentation
- Presentation and workflow surfaces: `alert`, `confirmationDialog`, `sheet`, `toast`, command registration through `.command(...)`, and command discovery through `CommandPalette` / `.commandPalette(...)`
- Toolbar chrome: `toolbar(...)`, `toolbarItem(...)`, and `toolbarStyle(.default)` for terminal-native top and bottom bars
- Runtime integration: `Resolver`, `DefaultRenderer`, `RunLoop`, terminal input parsing, signal handling, alternate-screen ownership, capability-aware presentation, and lifecycle or task staging
- Platform runners: `Runners/TerminalUICLI` for native CLI launch and attach flows, `GUI/SwiftUITUIGUI` for SwiftUI hosting, `Runners/TerminalUIWASI` for WASI launch, and `GUI/WebTUIGUI` as the Bun web host that consumes the WASI build
- Compact metrics and charts: `ProgressView`, `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, and related support types in `TerminalUICharts`

## Package Products

| Library Product | Role |
| --- | --- |
| `View` | SwiftUI-shaped authoring surface: `View`, builders, property wrappers, environment, focus, layouts, containers, and controls. |
| `TerminalUI` | Terminal runtime integration plus low-level rendering entry points, scene manifests, and retained hosted-scene sessions for wrapper packages. This product re-exports the `View` and `Core` layers used by the runtime. |
| `TerminalUICharts` | Compact chart and metric views built on `View` and the shared pipeline types re-exported through `TerminalUI`. |

`Core` remains the shared pipeline and data-model target that powers these
products, but it is not shipped as a separate library product today.

Prototype and showcase code still lives in this repository, but it is
intentionally not part of the supported package product surface. In
particular, `PrototypeUIComponents` remains a repo-local target for help-strip
and other exploratory workflow surfaces plus regression coverage rather than a
downstream import.

## Runner Packages

- `Runners/TerminalUICLI`: terminal-native executable runner, scene discovery, ptys, and attach flows
- `GUI/SwiftUITUIGUI`: SwiftUI host package for macOS and iOS
- `Runners/TerminalUIWASI`: WASI executable runner plus manifest mode
- `GUI/WebTUIGUI`: Bun-only browser host that consumes a `TerminalUIWASI` build

## Requirements

- macOS 15+ for local package development on Apple platforms
- Swift 6.3.0 managed through `swiftly`

This repo pins Swift `6.3.0` in [`.swift-version`](/Users/adamz/Developer/repos/swift-terminal-ui/.swift-version).
Use `swiftly` by default for repo-local SwiftPM work.

Verify before building:

```bash
swiftly run swift --version
```

The shorter `swift ...` form is also fine when your shell already resolves
`swift` through the `swiftly`-managed Swift 6.3.0 toolchain. Native-only builds
should also work fine in Xcode, but the default documented path in this repo is
still `swiftly`.

Use [docs/TOOLCHAINS.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/TOOLCHAINS.md) as the source of truth for native, wasm, Bun, Xcode, and Android toolchain expectations.

## Build And Test

```bash
swiftly run swift build
swiftly run swift test
```

## Documentation

Generate per-module DocC archives with:

```bash
swiftly run swift package generate-documentation --target TerminalUI
```

## GUI Wrapper Packages

Peer GUI packaging lives outside the root package products:

- `GUI/SwiftUITUIGUI`: SwiftUI wrapper package for macOS and iOS, built on `TerminalUI` scene manifests and `HostedSceneSession`
- `GUI/WebTUIGUI`: Bun-based web wrapper package that builds a TerminalUI wasm app bundle and hosts it in the browser

## Current Constraints

- The core `TerminalUI` runtime is still intentionally narrow: one active terminal host, one active scene, and one full-canvas `WindowGroup` per session.
- Executable launch policy now lives outside the root package. Use `Runners/TerminalUICLI` for terminal-native apps, `GUI/SwiftUITUIGUI` for SwiftUI hosts, or `Runners/TerminalUIWASI` for WASI builds; `GUI/WebTUIGUI` consumes the WASI output.
- The terminal-native toolbar surface is now supported through `toolbar(...)`, `toolbarItem(...)`, and `toolbarStyle(.default)`. The older keyboard-help APIs are removed, and the gallery now demonstrates the toolbar surface directly.
- Command registration, sheets, toasts, and the command palette are now part of the supported `View` surface. Prototype help-strip exploration still lives in `PrototypeUIComponents` while broader launcher-like shell workflows remain unsettled.

## Upcoming Work

- `NavigationStack` and richer popover-style presentation beyond the current sheet support
- richer focus ergonomics and scroll control

## Documentation

- [README](README.md): public overview, product map, and getting-started entry point
- [docs/README.md](docs/README.md): internal documentation index and maintenance notes
- [docs/VISION.md](docs/VISION.md): project philosophy, scope, and deferred work
- [docs/STATUS.md](docs/STATUS.md): shipped surface, current constraints, and short-term gaps
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): target boundaries and frame pipeline
- [docs/RUNTIME.md](docs/RUNTIME.md): runtime behavior, lifecycle semantics, and incremental-cost model
- [docs/SOURCE_LAYOUT.md](docs/SOURCE_LAYOUT.md): source ownership map across targets and key files
- [docs/PUBLIC_API_INVENTORY.md](docs/PUBLIC_API_INVENTORY.md): classified public-surface inventory
- [docs/PUBLIC_SURFACE_POLICY.md](docs/PUBLIC_SURFACE_POLICY.md): public API governance rules
- `*.docc` catalogs inside `Sources/*`: module landing pages and API-focused guides for `Core`, `View`, `TerminalUI`, and `TerminalUICharts`
