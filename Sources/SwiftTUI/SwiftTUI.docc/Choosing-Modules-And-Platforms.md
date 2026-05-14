# Choosing Modules And Platforms

Pick the SwiftTUI product that matches where your app runs.

## Overview

Most terminal apps should start with one dependency on the root `swift-tui`
package and one import:

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

`SwiftTUI` is the convenience product for terminal-native executables. It
re-exports the view/runtime surface, shared argument parsing, and the terminal
runner that provides the default `App.main()` behavior.

When your app needs a different launch or hosting story, choose one of the
sibling root-package products instead of adding everything by default.

## Import Matrix

| App shape | Depend on | Import |
| --- | --- | --- |
| Terminal-native executable | `SwiftTUI` | `import SwiftTUI` |
| Shared view package or custom host/launcher | `SwiftTUIRuntime` | `import SwiftTUIRuntime` |
| Explicit terminal runner control | `SwiftTUIRuntime` + `SwiftTUICLI` | `import SwiftTUIRuntime` and `import SwiftTUICLI` |
| WASI executable or manifest-mode app | `SwiftTUIWASI` | `import SwiftTUIWASI` |
| Browser deployment from a WASI build | `SwiftTUIWASI` app plus `Platforms/Web` tooling | `import SwiftTUIWASI` in the app |
| Localhost browser app from a native binary | `SwiftTUIWebHost` | `import SwiftTUIWebHost` |
| One binary that supports terminal launch and `--web` | `SwiftTUIWebHostCLI` | `import SwiftTUIWebHostCLI` |
| Native SwiftUI host on Apple platforms | `SwiftUIHost` | `import SwiftUIHost` |
| Embedded terminal program panes | `SwiftTUITerminal` | `import SwiftTUITerminal` |
| Tabbed/split terminal workspaces | `SwiftTUITerminalWorkspace` | `import SwiftTUITerminalWorkspace` |
| Charts and compact metrics | `SwiftTUICharts` | `import SwiftTUICharts` |
| Finite animated images or GIF import/export | `SwiftTUIAnimatedImage` | `import SwiftTUIAnimatedImage` |

`SwiftTUIRuntime`, `SwiftTUICLI`, `SwiftTUIWASI`, `SwiftTUIWebHost`, and
`SwiftTUIWebHostCLI` all re-export the authoring surface, so an executable
usually imports one launch product. Peer content products such as
`SwiftTUICharts`, `SwiftTUIAnimatedImage`, `SwiftTUITerminal`, and
`SwiftTUITerminalWorkspace` are added alongside that launch product when you
use those views.

## Common Compositions

### Terminal App

Use this for a normal command-line application that owns the terminal while it
runs:

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

Terminal-only apps do not link the embedded WebHost server or browser bundle.
If the user passes `--web`, the terminal runner rejects that mode before
entering raw terminal setup.

### Terminal App With Charts

Add charting as a peer product. The chart module reuses the same view and
runtime pipeline; it is not a separate app framework.

```swift
import SwiftTUI
import SwiftTUICharts

struct MetricsView: View {
  var body: some View {
    Sparkline(values: [2, 4, 3, 8, 6])
  }
}
```

### Terminal Plus Local Browser Mode

Use `SwiftTUIWebHostCLI` as the launch import when one executable should run in
the terminal by default and switch to a localhost browser host for `--web`.

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

This is a compile-time choice. A terminal-only `SwiftTUI` binary does not
dynamically discover WebHost support.

### Host-Managed App

Use `SwiftTUIRuntime` for shared app declarations when another product owns the
outer shell. Host products build `SceneManifest` values and retain
`HostedSceneSession` values with explicit presentation surfaces such as
`HostedRasterSurface` instead of relying on the terminal convenience `App.main()`.

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

`SwiftUIHost` uses this shape for native SwiftUI embedding. `Platforms/Web`
uses the same authored scene model with a `SwiftTUIWASI` build and the
browser-side `web-surface` runtime.

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
your app. The repo uses `swiftly`, Bun, and stricter local policy scripts to
develop and verify SwiftTUI itself.

Your app also does not need to copy SwiftTUI's package settings. SwiftTUI uses
Swift 6 language mode, strict memory-safety settings, and explicit actor
annotations internally, but those are the library's build choices. App code
should follow the concurrency settings that match the app and the rest of its
dependencies.

Related runtime guides live in the `SwiftTUIRuntime` documentation catalog:
Host Integration, Running Apps, and Terminal Embedding.
