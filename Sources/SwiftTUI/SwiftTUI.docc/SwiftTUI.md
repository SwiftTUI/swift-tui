# ``SwiftTUI``

Build batteries-included SwiftTUI apps with one import.

## Overview

`SwiftTUI` is the release-facing convenience module. It re-exports the
platform-neutral runtime, standard argument parsing, the combined
terminal/WebHost runner, and animated GIF/image support. Its `App` protocol is
the batteries-included overlay: it conforms to `SwiftTUICommand` while still
building on `SwiftTUIRuntime.App`, so apps can write:

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

Apps that define their own command-line options keep those options on the app
type and add the standard option group:

```swift
@main
struct DemoApp: App {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Option var widgets: Int = 5

  var body: some Scene {
    WindowGroup {
      Text("widgets: \(widgets)")
    }
  }
}
```

The default `App.main()` uses the terminal runner unless the parsed
configuration requests `--web`, in which case it launches the localhost
WebHost bridge. Use `SwiftTUIRuntime`, `SwiftTUICLI`, `SwiftTUIWebHost`, or
`SwiftTUIWebHostCLI` directly when building a narrower custom graph. Add peer
products such as `SwiftTUICharts`, `SwiftTUITerminal`, or
`SwiftTUITerminalWorkspace` only when that surface is part of your app.
Import `SwiftTUIRuntime` directly for host-managed app declarations that should
not conform to `SwiftTUICommand`.

## Topics

### Getting Started

- <doc:Choosing-Modules-And-Platforms>
