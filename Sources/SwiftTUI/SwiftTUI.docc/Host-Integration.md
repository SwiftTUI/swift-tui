# Embedding Modes

How SwiftTUI apps run inside non-terminal hosts: native SwiftUI, browser, and WASI.

## Overview

The same authored ``App``, ``Scene``, and ``WindowGroup`` values run unchanged across three execution modes. Pick the mode that matches your shipping target:

- **Terminal-native runner** — import `SwiftTUICLI` to get the default CLI `App.main()` plus pty-backed scene management. Use when you ship a binary that runs in a real terminal.
- **WASI runner** — import `SwiftTUIWASI` for WebAssembly execution and manifest generation. Use when you ship the app as a wasm module to a browser or sandbox host.
- **Embedded host package** — retain ``HostedSceneSession`` values inside another app's lifecycle. `GUI/SwiftUIHost` does this for native SwiftUI on Apple platforms; `GUI/WebHost` and `GUI/XtermWebHost` do it for browser hosting on top of a WASI build.

All three modes flow through the same runtime invalidation path. Resize, terminal style, and lifecycle events are normalized into the same control-message contract regardless of where the host fetches them.

## See Also

- <doc:Running-Apps>
- <doc:Architecture>
- <doc:Runtime>
- <doc:Vision>
- [Host Packages](https://github.com/adamz/swift-tui/blob/main/docs/HOST_PACKAGES.md)
