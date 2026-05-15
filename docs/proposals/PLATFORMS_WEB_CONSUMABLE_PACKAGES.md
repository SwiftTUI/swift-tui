# Platforms/Web Consumable Package Learnings

**Status:** Implemented internally. `Platforms/Web` is now the browser-runtime
workspace package `@swifttui/web`, while `Platforms/WebBuild` is the build-time
workspace package `@swifttui/build`. npm publishing, compiled release
artifacts, and SwiftPM plugin wrapping remain release-engineering work, not
active TODOs.

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

## Decision

Split `Platforms/Web` before publishing or documenting it as a general external
package. The old repo-private `webhost` workspace package has been replaced by
the split runtime/build workspaces.

The target public shape is:

- a browser-runtime package, `@swifttui/web`, with browser-safe entrypoints,
  style assets, scene manifest loading, canvas/ARIA hosting, WebSocket scene
  bridges, and WASI scene bridge support;
- a build-time package, `@swifttui/build`, with the manifest, WASI build, wasm
  validation, packaging APIs, and CLI/programmatic build APIs; and
- a later Swift-facing build wrapper or SwiftPM plugin for Swift-only projects,
  after the runtime/build package boundary is stable.

Do not publish the pre-split `webhost` package shape. It mixed browser runtime
exports with Bun/Node build code, exposed raw TypeScript sources, assumed the
repo workspace, and left load-bearing WASI worker glue in `Examples/WebExample`.

This decision keeps static browser deployment separate from the native
localhost-browser `SwiftTUIWebHost` / `SwiftTUIWebHostCLI` path. They may share
renderer code and wire formats, but they should remain separate consumer
stories.

## Current SwiftTUI Shape

The current browser-deploy path has four parts:

- A Swift executable imports `SwiftTUIWASI`.
- `WASIRunner` prints a scene manifest in `TUIGUI_MODE=manifest`, and executes
  one selected scene when compiled for WASI.
- `Platforms/WebBuild` builds the Swift package to `.wasm`, packages
  `scene-manifest.json` and `assets/app.wasm`, and validates the wasm through
  the browser `WebAssembly.compile` API.
- `Platforms/Web` bundles the browser runtime that draws `web-surface` frames
  into a canvas with ARIA side output.

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

### Package Boundary

`Platforms/Web/package.json` now declares `@swifttui/web` and exports runtime
subpaths. `Platforms/WebBuild/package.json` declares `@swifttui/build` and owns
build helpers. These packages are workspace-consumable today; npm publishing and
compiled release artifacts are still future release work.

### Runtime And Build Code Are Split

`Platforms/Web/index.ts` exports browser runtime APIs only. Build helpers moved
to `@swifttui/build`, and a package-boundary test keeps public runtime
entrypoints from importing `@swifttui/build` or `node:` modules.

### Bun Is Both Package Manager And Runtime Assumption

The current scripts use:

- `bun run`
- `Bun.spawn`
- `Bun.file`
- `Bun.write`
- `Bun.serve`
- `bun build`
- `bun test`

Repo-local scripts still use Bun. The build package core no longer uses Bun
globals for process spawning, file IO, PATH lookup, or wasm validation, but the
release artifact pipeline for npm/pnpm/Yarn consumers remains future work.

### Swift Toolchain Assumptions Are Hard-Coded

The WASI build helper currently hard-codes:

- `swift-6.3.1-RELEASE_wasm`
- `swiftly run swift` when `swiftly` is available
- release flags including `-Osize` and disabling LLVM merge functions
- fixed initial memory, max memory, and stack size

Those defaults remain the recommended defaults. `@swifttui/build` now exposes
override points for the Swift command, SDK ID, configuration, memory, stack
size, extra Swift compiler flags, extra linker flags, and extra Swift build
arguments.

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

The reusable WASI runtime factory, shared input queue, and worker implementation
now live under `@swifttui/web/wasi` and `@swifttui/web/wasi-worker`. The example
keeps only its app-specific frontend shell and thin worker entrypoint.

## Accepted Package Split

The implemented internal direction is two JavaScript workspace packages plus one
optional future Swift-facing tool path.

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
@swifttui/web/manifest
@swifttui/web/style.css
@swifttui/web/wasi
@swifttui/web/wasi-worker
@swifttui/web/websocket
@swifttui/web/testing
```

The current `Platforms/Web` browser runtime has the clean package boundary.
Compiled npm artifacts remain release work.

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

## Implementation Phasing Status

These phases record the order of work. Remaining release work should get scoped
plans before it is added to `TODO.md`.

### Phase 0: Document The Current Contract

- [x] Add docs that no longer imply `webhost` is a published package.
- [x] Document the native manifest-generation requirement.
- [x] Document required COOP/COEP headers and why `SharedArrayBuffer` is needed.
- [ ] Add a minimal external smoke fixture that builds a package outside this
  repo.

### Phase 1: Split Runtime And Build Entrypoints Internally

- [x] Move build helpers into `@swifttui/build`.
- [x] Keep browser runtime imports free of Node and Bun build APIs.
- [x] Move the WebExample WASI runtime factory into `@swifttui/web/wasi`.
- [x] Add tests that fail if browser runtime entrypoints import build modules.

### Phase 2: Make Build Tooling Node-Compatible

- [x] Replace Bun-only build helper internals with Node-compatible APIs where
  practical.
- [x] Keep Bun scripts as repo convenience wrappers.
- [ ] Add npm/pnpm/Vite fixture coverage.
- [x] Expose options for Swift executable, Swift SDK ID, release flags, memory,
  and output layout.

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

## Implementation Questions For Future Plans

These questions should be resolved inside future scoped implementation plans,
not by reopening this broad investigation.

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

## Non-Goals

- No npm package name is reserved by this document.
- No immediate implementation tranche is opened by this document.
- No replacement for `SwiftTUIWebHostCLI` is proposed here.
- No promise is made that Bun will be removed from repo-local development.
- No browser visual redesign is proposed here.
