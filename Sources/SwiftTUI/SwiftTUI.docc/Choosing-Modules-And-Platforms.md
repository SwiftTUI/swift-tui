# Choosing Modules And Platforms

Pick the SwiftTUI product that matches where your app runs.

## Overview

For most apps, start with one dependency on the root `swift-tui` package and
one import:

```swift
import SwiftTUI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Hello")
    }
  }
}
```

`SwiftTUI` is the convenience product for batteries-included executables. It
re-exports the view/runtime surface, shared argument parsing, the combined
terminal/WebHost runner that provides the default `App.main()` behavior, and
animated GIF/image support. Its `App` protocol is the command-enabled
convenience overlay over `SwiftTUIRuntime.App`.

When your app needs a narrower launch or hosting story, choose an in-package
integration product or an externally distributed host. The canonical
packaging boundaries live in
[Hosts and Platforms](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md).

## Import Matrix

| App shape | Depend on | Import |
| --- | --- | --- |
| Batteries-included executable: terminal by default, `--web` when requested, animated GIF/images available, and `App` conforms to `SwiftTUICommand` | `SwiftTUI` | `import SwiftTUI` |
| Shared view package or custom host/launcher | `SwiftTUIRuntime` | `import SwiftTUIRuntime` |
| Explicit terminal runner control | `SwiftTUIRuntime` + `SwiftTUICLI` | `import SwiftTUIRuntime` and `import SwiftTUICLI` |
| WASI executable or manifest-mode app | `SwiftTUIWASI` | `import SwiftTUIWASI` |
| Browser deployment from a WASI build | `SwiftTUIWASI` app plus `@swifttui/web` tooling | `import SwiftTUIWASI` in the app |
| Localhost browser app from a native binary | `SwiftTUIWebHost` | `import SwiftTUIWebHost` |
| One binary that supports terminal launch and `--web` | `SwiftTUIWebHostCLI` | `import SwiftTUIWebHostCLI` |
| Host-managed Android app | `SwiftTUIAndroidHost` | `import SwiftTUIAndroidHost` |
| Native SwiftUI embedding on macOS or iOS | `SwiftUIHost` from the separate [`swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui) package | `import SwiftUIHost` |
| Embedded terminal program panes | `SwiftTUITerminal` | `import SwiftTUITerminal` |
| Tabbed/split terminal workspaces | `SwiftTUITerminalWorkspace` | `import SwiftTUITerminalWorkspace` |
| Charts and compact metrics | `SwiftTUICharts` (from the separate [`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package) | `import SwiftTUICharts` |
| Finite animated images or GIF import/export without the full convenience product | `SwiftTUIAnimatedImage` | `import SwiftTUIAnimatedImage` |

`SwiftTUIRuntime`, `SwiftTUICLI`, `SwiftTUIWASI`, `SwiftTUIWebHost`,
`SwiftTUIWebHostCLI`, and `SwiftTUIAndroidHost` all re-export the authoring
surface, so an executable or host usually imports one integration product.
`SwiftTUI` additionally includes `SwiftTUIAnimatedImage` by default. Add peer
products such as `SwiftTUITerminal` and `SwiftTUITerminalWorkspace` alongside
your launch product only when you use those views. Charts and the SwiftUI host
come from separate packages.

## Common Compositions

### Terminal App

Use this for a normal command-line application that owns the terminal while it
runs and can switch to localhost browser hosting when launched with `--web`:

```swift
import SwiftTUI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Terminal UI")
    }
  }
}
```

The default `SwiftTUI` graph links the embedded WebHost server and browser
bundle so `--web` is available without changing imports. Use `SwiftTUICLI`
directly when you want a terminal-only graph that rejects `--web`.

### Terminal App With Charts

Add charting from the separate
[`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts) package
(product `SwiftTUICharts`, `package: "swift-tui-charts"`). The chart module
uses the same view and runtime pipeline. It is not a separate app framework.

```swift
import SwiftTUI
import SwiftTUICharts

struct MetricsView: View {
  var body: some View {
    Sparkline(values: [2, 4, 3, 8, 6])
  }
}
```

### Narrow Terminal Plus Local Browser Mode

Use `SwiftTUIWebHostCLI` when one executable must run in the terminal by
default. The executable switches to a localhost browser host for `--web`. This
product excludes the remaining `SwiftTUI` convenience surface.

```swift
import SwiftTUIWebHostCLI

@main
struct DemoApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Same app, two launch modes")
    }
  }
}
```

This is the lower-level product that `SwiftTUI` uses for its default launch
behavior.

### Host-Managed App

Use `SwiftTUIRuntime` for shared app declarations when another product owns the
outer shell. Host products build `SceneManifest` values and retain
`HostedSceneSession` values with explicit presentation surfaces such as
`HostedRasterSurface` instead of relying on the convenience `App.main()`.
This `App` is `SwiftTUIRuntime.App`, not the command-enabled `SwiftTUI.App`
overlay.

```swift
import SwiftTUIRuntime

struct HostedApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Hosted scene")
    }
  }
}
```

The in-package `SwiftTUIAndroidHost` product uses this shape for Android
embedding. The external
[`SwiftUIHost`](https://github.com/SwiftTUI/swift-tui-swiftui) product uses it
for native SwiftUI embedding. `@swifttui/web` consumes the same authored scene
model from a `SwiftTUIWASI` build. See
[Hosts and Platforms](https://github.com/SwiftTUI/swift-tui/blob/main/docs/HOSTS-AND-PLATFORMS.md)
for the canonical
distribution and engine-profile matrix.

### Terminal Program Embedding

`SwiftTUITerminal` and `SwiftTUITerminalWorkspace` are opt-in products for
embedding external terminal programs inside SwiftTUI views.

```swift
import SwiftTUI
import SwiftTUITerminal

struct ShellPane: View {
  @State private var session = TerminalProcessSession(
    command: "/bin/zsh",
    initialSize: CellSize(width: 80, height: 24)
  )

  var body: some View {
    TerminalView(session: session)
  }
}
```

Use `SwiftTUITerminalWorkspace` when you want retained tabs and split panes on
top of those terminal sessions.

## What You Do Not Need

Framework users do not need to adopt the repository's local maintainer
toolchain to build an app. Use normal SwiftPM package dependency wiring from
your app. The repository uses `swiftly`, Bun, and stricter local policy scripts
to develop SwiftTUI and run its tests.

Your app also does not need to copy SwiftTUI's package configuration. SwiftTUI uses
Swift 6 language mode, strict memory-safety configuration, and explicit actor
annotations internally, but those are the library's build choices. App code
must use the concurrency configuration that matches the app and its dependencies.

Related runtime guides live in the `SwiftTUIRuntime` documentation catalog:
Host Integration, Running Apps, and Terminal Embedding.
