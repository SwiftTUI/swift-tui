# ``SwiftTUI``

Build batteries-included SwiftTUI apps with one import.

## Overview

`SwiftTUI` is the release-facing convenience module. It re-exports the
platform-neutral runtime, standard argument parsing, the combined
terminal/WebHost runner, and animated GIF/image support. Its `App` protocol is
the batteries-included overlay. It conforms to `SwiftTUICommand` and builds on
`SwiftTUIRuntime.App`. Thus, apps can use this form:

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

> Important: Launch SwiftTUI apps with `@main`. `App.main()` is `async`.
> `@main` binds this asynchronous entry point. Do **not** add a top-level
> `DemoApp.main()` call in `main.swift`. Unlike `SwiftUI.App`, this app uses an
> asynchronous entry point. A direct call selects the synchronous
> `ParsableCommand.main()` overload from swift-argument-parser. It does not
> start the runtime. `await DemoApp.main()` does not change the overload
> selection. SwiftTUI rejects this path with a precise diagnostic.

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

The default `App.main()` (bound by `@main`) uses the terminal runner unless the
parsed configuration requests `--web`, in which case it launches the localhost
WebHost bridge. Use `SwiftTUIRuntime`, `SwiftTUICLI`, `SwiftTUIWebHost`, or
`SwiftTUIWebHostCLI` directly when building a narrower custom graph. Add peer
products such as `SwiftTUITerminal` only when that surface is part of your
app. Charts ship separately from
[`swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts), with
[their own documentation archive](https://swifttui.sh/docs/charts/documentation/swifttuicharts).
For host-managed app declarations that do not conform to `SwiftTUICommand`,
import `SwiftTUIRuntime` directly.

The reference is organized by module, but the developer guides span them:
<doc:Guides> is the task-oriented index across the whole set.

## Topics

### Getting Started

- <doc:Choosing-Modules-And-Platforms>
- <doc:Guides>
