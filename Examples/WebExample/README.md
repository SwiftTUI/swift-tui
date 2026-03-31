# WebExample

Minimal Bun web app that embeds a Swift `TerminalUI` executable through
[`GUI/WebTUIGUI`](/Users/adamz/Developer/repos/swift-terminal-ui/GUI/WebTUIGUI).

The example has two parts:

- `TerminalApp/`: a tiny Swift package with a reusable `WebExampleScenes`
  library target plus a thin `WebExampleApp` executable launcher
- `src/`: the Bun host that builds the manifest and wasm assets, serves them, and mounts `WebTUIGUI`

## Toolchains

- Use `swiftly` and Swift 6.3.0 for the Swift build path
- Use Bun for the web app

## Setup

```bash
bun install
```

## Development

```bash
bun dev
```

`bun dev` first builds `TerminalApp/dist/scene-manifest.json` and
`TerminalApp/dist/assets/app.wasm`, copies the packaged `ghostty-web`
`ghostty-vt.wasm` into `dist/`, then starts the Bun server.

## Production Build

```bash
bun build
bun start
```

## Notes

- `src/build-terminal.ts` drives the Swift manifest and wasm build.
- `src/scene-runtime.ts` provides the example-specific WASI bootstrap that runs `WebExampleApp` inside each `WebTUIGUI` scene runtime.
- The Bun server serves `/ghostty-vt.wasm` from the built `dist/` directory, using the version shipped by the npm `ghostty-web` package.
- `TerminalApp/Sources/WebExampleScenes/WebExampleApp.swift` is the reusable
  `TerminalUI.App` definition. `TerminalApp/Sources/TerminalApp/main.swift`
  is only the launcher and calls `try await MultiSceneLauncher.run(WebExampleApp.self)`.
