# Platforms/Web Consumable Package Learnings

**Status:** Investigation draft. This is not an approved implementation plan.
It captures the current limitations of `Platforms/Web` as an external consumer
surface and sketches package-shape options such as `@swifttui/web` and
`@swifttui/build`.

**Owner:** unassigned.

**Related docs:** [LOCAL_BROWSER_HOST_LEARNINGS.md](LOCAL_BROWSER_HOST_LEARNINGS.md),
[EMBEDDED_WEB_HOST.md](EMBEDDED_WEB_HOST.md),
[HOST_PACKAGES.md](../HOST_PACKAGES.md),
[TOOLCHAINS.md](../TOOLCHAINS.md),
[../Examples/WebExample/README.md](../../Examples/WebExample/README.md).

## Scope

This document is about the deploy-to-browser shape:

```text
SwiftTUI app -> Swift WASI build -> static app.wasm + manifest -> browser host
```

It is not about a native binary serving a localhost browser view. That separate
local-browser track is covered in
[LOCAL_BROWSER_HOST_LEARNINGS.md](LOCAL_BROWSER_HOST_LEARNINGS.md).

The question here is whether an external repo can consume the browser host as a
normal web-project dependency, and what would need to change before
`Platforms/Web` is more than repo-maintainer infrastructure.

## Current SwiftTUI Shape

The current browser-deploy path has three parts:

- A Swift executable imports `SwiftTUIWASI`.
- `WASIRunner` prints a scene manifest in `TUIGUI_MODE=manifest`, and executes
  one selected scene when compiled for WASI.
- `Platforms/Web` builds the Swift package to `.wasm`, packages
  `scene-manifest.json` and `assets/app.wasm`, and bundles a browser runtime
  that draws `web-surface` frames into a canvas with ARIA side output.

The path is functional. A throwaway external SwiftPM package was able to build
through:

```bash
bun run --cwd Platforms/Web build \
  -- --package-path /tmp/external-app \
     --app ExternalWebApp \
     --dist /tmp/external-app/web-dist
```

The resulting output contained:

- `index.html`
- `scene-manifest.json`
- bundled JavaScript
- `assets/app.wasm`

That proves external packages can be targeted. It does not prove the system is
a good external product yet.

## Current Consumer Problems

### The Package Is Private

`Platforms/Web/package.json` declares `"private": true` and exposes raw
`index.ts`. `Examples/WebExample` says to `bun add webhost`, but `webhost` is
currently a repo workspace package, not a published dependency an outside repo
can add from npm.

### Runtime And Build Code Share One Export

`Platforms/Web/index.ts` exports browser runtime APIs and build helpers from
the same module. It also imports Node APIs and uses Bun APIs in the same
entrypoint that browser consumers import from.

That is a development artifact. A browser runtime package should not pull in
build-time concerns, and a build package should not require browser runtime
types to be loaded by default.

### Bun Is Both Package Manager And Runtime Assumption

The current scripts use:

- `bun run`
- `Bun.spawn`
- `Bun.file`
- `Bun.write`
- `Bun.serve`
- `bun build`
- `bun test`

That is fine for this repo, but it makes "use SwiftTUI from a Vite/npm/pnpm
web project" harder than necessary. It also means the system is not currently
package-manager-agnostic.

### Swift Toolchain Assumptions Are Hard-Coded

The WASI build helper currently hard-codes:

- `swift-6.3.1-RELEASE_wasm`
- `swiftly run swift` when `swiftly` is available
- release flags including `-Osize` and disabling LLVM merge functions
- fixed initial memory, max memory, and stack size

Those defaults are useful. They should remain the recommended defaults. But an
external build tool needs explicit override points for the Swift executable,
SDK ID, configuration, memory, stack size, extra Swift flags, and extra linker
flags.

### Manifest Generation Runs The App Natively

The manifest step runs the executable natively with `TUIGUI_MODE=manifest`.
That means the consumer package must be valid for the native host platform
before the WASI build even starts. In the external smoke, a package without an
explicit platform floor failed because its executable defaulted below
SwiftTUI's `macOS(.v15)` requirement.

This should be documented and probably improved. Possible improvements include:

- clearer error text around native manifest generation
- a manifest-only helper target pattern
- a SwiftPM plugin that can surface the platform requirement early
- future manifest extraction that does not require launching the final
  executable natively

### WebExample Contains Load-Bearing Glue

`Examples/WebExample` documents `createWebHostApp` plus
`createWasmSceneRuntimeFactory` as the adoption pattern. But
`createWasmSceneRuntimeFactory` lives in the example, not in the reusable web
package. External users currently have to copy too much example code.

If this is a public product, the WASI runtime factory and worker glue should be
owned by the web runtime package or by a documented adapter package.

## Proposed Package Split

This investigation points toward two JavaScript packages plus one optional
Swift-facing tool path.

### `@swifttui/web`

Browser runtime only.

Responsibilities:

- load and validate `scene-manifest.json`
- expose `createWebHostApp`
- expose the canvas scene runtime
- expose WebSocket and WASI scene bridge factories
- expose style and theme types
- expose CSS or a documented style contract
- mount accessibility trees and announcements as browser ARIA
- provide generated `.d.ts` files and ESM browser builds

Must not:

- spawn Swift
- depend on Bun globals
- import Node-only modules from its public browser entrypoint
- know about repo paths
- assume a package manager

Possible exports:

```text
@swifttui/web
@swifttui/web/style.css
@swifttui/web/wasi
@swifttui/web/websocket
@swifttui/web/testing
```

The current `Platforms/Web` browser runtime is close to this, but it needs a
clean package boundary and compiled artifacts.

### `@swifttui/build`

Build-time package and CLI.

Responsibilities:

- generate `scene-manifest.json`
- build the Swift executable for WASI
- validate `app.wasm` with `WebAssembly.compile`
- optionally optimize or strip wasm
- copy or emit a minimal static web shell
- expose a CLI such as `swifttui-web build`
- work with npm, pnpm, Yarn, and Bun

Must not:

- export browser runtime APIs from the default entrypoint
- require Bun to execute
- assume the package is inside the SwiftTUI monorepo
- hide the Swift command, SDK, or linker flags from callers

Possible CLI:

```bash
npx swifttui-web build \
  --package-path . \
  --product MyApp \
  --dist dist \
  --swift-sdk swift-6.3.1-RELEASE_wasm
```

Possible programmatic API:

```ts
import { buildSwiftTUIWebApp } from "@swifttui/build";

await buildSwiftTUIWebApp({
  packagePath: ".",
  product: "MyApp",
  dist: "dist",
});
```

### SwiftPM Tool Or Plugin

For Swift-only projects, JavaScript package consumption may still be too much.
The Swift-facing path could be:

```bash
swift package plugin swift-tui-web-build \
  --product MyApp \
  --dist dist
```

or:

```bash
swift run swift-tui-web build --product MyApp --dist dist
```

This tool could shell out to `swift build --swift-sdk ...` and either vendor a
minimal browser shell or call the JavaScript build package. The important
consumer promise is that a Swift app author can produce a static browser build
without adopting the SwiftTUI repo's Bun workspace.

## Learnings From Comparable Projects

### JavaScriptKit

[`JavaScriptKit`](https://github.com/swiftwasm/JavaScriptKit) is the current
SwiftWasm direction to study. Its package-to-JS plugin emits JavaScript entry
points that web bundlers can consume, and its deployment docs show a normal
npm/Vite deployment path.

The lesson is to meet web projects where they are:

- generate JS artifacts from SwiftPM
- let Vite or another bundler own web optimization
- keep the Swift build step explicit
- support normal npm workflows

SwiftTUI should not copy JavaScriptKit's exact runtime model, because SwiftTUI
uses `web-surface` and a canvas/ARIA host. But the packaging workflow is the
right reference.

### Carton

[`carton`](https://github.com/swiftwasm/carton) is a historical ergonomics
reference. Its value was not just that it built WASM; it made Swift web work
feel like a single command for dev and bundle workflows.

The lesson for SwiftTUI is to provide one obvious command for:

- build manifest
- build wasm
- bundle browser runtime
- serve locally with the required headers

Even if the implementation uses a modern package-to-JS or npm package path, the
developer workflow should feel similarly direct.

### xterm.js

[`xterm.js`](https://github.com/xtermjs/xterm.js) shows how a browser terminal
component is packaged for broad reuse:

- public package
- typed ESM imports
- CSS entrypoint
- optional addons
- backend-agnostic frontend component

SwiftTUI's browser renderer is not a terminal emulator, but it should aspire to
the same packaging clarity. The browser package should be a stable component,
not a repo-internal example dependency.

### Textual Serve

`textual-serve` is a local-browser reference, not a static web reference. The
lesson here is separation: Textual's web-serving mode does not make every
Textual app a static web project. SwiftTUI should keep the local WebHost and
the static WASI web host distinct, even if they share renderer code.

## Proposed Phasing

### Phase 0: Document The Current Contract

- Add a clear external-browser-build guide that does not imply `webhost` is
  already a published package.
- Document the native manifest-generation requirement.
- Document required COOP/COEP headers and why `SharedArrayBuffer` is needed.
- Add a minimal external smoke fixture that builds a package outside this repo.

### Phase 1: Split Runtime And Build Entrypoints Internally

- Move build helpers behind a separate internal entrypoint.
- Keep browser runtime imports free of Node and Bun APIs.
- Move the WebExample WASI runtime factory into reusable package code or a
  documented adapter module.
- Add tests that fail if browser runtime entrypoints import build modules.

### Phase 2: Make Build Tooling Node-Compatible

- Replace Bun-only build helpers with Node-compatible APIs where practical.
- Keep Bun scripts as repo convenience wrappers.
- Add npm/pnpm/Vite fixture coverage.
- Expose options for Swift executable, Swift SDK ID, release flags, memory, and
  output layout.

### Phase 3: Publish JavaScript Packages

- Publish `@swifttui/web` and `@swifttui/build` or equivalent names.
- Ship compiled JS, source maps, CSS, and `.d.ts`.
- Decide package versioning relative to the Swift package version.
- Add release checks that build the packages from clean installs.

### Phase 4: Add A Swift-Facing Build Tool

- Add a SwiftPM plugin or executable that wraps the build flow.
- Decide whether it shells out to Node package tooling, vendors the browser
  runtime, or both.
- Make the Swift-only quickstart explicit and tested.

## Open Questions

- Should `@swifttui/web` include the WASI worker and shared-stdin queue, or
  should those live in `@swifttui/web/wasi` as a subpath?
- Should `@swifttui/build` generate a full static app, or only produce
  `app.wasm` and `scene-manifest.json` for a host framework to consume?
- Should the SwiftPM plugin depend on Node, or should it be capable of a
  minimal no-Node static shell?
- How should package versions align across SwiftPM and npm?
- Is Bun still the repo's preferred maintainer tool after Node-compatible
  build helpers exist?
- Should manifest generation keep running the executable natively, or should a
  pure SwiftPM plugin path extract manifests another way?
- What is the minimum supported browser baseline for `SharedArrayBuffer`,
  canvas, clipboard writes, and ARIA mounting?
- Should the public web runtime expose lower-level canvas/render primitives, or
  only the app-level `createWebHostApp` API?

## Non-Goals For This Investigation Draft

- No npm package name is reserved by this document.
- No implementation is approved by this document.
- No replacement for `SwiftTUIWebHostCLI` is proposed here.
- No promise is made that Bun will be removed from repo-local development.
- No browser visual redesign is proposed here.
