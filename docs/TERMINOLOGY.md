# Terminology

This page pins the external vocabulary for SwiftTUI platform integration.
Internal types may still use `Host` in their concrete names, but public docs
should use these terms consistently.

## Product Layers

- `SwiftTUI`: release-facing terminal app convenience product. It re-exports
  `SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI` so ordinary
  terminal apps can write only `import SwiftTUI`.
- `SwiftTUIRuntime`: platform-neutral authored-view/runtime composition
  product used by explicit runner and host products.

## Runner

A runner owns process startup for an authored `App`.

Use **runner** when the product or type owns top-level execution, default
`App.main()` behavior, launch routing, argv/env parsing, raw-mode setup, crash
guards, scene discovery, or explicit entry points such as `TerminalRunner.run`.

Current runner products:

- `SwiftTUICLI`: terminal-native executable launch through `TerminalRunner`.
- `SwiftTUIWASI`: WASI executable launch and manifest output through
  `WASIRunner`.
- `SwiftTUIWebHost`: web-only localhost-browser launch
  through `WebHostRunner`.
- `SwiftTUIWebHostCLI`: combined terminal/WebHost launch routing through
  `WebHostCLIRunner`.

## Host

A host owns an external presentation environment or embedding lifecycle for a
SwiftTUI scene.

Use **host** when the product or shell owns a platform surface, window or
browser lifecycle, size and style delivery, native input, clipboard bridging,
accessibility bridging, scene-switching chrome, or retained
`HostedSceneSession` values inside another app/runtime.

Current host products and packages:

- `SwiftUIHost`: embeds SwiftTUI scenes in a native SwiftUI app shell.
- `Platforms/Web`: Bun package that embeds SwiftTUI WASI scenes in a browser
  canvas.

`SwiftTUIWebHost` is intentionally compound: it provides a runner that starts a
localhost server and a browser host that presents the running scene. When
writing about it, say **WebHost runner**, **WebHost CLI runner**,
**localhost WebHost bridge**, or **browser host** depending on which side is in
scope.

## Presentation Surface

A presentation surface is the low-level frame sink used by `RunLoop`.

Use **presentation surface** for `PresentationSurface` implementations such as
`TerminalHost`, `HostedRasterSurface`, `WebSurfaceTransport`, and
`WebSocketSurfaceTransport`. A presentation surface may be created by a runner
or retained by a host, but it is not itself a product-level runner or host.

Use `SemanticHostFrame` for the single value handed to non-terminal
surfaces that consume raster output together with semantic snapshot data and
raster damage hints. Each semantic host frame also carries a producer sequence
so hosts can reason about stale asynchronous work without relying only on
callback order.

## Hosted Scene Session

A `HostedSceneSession` is a retained runtime session for one selected scene. It
lets host products keep scene state alive while the platform shell manages
visibility, size, style, input, and lifecycle. The session is the shared runtime
seam between SwiftTUI and hosts; it is not the host itself.

## Terminal-Program Embedding

`SwiftTUITerminal` lets authored SwiftTUI views embed external terminal
programs through `TerminalView` and related session types. Its sources live in
`Platforms/Embedding`, but it is not a runner product and it is not a host
product for SwiftTUI apps.

## Usage Rules

- Say **runner product** for products that own executable startup or launch
  routing.
- Say **host product** for products that retain SwiftTUI scenes inside another
  app/runtime lifecycle.
- Say **platform integration product** when discussing Swift runners and hosts
  together.
- Say **presentation surface** for `RunLoop` frame sinks and terminal/web/native
  transport implementations.
- Avoid using **host package** as a blanket term for all platform integration
  products.
- Avoid using **GUI host** in current docs; the checked-in packages now live
  under `Platforms/`.

## Adjacent Uses Of Host

These uses are valid but are not the package-integration meaning above. Do not
rewrite them unless the surrounding doc is specifically discussing runner/host
package boundaries.

- URL and HTTP host names, bind hosts, and allowed hosts.
- DocC or web static hosting.
- SwiftUI layout research terms such as "root host" or "hosting container".
- Internal view-tree container terms such as portal hosts or toolbar hosts.
- Concrete public type/product names such as `TerminalHost`, `HostedRasterSurface`,
  `SwiftUIHost*`, and `WebHost*`.
