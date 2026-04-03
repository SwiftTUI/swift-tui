# WebTUIGUI

Browser wrapper for TerminalUI apps.

## Toolchains

Use Bun for this package, and use the repo-default `swiftly` Swift 6.3.0
toolchain for every Swift command that the build pipeline triggers.

Quick check:

```bash
swiftly run swift --version
```

Native-only development should also work in Xcode, but the documented package
and wasm build path for this wrapper uses `swiftly` plus Bun.

This package now lives in the repo's Bun workspace. Run `bun install` from the
repo root or from any workspace package directory, and Bun will maintain one
root `bun.lock` plus stable relative workspace links.

## Ghostty Dependency

This package now consumes the published [`ghostty-web`](https://www.npmjs.com/package/ghostty-web)
npm package through Bun instead of importing from the repository's `reference/`
directory or from a GitHub source snapshot.

That keeps the JavaScript bundle and `ghostty-vt.wasm` asset version-locked and
avoids the extra Ghostty submodule and Zig bootstrap step during app builds.

## API

```ts
import { createWebTUIApp } from "./index.ts";

const controller = await createWebTUIApp({
  mount: document.getElementById("app")!,
  manifestUrl: new URL("./scene-manifest.json", import.meta.url),
  style: {
    colorSchemeMode: "system",
    dark: {
      theme: {
        foreground: "#eceff4",
        background: "#1e222a",
        tint: "#56b6c2",
      },
    },
    light: {
      theme: {
        foreground: "#1f2328",
        background: "#ffffff",
        tint: "#0969da",
      },
    },
  },
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

1. `build:manifest` captures `TUIGUI_MODE=manifest` output from the Swift app by invoking `swiftly run swift`.
2. `build:wasm` copies the app's wasm artifact into `dist/assets/app.wasm`.
3. `build:web` bundles `index.html` and the browser entrypoint with Bun, then copies `ghostty-web`'s packaged `ghostty-vt.wasm` into `dist/`.

## Notes

- Scene switching is controller-managed and retains existing scene runtimes.
- Terminal styling is host-owned through `WebTUITerminalStyle`, which now carries
  explicit light and dark theme variants plus a semantic runtime payload.
- `BrowserWASIBridge` and `StdIOPipe` are the internal glue for future WASI-backed integration.
