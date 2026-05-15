# Examples

This directory keeps the maintained example apps and package shells. It is the
canonical roster for runnable examples in this repo; if a new example is added,
add it here and give the example directory its own README.

Use `swiftly run swift ...` for Swift packages so the examples use the repo's
pinned Swift toolchain. Use the repo root for the commands below unless a local
README says otherwise.

## Roster

| Example | Surface | What it proves | Run |
| --- | --- | --- | --- |
| [minimal](minimal) | Snapshot renderer | Lowest public render path: `DefaultRenderer` to `TerminalSurfaceRenderer`, with no app runtime or argument parser | `swiftly run swift run --package-path Examples/minimal minimal` |
| [argparse](argparse) | Terminal app CLI | `SwiftTUICommand`, consumer flags, standard SwiftTUI flags, and completions in one app type | `swiftly run swift run --package-path Examples/argparse argparse-demo --help` |
| [gallery](gallery) | Terminal app plus optional WebHost | Primary component workbench for the public view surface: tabs, controls, palette, text input, scroll commands, charts, images, animated GIFs, file drop, popovers, and physics | `swiftly run swift run --package-path Examples/gallery gallery-demo` |
| [layouts](layouts) | Terminal app | SwiftTUI layout catalog with behavior tests for stacks, frames, geometry, scrolling, overlays, shapes, matched geometry, and custom layouts | `swiftly run swift run --package-path Examples/layouts layouts-demo` |
| [LayoutsSwiftUI](LayoutsSwiftUI) | SwiftUI comparison app | Native SwiftUI layout catalog beside the embedded SwiftTUI catalog through `SwiftUIHost` | `swiftly run swift run --package-path Examples/LayoutsSwiftUI layouts-swiftui-demo` |
| [file-previewer](file-previewer) | Terminal app plus embedded processes | Miller-column browser and file previews through `SwiftTUITerminal` / `TerminalProcessSession` | `swiftly run swift run --package-path Examples/file-previewer FilePreviewerApp` |
| [terminal-workspace](terminal-workspace) | Terminal workspace | First-party `SwiftTUITerminalWorkspace` surface: tabs, splits, retained sessions, command palette actions, and persisted layout metadata | `swiftly run swift run --package-path Examples/terminal-workspace terminal-workspace` |
| [gitviz](gitviz) | Non-interactive CLI | `SwiftTUICharts` over real git data, with one or more commands for every chart primitive | `swiftly run swift run --package-path Examples/gitviz gitviz dashboard --path .` |
| [gifcat](gifcat) | Terminal app | `SwiftTUIAnimatedImage` playback, source GIF delays, regular-size image attachments, and row-major tiling of multiple GIFs | `swiftly run swift run --package-path Examples/gifcat gifcat nyan.gif` |
| [gifeditor](gifeditor) | Terminal app plus optional WebHost | Full GIF editor: half-cell canvas, palette, tools, layers, timeline, pointer input, undo/redo, and GIF import/export | `swiftly run swift run --package-path Examples/gifeditor gifeditor` |
| [SwiftUIExample](SwiftUIExample) | Native Apple app | SwiftUI host app embedding reusable SwiftTUI scenes through `SwiftUIHost` | `open Examples/SwiftUIExample/SwiftUIExample.xcodeproj` |
| [WebHostExample](WebHostExample) | Localhost browser host | Smallest `SwiftTUIWebHostCLI` opt-in app; terminal by default, browser host with `--web` | `swiftly run swift run --package-path Examples/WebHostExample WebHostExample --web` |
| [WebExample](WebExample) | Static browser/WASI app | Browser deployment using `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build`, and a Bun-served host shell | `bun --cwd Examples/WebExample dev` |

## By Product

| Product or package | Examples |
| --- | --- |
| `SwiftTUI` app/runtime surface | [argparse](argparse), [gallery](gallery), [layouts](layouts), [file-previewer](file-previewer), [terminal-workspace](terminal-workspace), [gifcat](gifcat), [gifeditor](gifeditor), [WebHostExample](WebHostExample) |
| `SwiftTUIRuntime` / low-level rendering | [minimal](minimal), [gallery](gallery), [WebExample](WebExample) |
| `SwiftTUIArguments` / `SwiftTUICommand` | [argparse](argparse), [gallery](gallery), [gifeditor](gifeditor), [gitviz](gitviz) |
| `SwiftTUICharts` | [gitviz](gitviz), [gallery](gallery), [layouts](layouts) |
| `SwiftTUIAnimatedImage` | [gifcat](gifcat), [gallery](gallery) |
| `SwiftTUITerminal` | [file-previewer](file-previewer) |
| `SwiftTUITerminalWorkspace` | [terminal-workspace](terminal-workspace) |
| `SwiftUIHost` | [SwiftUIExample](SwiftUIExample) |
| `SwiftTUIWebHostCLI` | [WebHostExample](WebHostExample), [gallery](gallery), [gifeditor](gifeditor) |
| `SwiftTUIWASI`, `@swifttui/web`, `@swifttui/build` | [WebExample](WebExample) |

## Focused Tests

```bash
swiftly run swift test --package-path Examples/file-previewer
swiftly run swift test --package-path Examples/gallery
swiftly run swift test --package-path Examples/gifcat
swiftly run swift test --package-path Examples/gifeditor
swiftly run swift test --package-path Examples/gitviz
swiftly run swift test --package-path Examples/layouts
swiftly run swift test --package-path Examples/terminal-workspace
swiftly run swift test --package-path Examples/WebHostExample
bun test --cwd Examples/WebExample
```

Examples without focused test targets are still covered by
`Scripts/test_all.sh`: [minimal](minimal) runs a smoke render,
[argparse](argparse) builds, [LayoutsSwiftUI](LayoutsSwiftUI) builds on Apple
platforms, and [SwiftUIExample](SwiftUIExample) builds its reusable scene
package plus the Xcode host app on Apple platforms. The repo gate remains
`bun run test` from the repo root and intentionally includes only
[gallery](gallery) from the examples set; use `bun run test:all` for exhaustive
example coverage.
