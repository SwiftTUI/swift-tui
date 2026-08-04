# Runner And Host Integration

How SwiftTUI apps launch through runner products or live inside host products.

## Overview

The same authored ``App``, ``Scene``, and ``WindowGroup`` values run unchanged
across the supported execution modes. Pick the mode that matches your shipping
target. In repo terminology, a runner owns process startup and launch routing,
while a host owns an external presentation environment or embedding lifecycle.
The canonical mode, packaging, and engine-profile matrix is
<doc:Hosts-And-Platforms>.

- **Batteries-included convenience** — import `SwiftTUI` to get the default
  terminal `App.main()`, pty-backed scene management, `--web` localhost launch,
  and animated GIF/image support. Use when you ship a normal app binary.
- **Explicit terminal runner** — compose `SwiftTUIRuntime` with `SwiftTUICLI`
  when a custom launcher needs direct `TerminalRunner` control.
- **WASI runner** — import `SwiftTUIWASI` for WebAssembly execution and
  manifest generation. Use it to ship the app as a wasm module to a browser or
  sandbox host.
- **Host product** — retain ``HostedSceneSession`` values with explicit
  presentation surfaces such as ``HostedRasterSurface`` inside another app's
  lifecycle. The in-package `SwiftTUIAndroidHost` product uses this contract
  for Android embedding. `@swifttui/web` consumes a WASI build in the browser,
  while the external
  [`SwiftUIHost`](https://github.com/SwiftTUI/swift-tui-swiftui) product uses
  the contract for native SwiftUI embedding on macOS and iOS.
- **WebHost runner and browser host** — import `SwiftTUIWebHost` for a web-only
  localhost-browser launch. Use `SwiftTUIWebHostCLI` directly when one
  executable must support both terminal-native and `--web` launch without the
  full `SwiftTUI` convenience product. This product is intentionally compound:
  say "WebHost runner" or "browser host" depending on the role.

All modes flow through the same runtime invalidation path. Resize, terminal
style, and lifecycle events are normalized into the same control-message
contract regardless of where the host fetches them. Resolve reuse, selective
evaluation, ambient binding, and stack-depth policy can still vary by the
per-host engine profile in <doc:Hosts-And-Platforms>.

Host-managed presentation surfaces that consume semantics receive
``SemanticHostFrame`` values. A semantic host frame is the atomic handoff for
one committed frame. Producer sequence, raster output, the semantic snapshot,
focused identity, and optional raster damage travel together. Thus, hosts do
not combine data from different commits. ``SemanticHostFrameCapabilities``
declares the host-frame side effects that the bridge supports, including
imperative accessibility announcements.

Terminal-backed hosts usually implement the aggregate ``PresentationSurface``.
Non-terminal hosts can instead compose narrower roles, such as
``PresentationSurfaceMetricsProvider`` plus semantic or raster presentation.
These hosts do not need terminal raw-mode or byte-writing methods.

## See Also

- <doc:Hosts-And-Platforms>
- <doc:Running-Apps>
- <doc:Architecture>
- <doc:Runtime-Render-Pipeline>
- <doc:Runtime>
- <doc:Vision>
