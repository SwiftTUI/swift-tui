# Runner And Host Integration

How SwiftTUI apps launch through runner products or live inside host products.

## Overview

The same authored ``App``, ``Scene``, and ``WindowGroup`` values run unchanged
across the supported execution modes. Pick the mode that matches your shipping
target. In repo terminology, a runner owns process startup and launch routing,
while a host owns an external presentation environment or embedding lifecycle.

- **Terminal-native runner** — import `SwiftTUICLI` to get the default CLI `App.main()` plus pty-backed scene management. Use when you ship a binary that runs in a real terminal.
- **WASI runner** — import `SwiftTUIWASI` for WebAssembly execution and manifest generation. Use when you ship the app as a wasm module to a browser or sandbox host.
- **Host product** — retain ``HostedSceneSession`` values inside another app's lifecycle. `SwiftUIHost` does this for native SwiftUI on Apple platforms; `Platforms/Web` does it for browser hosting on top of a WASI build.
- **WebHost runner and browser host** — import `SwiftTUIWebHost` for web-only
  localhost-browser launch, or `SwiftTUIWebHostCLI` when one executable should
  support both terminal-native and `--web` launch. This product is intentionally
  compound: say "WebHost runner" or "browser host" depending on the role.

All modes flow through the same runtime invalidation path. Resize, terminal
style, and lifecycle events are normalized into the same control-message
contract regardless of where the host fetches them.

## See Also

- <doc:Running-Apps>
- <doc:Architecture>
- <doc:Runtime>
- <doc:Vision>
- [Platform Integration Products](https://github.com/adamz/swift-tui/blob/main/docs/HOST_PACKAGES.md)
- [Terminology](https://github.com/adamz/swift-tui/blob/main/docs/TERMINOLOGY.md)
