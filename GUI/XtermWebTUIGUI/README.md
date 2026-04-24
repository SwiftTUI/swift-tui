# XtermWebTUIGUI

Browser wrapper for TerminalUI apps using xterm.js.

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

## xterm.js Dependency

This package consumes the published [`@xterm/xterm`](https://www.npmjs.com/package/@xterm/xterm)
and [`@xterm/addon-fit`](https://www.npmjs.com/package/@xterm/addon-fit)
npm packages through Bun instead of importing a repo-local browser terminal
implementation.

That keeps the JavaScript bundle version-locked and avoids the extra Ghostty
browser asset path used by `GUI/WebTUIGUI`.

Because `TerminalUIWASI` defaults to the structured `web-surface` transport,
this package sets `TUIGUI_TRANSPORT=ansi` when launching browser-hosted apps.

## API

```ts
import { createWebTUIApp } from "./index.ts";

const controller = await createWebTUIApp({
  mount: document.getElementById("app")!,
  manifestUrl: new URL("./scene-manifest.json", import.meta.url),
  style: {
    palette: {
      foreground: "#eceff4",
      background: "#1e222a",
      cursor: "#56b6c2",
      selectionBackground: "#2e3440",
      selectionForeground: "#eceff4",
    },
    theme: {
      foreground: "#eceff4",
      background: "#1e222a",
      tint: "#56b6c2",
      link: "#5ba3ff",
    },
  },
});

await controller.switchScene("dashboard");
controller.setStyle({ cursorBlink: true, theme: { tint: "#79c0ff" } });
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
2. `build:wasm` copies the app's wasm artifact into `dist/assets/app.wasm`,
   validates it with the browser `WebAssembly` API, then keeps the stripped
   artifact only if stripping still produces browser-parseable wasm.
3. `build:web` bundles `index.html` and the browser entrypoint with Bun. The xterm.js runtime is loaded from npm and does not require a separate packaged wasm terminal asset.

## Notes

- Scene switching is controller-managed and retains existing scene runtimes.
- Terminal styling is host-owned through `WebTUITerminalStyle`, which carries
  one active palette/theme pair plus the runtime payload sent into TerminalUI.
- Hosts that want multiple themes swap entire `WebTUITerminalStyle` objects;
  the library does not provide a built-in mode switcher.
- `BrowserWASIBridge` and `StdIOPipe` are the internal glue for future WASI-backed integration.
