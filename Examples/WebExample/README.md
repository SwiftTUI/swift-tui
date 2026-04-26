# WebExample

Minimal Bun web app that embeds a Swift `TerminalUI` executable through
[`GUI/WebTUIGUI`](/Users/adamz/Developer/repos/swift-terminal-ui/GUI/WebTUIGUI).

The example has two parts:

- `TerminalApp/`: a Swift package with a reusable `WebExampleScenes`
  library target plus a thin `WebExampleApp` executable launcher
- `src/`: the Bun host that builds the manifest and wasm assets, serves them, and mounts `WebTUIGUI`

The browser-hosted `WebExampleApp` runs the same component gallery used by the
SwiftUI demo, backed by the shared `GalleryDemoViews` target.

## Toolchains

- Swift
  - Use `swiftly` to run Swift 6.3.1
  - configure the Swift SDK `swift-6.3.1-RELEASE_wasm` for the Swift build
  - Use `-Xswiftc -Osize` plus `-Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass` for the wasm release build. Plain `-O`, and on some Darwin runners even plain `-Osize`, can emit merged outlined copy helpers whose signatures exceed the browser WebAssembly API's 1000-parameter limit and cause `WebAssembly.Module doesn't parse` startup failures.
  - The Swift Wasm build for a non-trivial TerminalUI program must configure the stack-size avoid runtime crashes. Stack and heap size may similarly require configuration.
  - An overkill example which does a required stack size bump, but also configures maximal upfront memory is:
    - `swiftly run swift build --swift-sdk swift-6.3.1-RELEASE_wasm -c release -Xswiftc -Osize -Xswiftc -Xfrontend -Xswiftc -disable-llvm-merge-functions-pass -Xlinker --initial-memory=536870912 -Xlinker --max-memory=4294967296 -Xlinker -z -Xlinker "stack-size=1048576"`
  - See build.sh and run.sh in TerminalUI
- Use Bun for the web app.
- (Bun is currently configured to build the Swift Wasm targets with overkill memory settings.)

## Setup

```bash
bun install
```

`WebExample` and `GUI/WebTUIGUI` now share the repo's Bun workspace, so running
`bun install` from the repo root is preferred. Running it from
`Examples/WebExample` also works and updates the root workspace lockfile.

## Development

```bash
bun dev
```

`bun dev` first builds `TerminalApp/dist/scene-manifest.json` and
`TerminalApp/dist/assets/app.wasm`, then starts the Bun server.

The dev server runs Bun's HTML-import bundler behind a small proxy that adds
the COOP/COEP headers required for `SharedArrayBuffer`-backed stdin. Hot module
reloading is disabled in this mode, so refresh the page after frontend edits.

## Production Build

```bash
bun run build
bun run start
```

## Notes

- `src/build-terminal.ts` drives the Swift manifest and wasm build.
- `src/scene-runtime.ts` provides the example-specific WASI bootstrap that runs `WebExampleApp` inside each `WebTUIGUI` scene runtime.
- The web host uses WebTUIGUI's structured surface transport and canvas
  renderer; there is no terminal-emulator wasm side asset.
- `TerminalApp/Sources/WebExampleScenes/WebExampleApp.swift` is the reusable
  `TerminalUI.App` definition. `TerminalApp/Sources/TerminalApp/main.swift`
  is only the launcher and calls `try await TerminalWASIAppRunner.run(WebExampleApp.self)`.
