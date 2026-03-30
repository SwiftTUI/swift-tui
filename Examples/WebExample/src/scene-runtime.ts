import {
  WASI,
  ConsoleStdout,
  File,
  OpenFile,
} from "@bjorn3/browser_wasi_shim";
import {
  WebTUISceneRuntime,
  type WebTUISceneRuntimeOptions,
} from "../../../GUI/WebTUIGUI/src/WebTUISceneRuntime.ts";
import type { BrowserWASIBridge } from "../../../GUI/WebTUIGUI/src/wasi/BrowserWASIBridge.ts";

export function createWasmSceneRuntimeFactory(
  wasmURL: URL
): (options: WebTUISceneRuntimeOptions) => WebTUISceneRuntime {
  return (options) => new WasmSceneRuntime(options, wasmURL);
}

class WasmSceneRuntime extends WebTUISceneRuntime {
  private readonly bridge?: BrowserWASIBridge;
  private readonly wasmURL: URL;
  private startTask?: Promise<void>;

  constructor(
    options: WebTUISceneRuntimeOptions,
    wasmURL: URL
  ) {
    super(options);
    this.bridge = options.bridge;
    this.wasmURL = wasmURL;
  }

  override async mount(): Promise<void> {
    await super.mount();
    if (!this.startTask) {
      this.startTask = this.startModule();
    }
    await this.startTask;
  }

  private async startModule(): Promise<void> {
    if (!this.bridge) {
      return;
    }

    try {
      const response = await fetch(this.wasmURL);
      if (!response.ok) {
        throw new Error(`failed to load ${this.wasmURL.pathname}: ${response.status} ${response.statusText}`);
      }

      const wasi = new WASI(
        ["app.wasm"],
        Object.entries(this.bridge.environment).map(([key, value]) => `${key}=${value}`),
        [
          new OpenFile(new File(new Uint8Array())),
          new ConsoleStdout((chunk) => this.bridge?.stdout.write(chunk)),
          new ConsoleStdout((chunk) => this.bridge?.stderr.write(chunk)),
        ]
      );

      const module = await WebAssembly.compile(await response.arrayBuffer());
      const instance = await WebAssembly.instantiate(module, {
        wasi_snapshot_preview1: wasi.wasiImport,
      });
      const exitCode = wasi.start(instance as WebAssembly.Instance);
      if (exitCode !== 0) {
        this.bridge.stderr.write(`\nWebExampleApp exited with code ${exitCode}.\n`);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.bridge.stderr.write(`\nFailed to start WebExampleApp: ${message}\n`);
    }
  }
}
