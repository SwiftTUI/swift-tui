# Public Products Draft

**Status:** Implemented as the May 2026 public product contract.
**Owner:** SwiftTUI maintainers.
**Related docs:** [HOST_PACKAGES.md](../HOST_PACKAGES.md),
[PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md),
[ARGUMENT_PARSING.md](ARGUMENT_PARSING.md),
[EMBEDDED_WEB_HOST.md](EMBEDDED_WEB_HOST.md),
[ADR-0008](../decisions/0008-swifttui-library-only-runners-own-main.md),
[ADR-0017](../decisions/0017-terminal-convenience-product-over-runtime.md),
[ADR-0016](../decisions/0016-platform-products-live-in-root-package.md).

## Summary

The release-facing package surface should have two layers:

1. **A convenience application layer** where ordinary terminal TUI authors add
   the `SwiftTUI` product and write only `import SwiftTUI`. That import gives
   them the authoring surface, terminal runner, standard argument parsing, and
   default terminal launch behavior. It does not include WebHost, charts, GIF
   animation, SwiftUI hosting, WASI hosting, or terminal-emulator embedding.
2. **A composed host layer** where each platform host is shaped the same way:
   import the platform-neutral SwiftTUI core, import the host product you want,
   then explicitly run or retain the app through that host. This layer is for
   SwiftUI apps, web-only apps, WASI apps, custom launchers, and any consumer
   that wants exact dependency control.

This deliberately revises the release ergonomics decision from ADR-0008. The
old two-import terminal app shape optimized for internal host purity:

```swift
import SwiftTUI
import SwiftTUICLI
```

The implemented release shape makes terminal apps feel like a single framework
while still preserving the no-extra-dependencies property for consumers who
choose a host product directly.

## Implementation Resolution

- Public core name: `SwiftTUIRuntime`.
- Terminal convenience product: `SwiftTUI`, a thin re-export of
  `SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI`.
- Terminal host product below the convenience layer: `SwiftTUICLI`.
- WebHost enablement: Option A. `SwiftTUIWebHostCLI` is the import replacement
  for binaries that intentionally support terminal and `--web` launch.
- `SwiftTUIWebHostCLI` re-exports `SwiftTUIRuntime`, `SwiftTUIArguments`, and
  `SwiftTUIWebHost`, and it calls `TerminalRunner` internally. It does not
  depend on the `SwiftTUI` convenience product, which avoids competing default
  `App.main()` providers while preserving the same authoring surface.

## Goals

- A regular terminal TUI app should need one source import: `import SwiftTUI`.
- Standard SwiftTUI argument parsing should be available by default. Consumers
  should not need a separate `import SwiftTUIArguments` for framework options,
  completion helpers, or app-specific `SwiftTUICommand` conformance.
- WebHost remains disabled by default and absent from default terminal app
  binaries: no FlyingFox, no WebSocket server, no browser bundle resources, no
  WebHost runner symbols.
- Enabling WebHost should be trivial. The preferred user story is no additional
  source import. The practical release fallback is a single import replacement
  or explicit launcher product that is easy to document and hard to misuse.
- Charts and animated images remain first-class domain products, not part of
  the default `SwiftTUI` convenience import.
- Platform-specific convenience imports may exist only when their packaging is
  unambiguous and does not smuggle unrelated host dependencies into the binary.
- The layer beneath `SwiftTUI` stays composable. A website-only consumer does
  not get terminal dependencies. A SwiftUI app does not get terminal
  dependencies. A terminal host is structured like every other host when the
  consumer does not choose the `SwiftTUI` convenience product.
- There is one platform-agnostic library import for shared SwiftTUI code:
  `SwiftTUIRuntime`.
- Availability annotations should make unsupported host/platform combinations
  fail clearly at compile time where Swift can express that.

## Non-Goals

- Do not merge charts or animated image playback into `SwiftTUI`.
- Do not make WebHost a weakly linked or runtime-discovered feature inside the
  default terminal product.
- Do not require the SwiftUI host, WASI host, WebHost, or terminal embedding
  products to import the terminal convenience product.
- Do not preserve every current product name if a name now communicates the
  wrong dependency shape.

## Product Roles

### Convenience Product

`SwiftTUI` is the release-facing terminal application product:

| Product | Intended import | Responsibility | Must not include |
|---|---|---|---|
| `SwiftTUI` | `import SwiftTUI` | SwiftUI-shaped authoring, platform-neutral runtime, terminal runner, standard argument parsing, default terminal `App.main()` | WebHost, FlyingFox, browser resources, SwiftUI host, WASI runner, charts, GIF animation, terminal-emulator embedding |

For ordinary apps:

```swift
import SwiftTUI

@main
struct NotesApp: App {
  var body: some Scene {
    WindowGroup {
      NotesView()
    }
  }
}
```

This should parse framework options and environment by default. App-specific
flags remain opt-in through `SwiftTUICommand`, but that protocol is available
from the same import:

```swift
import SwiftTUI

@main
struct NotesApp: App, SwiftTUICommand {
  @OptionGroup var swiftTUIOptions: SwiftTUIOptions
  @Option var notebook: String = "default"

  var body: some Scene {
    WindowGroup {
      NotesView(notebook: notebook)
    }
  }
}
```

The default `App.main()` path should parse framework-owned flags such as
accessibility, color, diagnostics, render mode, and WebHost request flags. If a
terminal-only binary receives `--web`, it should fail before raw mode with an
actionable message explaining the WebHost-enabled product path.

### Platform-Neutral Core

The implementation uses `SwiftTUIRuntime` as the public platform-neutral
import. The existing low-level `SwiftTUICore` target remains pipeline
infrastructure and is re-exported through `SwiftTUIRuntime`.

`SwiftTUIRuntime` should be enough for code that is not choosing a host:

```swift
import SwiftTUIRuntime

struct SharedDashboard: View {
  var body: some View {
    VStack {
      Text("Builds")
      ProgressView(value: 0.7)
    }
  }
}
```

It should own the platform-neutral pieces that every host needs:

- `View`, `Scene`, `App`, builders, controls, layout, gestures, focus, state,
  environment, presentation declarations, and navigation destinations.
- `DefaultRenderer`, frame artifacts, semantic output, raster output, and
  hosted scene sessions.
- `RuntimeConfiguration` and host-neutral configuration models, including a
  WebHost request value that can exist without linking an HTTP server.
- Platform-neutral image support already considered part of the base authoring
  surface, such as PNG and baseline JPEG decoding.

It should not own:

- terminal raw mode, signal handling, sockets, PTYs, stdout presentation, or
  crash guards;
- HTTP/WebSocket serving or browser resources;
- SwiftUI/AppKit/UIKit host views;
- WASI process launch;
- terminal-emulator child-process embedding;
- charts or animated image/GIF playback.

### Host Products

Host products should all depend on the platform-neutral core and expose their
own host policy. They should not depend on the terminal convenience product.

| Product | Import | Shape |
|---|---|---|
| `SwiftTUICLI` | `import SwiftTUIRuntime` + `import SwiftTUICLI` | Explicit terminal launch or retained terminal host. Same structural role as SwiftUI/WebHost/WASI when bypassing the `SwiftTUI` convenience product. |
| `SwiftUIHost` or future `SwiftTUISwiftUI` | `import SwiftTUIRuntime` + `import SwiftUIHost` | Native SwiftUI app embedding. No terminal dependencies. |
| `SwiftTUIWASI` | `import SwiftTUIRuntime` + `import SwiftTUIWASI` | WASI launch and manifest behavior. No POSIX terminal runner. |
| `SwiftTUIWebHost` | `import SwiftTUIRuntime` + `import SwiftTUIWebHost` | Localhost browser host only. No terminal runner required. |
| `WASISurfaceBridge` | `import WASISurfaceBridge` | Pure `web-surface` transport support. No terminal dependencies. |
| `SwiftTUITerminal` | `import SwiftTUIRuntime` + `import SwiftTUITerminal` | Terminal-emulator and child-process embedding. Domain-specific, not part of regular app convenience. |

The important rule is symmetry: once a consumer does not import the `SwiftTUI`
convenience product, terminal execution is just another host choice. It should
not have a privileged import pattern that the SwiftUI host, WebHost, and WASI
host do not share.

## Proposed Package Graph

The exact target names can change, but the dependency direction should not:

```text
SwiftTUIRuntime
  -> platform-neutral dependencies only

SwiftTUIArguments
  -> SwiftTUIRuntime
  -> swift-argument-parser

SwiftTUICLI
  -> SwiftTUIRuntime
  -> SwiftTUIArguments
  -> terminal runtime deps only

SwiftTUI
  -> SwiftTUIRuntime
  -> SwiftTUIArguments
  -> SwiftTUICLI

SwiftTUIWebHost
  -> SwiftTUIRuntime
  -> WASISurfaceBridge
  -> FlyingFox + browser resources

SwiftTUIWebHostCLI
  -> SwiftTUIRuntime
  -> SwiftTUIArguments
  -> SwiftTUICLI
  -> SwiftTUIWebHost

SwiftUIHost
  -> SwiftTUIRuntime
  -> SwiftUI platform APIs

SwiftTUIWASI
  -> SwiftTUIRuntime
  -> WASISurfaceBridge

SwiftTUICharts
  -> SwiftTUICore
  -> SwiftTUIViews

SwiftTUIAnimatedImage
  -> SwiftTUICore
  -> SwiftTUIViews
  -> GIF codec
```

Boundary tests should assert this graph directly. In particular:

- `SwiftTUI` must not depend on `SwiftTUIWebHost`, FlyingFox, or WebHost
  browser resources.
- `SwiftUIHost` must not depend on terminal runner products, Unix signals,
  PTYs, or SwiftTerm.
- `SwiftTUIWebHost` must not depend on terminal runner products unless the
  consumer chooses the combined CLI product.
- `SwiftTUICharts` and `SwiftTUIAnimatedImage` must not be re-exported by
  `SwiftTUI`.

## Resolved Mismatches

The implementation closes the original release-shape mismatches:

- `SwiftTUIRuntime` now owns the host-neutral authoring/runtime import, and
  `SwiftTUI` is the terminal app convenience product.
- `SwiftTUIArguments` depends on `SwiftTUIRuntime`; `SwiftTUI` re-exports
  argument parsing instead of sitting below it.
- `SwiftTUICLI` remains the lower-level terminal runner product, while
  `import SwiftTUI` makes the default terminal `App.main()` visible for normal
  apps.
- `SwiftUIHost`, `SwiftTUIWASI`, `WASISurfaceBridge`, `SwiftTUIWebHost`, and
  `SwiftTUITerminal` depend on `SwiftTUIRuntime` instead of the terminal
  convenience product.
- The WebHost compile-time boundary is preserved. `SwiftTUIWebHostCLI` is the
  explicit combined product for binaries that intentionally support `--web`.

## WebHost Enablement

There are three possible enablement shapes.

### Option A: One Import Replacement

The consumer changes the product dependency and replaces:

```swift
import SwiftTUI
```

with:

```swift
import SwiftTUIWebHostCLI
```

`SwiftTUIWebHostCLI` re-exports `SwiftTUIRuntime`, `SwiftTUIArguments`, and
`SwiftTUIWebHost`; it uses `TerminalRunner` internally for normal launches.
Its default launch path routes `--web` to `WebHostRunner` and normal launches
to the terminal runner.

This is closest to the current implementation and preserves compile-time
isolation. It is not the ideal "no import change" story, but it is simple,
auditable, and fits SwiftPM.

### Option B: Explicit Launcher

The source keeps `import SwiftTUI`, adds a WebHost product dependency, and owns
an explicit main:

```swift
import SwiftTUI
import SwiftTUIWebHostCLI

@main
enum Main {
  static func main() async throws {
    try await WebHostCLIRunner.run(NotesApp.self)
  }
}
```

This is best for apps that need custom startup, but it is not the ergonomic
default.

### Option C: No Source Import Change

The consumer changes only package configuration and keeps:

```swift
import SwiftTUI
```

This is the preferred user story, but SwiftPM does not make it easy to do
honestly. A module cannot gain a different default `App.main()` implementation
just because another product was linked, and default-WebHost behavior cannot
live in `SwiftTUI` without also linking WebHost into the default binary.

Do not adopt fragile runtime registration, weak linking, dynamic symbol lookup,
or module side effects to simulate this. Option C is acceptable only if the
implementation can satisfy all of these:

- default `SwiftTUI` binaries still contain no WebHost dependencies or
  resources;
- adding the WebHost-enabled product makes the default launch path visible to
  Swift's type checker without relying on an unimported module extension;
- package graph tests can prove terminal-only, WebHost-only, and combined
  binaries are distinct.

Until that mechanism exists, Option A is the release behavior.

## Convenience Imports For Other Platforms

Other platforms may get convenience imports when the dependency story is
unambiguous:

- A native Apple convenience product may be reasonable if it re-exports only
  `SwiftTUIRuntime` and `SwiftUIHost`, is unavailable off Apple platforms, and
  does not import terminal or WebHost code.
- A WASI convenience product may be reasonable if it owns only WASI launch and
  `web-surface` transport.
- A WebHost-only convenience product may be reasonable for local-browser apps
  that never paint a terminal.

Do not create a convenience product just to reduce import count if the product
name hides major dependencies. The convenience layer exists to clarify common
packaging choices, not to collapse every host into an umbrella.

## Availability Policy

Use `@available` to make unsupported usage clear:

- Terminal runner and PTY APIs should be unavailable on platforms where they
  cannot work, with messages pointing to `SwiftUIHost`, `SwiftTUIWASI`, or
  `SwiftTUIRuntime` as appropriate.
- SwiftUI host APIs should carry Apple-platform availability and remain absent
  from Linux builds where the product is not emitted.
- WebHost APIs should express supported server platforms. Binding and browser
  opening behavior can still be runtime policy, but the product should fail
  clearly where the server stack cannot compile.
- Platform-neutral `SwiftTUIRuntime` should avoid unnecessary availability
  restrictions. Host-specific unavailability belongs in host products.

Availability annotations are not a dependency-management tool. They help call
sites, but package graph boundaries still need product splits and tests.

## Implemented Migration

1. **Inventory the current graph.** Captured the public products, target
   dependencies, imported modules, and resource edges in one package graph
   test and extended `Scripts/check_webhost_package_boundary.sh`.
2. **Extract the public platform-neutral core.** Selected `SwiftTUIRuntime` and
   moved host-neutral authoring, `App`/`Scene`, hosted sessions, rendering, and
   configuration into that import.
3. **Rebuild `SwiftTUI` as the terminal convenience product.** Re-exported the
   platform-neutral core, argument parsing, and terminal runner. Standard
   argument parsing is part of the default terminal launch path.
4. **Make terminal host composition explicit below the convenience layer.** Kept
   `SwiftTUICLI` so it behaves like `SwiftUIHost`,
   `SwiftTUIWebHost`, and `SwiftTUIWASI` when the consumer imports core plus a
   host product directly.
5. **Keep domain utilities explicit.** Kept charts, animated image/GIF, and
   terminal-emulator embedding have first-class docs and examples but are not
   re-exported from `SwiftTUI`.
6. **Update docs and examples.** README examples now show one-import terminal
   apps first, then composed host recipes. `HOST_PACKAGES.md`,
   `PUBLIC_SURFACE_POLICY.md`, and `SOURCE_LAYOUT.md` describe the implemented
   product graph.
7. **Add compatibility shims cautiously.** No compatibility shim was added; the
   old runtime target name became `SwiftTUIRuntime`, and `SwiftTUI` is now the
   convenience import.

## Success Criteria

- A new terminal app can depend on the `SwiftTUI` product, write only
  `import SwiftTUI`, and run with standard framework flags.
- A terminal-only `SwiftTUI` binary links no WebHost server, FlyingFox,
  WebSocket adapter, or browser resources.
- A WebHost-only app can depend on `SwiftTUIRuntime` and `SwiftTUIWebHost` without
  terminal runner, PTY, Unix signal, or terminal socket dependencies.
- A native SwiftUI app can depend on `SwiftTUIRuntime` and `SwiftUIHost` without
  terminal dependencies.
- A platform-agnostic shared view package imports one core module and no host.
- Charts and animated image consumers add explicit products and imports.
- The docs teach common users the convenience import first and teach advanced
  users the composed graph before they need it.

## Resolved Decisions And Follow-Ups

- Public core name: `SwiftTUIRuntime`.
- Terminal host product name below the convenience layer: `SwiftTUICLI`.
- WebHost enablement: Option A for release.
- Whether terminal-emulator embedding should be grouped with domain utilities
  in public docs, or kept under platform integration docs.
- Whether the convenience `SwiftTUI` product should be unavailable on iOS or
  present but terminal-runner APIs unavailable. Prefer the former if the product
  truly means terminal app convenience.

## Rejected Directions

- **Keep the current two-import terminal story as the public default.** It is
  internally clean, but it makes the most common consumer path feel unfinished.
- **Move WebHost into `SwiftTUI`.** This satisfies `--web` ergonomics but
  violates the no-extra-binaries goal.
- **Use weak linking or runtime discovery for WebHost.** That hides important
  packaging behavior and makes boundary tests less meaningful.
- **Make every host re-export every other host.** That optimizes import count
  by destroying the dependency story.
- **Rename charts or GIF as "extras" hidden under `SwiftTUI`.** They are useful
  enough to be first-class products and specific enough to stay explicit.
