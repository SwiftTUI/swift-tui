# ``SwiftTUI``

Build terminal-native SwiftTUI apps with one import.

## Overview

`SwiftTUI` is the release-facing terminal app convenience module. It re-exports
`SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI` so terminal-native
apps can write:

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

Use `SwiftTUIRuntime` directly when building shared view packages, host
products, or custom launchers that should not inherit terminal runner
convenience behavior. Add peer products such as `SwiftTUICharts`,
`SwiftTUIAnimatedImage`, `SwiftTUITerminal`, or `SwiftTUITerminalWorkspace`
only when that surface is part of your app.

WebHost support remains compile-time opt-in. Apps that intentionally support
both terminal and `--web` launch should depend on and import
`SwiftTUIWebHostCLI` instead.

## Topics

### Getting Started

- <doc:Choosing-Modules-And-Platforms>
