# TerminalUI

Build terminal applications in Swift with a view system, layout model, and runtime shaped after SwiftUI rather than after a terminal-specific DSL.

TerminalUI is for teams who want the ergonomics of declarative SwiftUI authoring without throwing away the discipline that interactive terminal software still needs: cell-based layout, focus and selection routing, capability-aware presentation, lifecycle ownership, task reconciliation, and incremental screen updates.

## Why TerminalUI

- SwiftUI-shaped authoring. You write body-only `View` types, `@State`, `@Binding`, `@FocusState`, `@FocusedValue`, repo-owned `@Bindable`, `Layout`, `PreferenceKey`-driven upward data flow, environment modifiers, and scene declarations with familiar SwiftUI structure.
- SwiftUI-style actor isolation. `View`, `Scene`, `App`, `Resolver.resolve`, and `DefaultRenderer.render` are `@MainActor` authoring APIs, while the pure `Core` pipeline stays nonisolated.
- A real rendering pipeline. Frames move through a strict `resolve -> measure -> place -> semantics -> draw -> raster -> commit` pipeline, which keeps layout, interaction, presentation, and lifecycle work separate and testable.
- Runtime behavior designed for real TUIs. The runtime owns alternate-screen presentation, terminal sizing, keyboard and mouse input, Unix signals, focus routing, lifecycle staging, and task start or cancellation after commit.
- Capability-aware output. The same frame artifacts can be rendered for previews, snapshot tests, or live terminals with ASCII, ANSI16, ANSI256, or true-color output.
- Layered products instead of one monolith. `View` handles authoring, `Core` handles the pure pipeline, `TerminalUI` handles runtime integration, `TerminalUIScenes` adds multi-scene orchestration, and `TerminalUICharts` adds compact charting.

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

For full interactive applications, the public scene-launch story currently goes through `TerminalUIScenes`:

```swift
import TerminalUI
import TerminalUIScenes

@main
struct DemoApp: App {
  static func main() async throws {
    try await MultiSceneLauncher.run(Self())
  }

  var body: some Scene {
    WindowGroup("Deploy Dashboard") {
      BuildSummary()
    }
  }
}
```

`MultiSceneLauncher` gracefully falls back to the single-scene runtime when the app only declares one `WindowGroup`, so the same launch path works for single-window and multi-window apps today.
App and scene construction follow the same main-actor model as SwiftUI, so construct app values on the main actor before launching when you are outside an already main-actor-isolated entry point.

## What Ships Today

- Layout and containers: `VStack`, `HStack`, `ZStack`, `ScrollView`, `List`, `OutlineGroup`, `Table`, `Section`, `ViewThatFits`, and custom `Layout`
- State and focus: `@State`, `@Binding`, repo-owned `@Bindable`, `@FocusState`, focused values, focus effect controls, and default-focus modifiers
- Controls and content: `Text`, `Button`, `Toggle`, `Stepper`, `Slider`, `TextField`, `TextEditor`, `SecureField`, `DisclosureGroup`, `Picker`, `Menu`, `ProgressView`, `Label`, `GroupBox`, `ControlGroup`, `TabView`, `NavigationSplitView`, and terminal-native alert or confirmation presentation
- Runtime integration: `Resolver`, `DefaultRenderer`, `RunLoop`, terminal input parsing, signal handling, alternate-screen ownership, capability-aware presentation, and lifecycle or task staging
- Multi-scene orchestration: optional `TerminalUIScenes` support for pty-backed secondary scenes, scene discovery, and attachment
- Compact metrics and charts: `ProgressView`, `BarChart`, `ColumnChart`, `ComparisonChart`, `Sparkline`, `Timeline`, `ThresholdGauge`, and related support types in `TerminalUICharts`

## Package Products

| Product | Role |
| --- | --- |
| `View` | SwiftUI-shaped view authoring surface: `View`, builders, property wrappers, environment, focus, layouts, containers, and controls. |
| `Core` | Pure frame-pipeline types and algorithms: geometry, styling, layout, semantics, draw extraction, rasterization, diagnostics, and commit planning. No terminal I/O. |
| `TerminalUI` | Runtime integration for terminals: `Resolver`, `DefaultRenderer`, `RunLoop`, terminal host I/O, input parsing, signal handling, and presentation planning. |
| `TerminalUIScenes` | Optional scene-runtime layer for multi-window apps, scene discovery, pty-backed secondary scenes, and attachment flows. |
| `TerminalUICharts` | Compact chart and metric views built on `View` and `Core`. Useful for dashboards and operational surfaces without changing the core architecture story. |

Prototype and showcase code still lives in this repository, but it is intentionally not part of the supported package product surface. In particular, `PrototypeUIComponents` remains a repo-local target for experiments and regression coverage rather than a downstream import.

## Requirements

- macOS 15+
- An Apple Swift 6.3 toolchain is currently recommended for local builds and documentation generation

If multiple Swift toolchains are installed, prefer `xcrun swift ...` so builds and DocC generation use the Xcode-selected toolchain consistently.

## Build And Test

```bash
xcrun swift build
xcrun swift test
```

## Documentation

Generate per-module DocC archives with:

```bash
xcrun swift package generate-documentation --target TerminalUI
```

## Current Constraints

- The core `TerminalUI` runtime is still intentionally narrow: one active terminal host, one active scene, and one full-canvas `WindowGroup` per session.
- The scene-based public launch path currently lives in `TerminalUIScenes.MultiSceneLauncher`, including the single-scene case.
- Terminal-native help strips and command palettes are still experimental. They currently live in the repo-local `PrototypeUIComponents` target rather than in the supported package product surface, though the gallery and Todoist examples now mirror those patterns through local composition.

## Upcoming Work

- `NavigationStack`, `Toolbar`, and sheet or popover-style presentation
- richer focus ergonomics, scroll control, and settled terminal-native help or command surfaces

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
- `*.docc` catalogs inside `Sources/*`: module landing pages and API-focused guides for `Core`, `View`, `TerminalUI`, `TerminalUIScenes`, and `TerminalUICharts`
