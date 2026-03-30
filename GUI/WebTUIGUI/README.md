# WebTUIGUI

Browser wrapper for TerminalUI apps.

## Toolchains

Use Bun for this package, and use the repo-default `swiftly` Swift 6.3.0
toolchain for every Swift command that the build pipeline triggers.

Before running the Bun scripts here, make sure `swift` in your shell already
points at the `swiftly`-managed Swift 6.3.0 toolchain. The Bun scripts shell
out to `swift` directly.

Quick check:

```bash
swift --version
```

Native-only development should also work in Xcode, but the documented package
and wasm build path for this wrapper uses `swiftly` plus Bun.

## API

```ts
import { createWebTUIApp } from "./index.ts";

const controller = await createWebTUIApp({
  mount: document.getElementById("app")!,
  manifestUrl: new URL("./scene-manifest.json", import.meta.url),
});

await controller.switchScene("dashboard");
controller.setStyle({ cursorBlink: true });
```

## Scripts

- `bun test`
- `bun run build:manifest -- --app <AppExecutable>`
- `bun run build:wasm -- --app <AppExecutable>`
- `bun run build:web`
- `bun run build -- --app <AppExecutable>`
- `bun run dev`

The build flow is intentionally small:

1. `build:manifest` captures `TUIGUI_MODE=manifest` output from the Swift app by invoking the `swiftly`-managed `swift`.
2. `build:wasm` copies the app's wasm artifact into `dist/assets/app.wasm`.
3. `build:web` bundles `index.html` and the browser entrypoint with Bun.

## Notes

- Scene switching is controller-managed and retains existing scene runtimes.
- Terminal styling is exposed through `WebTUITerminalStyle`.
- `BrowserWASIBridge` and `StdIOPipe` are the internal glue for future WASI-backed integration.
