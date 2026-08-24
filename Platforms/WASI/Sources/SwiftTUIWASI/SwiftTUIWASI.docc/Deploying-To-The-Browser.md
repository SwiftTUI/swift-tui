# Deploying to the Browser

Ship a SwiftTUI app to a web page: serve it from the binary with `--web`, or
compile a static WebAssembly bundle any web host can serve.

## Overview

The same authored `App` reaches a browser on two paths:

- **Localhost WebHost.** Any app built on the `SwiftTUI` convenience product
  already has it: launch with `--web` and the native process serves the app to
  a local browser tab. No extra targets, no packaging. Use it for development
  previews and local tools.
- **Static WASI bundle.** Compile the app itself to `wasm32-wasi` with this
  product, package it with the
  [`@swifttui/build`](https://github.com/SwiftTUI/swift-tui-web) tooling, and
  mount it with the [`@swifttui/web`](https://github.com/SwiftTUI/swift-tui-web)
  browser runtime. The result is a directory of static files — no server-side
  Swift. This is what the live demo at
  <https://swifttui.sh/webexample/> is.

The rest of this article covers the static path.

## Compile the App to WASI

Give the browser build its own executable target whose dependency closure
stays WASI-safe: your views (through `SwiftTUIRuntime` or `SwiftTUIViews`)
plus the `SwiftTUIWASI` product. Do not depend on the `SwiftTUI` umbrella
here — it reaches the localhost web-server stack, which does not build for
WASI.

The entry point passes the app type to ``WASIRunner``:

```swift
// main.swift
import SwiftTUIRuntime
import SwiftTUIWASI

struct MyBrowserApp: App {
  var body: some Scene {
    // The identifier is load-bearing: it becomes the scene id in
    // scene-manifest.json, which the browser runtime selects scenes by.
    WindowGroup("My App", id: WindowIdentifier("main")) {
      ContentView()
    }
  }
}

try await WASIRunner.run(MyBrowserApp.self)
```

Building for `wasm32-wasi` requires a Swift SDK for that triple matching your
toolchain (installable through `swift sdk install`; the build tooling below
reports the exact artifact it expects when the SDK is missing).

## Package and Mount

The JavaScript side ships as two npm packages from
[`swift-tui-web`](https://github.com/SwiftTUI/swift-tui-web):
`@swifttui/build` compiles and packages the wasm plus its scene manifest, and
`@swifttui/web` is the browser runtime that mounts it.

```bash
npm install @swifttui/web @swifttui/build
npx swifttui-web build --package-path . --app MyBrowserApp
```

```js
import { createWebHostApp } from "@swifttui/web";
import { createWasmSceneRuntimeFactory } from "@swifttui/web/wasi";

await createWebHostApp({
  mount: document.getElementById("app"),
  manifestUrl: new URL("./scene-manifest.json", import.meta.url),
  sceneRuntimeFactory: createWasmSceneRuntimeFactory(
    new URL("./assets/app.wasm", import.meta.url),
  ),
});
```

The runtime paints through a canvas or DOM engine and mounts an ARIA
accessibility tree alongside the rendered cells. Renderer selection, styling,
and the transport details are documented in the `@swifttui/web` package's own
README.

## Serve With the Required Headers

The WASI runtime uses `SharedArrayBuffer`-backed stdin, so the hosting page
must be served with cross-origin isolation headers. Without them the mount
stays blank:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

## Start From the Reference Template

[`swift-tui-counter-demo/WebExample`](https://github.com/SwiftTUI/swift-tui-counter-demo/tree/main/WebExample)
is the maintained embedding template — the exact source of the live demo,
including dev-server and production-build scripts and a checklist of what to
copy into your own site.

For the full host and platform matrix, including how the WASI presentation
compares to the localhost WebHost and the native hosts, see
[Hosts and Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms).
