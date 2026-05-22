# ``SwiftTUI``

Build batteries-included SwiftTUI apps with one import.

## Overview

`SwiftTUI` is the release-facing convenience module. It re-exports the
platform-neutral runtime, standard argument parsing, the combined
terminal/WebHost runner, and animated GIF/image support so apps can write:

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

The default `App.main()` uses the terminal runner unless the parsed
configuration requests `--web`, in which case it launches the localhost
WebHost bridge. Use `SwiftTUIRuntime`, `SwiftTUICLI`, `SwiftTUIWebHost`, or
`SwiftTUIWebHostCLI` directly when building a narrower custom graph. Add peer
products such as `SwiftTUICharts`, `SwiftTUITerminal`, or
`SwiftTUITerminalWorkspace` only when that surface is part of your app.

## Topics

### Getting Started

- <doc:Choosing-Modules-And-Platforms>
