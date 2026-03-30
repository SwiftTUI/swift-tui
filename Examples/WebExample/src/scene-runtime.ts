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

const resizeRelaunchDelayMs = 75;

export interface WasmSceneResizeEvent {
  sceneId: string;
  columns: number;
  rows: number;
}

export interface WasmSceneRuntimeFactoryOptions {
  onSceneResize?(event: WasmSceneResizeEvent): void;
}

export function createWasmSceneRuntimeFactory(
  wasmURL: URL,
  factoryOptions: WasmSceneRuntimeFactoryOptions = {}
): (options: WebTUISceneRuntimeOptions) => WebTUISceneRuntime {
  return (options) => new WasmSceneRuntime(options, wasmURL, factoryOptions);
}

class WasmSceneRuntime extends WebTUISceneRuntime {
  private readonly bridge?: BrowserWASIBridge;
  private readonly wasmURL: URL;
  private readonly onSceneResize?: (event: WasmSceneResizeEvent) => void;
  private detachResizeListener?: () => void;
  private moduleRunTask: Promise<void> = Promise.resolve();
  private modulePromise?: Promise<WebAssembly.Module>;
  private resizeRelaunchTimer?: ReturnType<typeof setTimeout>;
  private didMount = false;
  private runCount = 0;

  constructor(
    options: WebTUISceneRuntimeOptions,
    wasmURL: URL,
    factoryOptions: WasmSceneRuntimeFactoryOptions
  ) {
    super(options);
    this.bridge = options.bridge;
    this.wasmURL = wasmURL;
    this.onSceneResize = factoryOptions.onSceneResize;
  }

  override async mount(): Promise<void> {
    await super.mount();
    if (this.didMount) {
      return;
    }

    this.didMount = true;
    this.detachResizeListener = this.bridge?.subscribeResize((columns, rows) => {
      console.debug("[WebExample] scene resize", {
        sceneId: this.descriptor.id,
        columns,
        rows,
      });
      this.onSceneResize?.({
        sceneId: this.descriptor.id,
        columns,
        rows,
      });
      this.scheduleResizeRelaunch();
    });
    await this.enqueueModuleRun();
  }

  override dispose(): void {
    if (this.resizeRelaunchTimer) {
      clearTimeout(this.resizeRelaunchTimer);
      this.resizeRelaunchTimer = undefined;
    }
    this.detachResizeListener?.();
    super.dispose();
  }

  private scheduleResizeRelaunch(): void {
    if (!this.didMount) {
      return;
    }

    if (this.resizeRelaunchTimer) {
      clearTimeout(this.resizeRelaunchTimer);
    }

    this.resizeRelaunchTimer = setTimeout(() => {
      this.resizeRelaunchTimer = undefined;
      void this.enqueueModuleRun(true);
    }, resizeRelaunchDelayMs);
  }

  private enqueueModuleRun(
    clearScreen: boolean = false
  ): Promise<void> {
    this.moduleRunTask = this.moduleRunTask.then(async () => {
      if (clearScreen) {
        this.writeOutput("\u001B[2J\u001B[H");
      }
      await this.startModule();
    });
    return this.moduleRunTask;
  }

  private async startModule(): Promise<void> {
    if (!this.bridge) {
      return;
    }

    try {
      const columns = Number(this.bridge.environment.TUIGUI_COLUMNS ?? "0") || 0;
      const rows = Number(this.bridge.environment.TUIGUI_ROWS ?? "0") || 0;
      this.runCount += 1;
      console.debug("[WebExample] launching scene", {
        sceneId: this.descriptor.id,
        columns,
        rows,
        runCount: this.runCount,
      });
      const wasi = new WASI(
        ["app.wasm"],
        Object.entries(this.bridge.environment).map(([key, value]) => `${key}=${value}`),
        [
          new OpenFile(new File(new Uint8Array())),
          new ConsoleStdout((chunk) => this.bridge?.stdout.write(chunk)),
          new ConsoleStdout((chunk) => this.bridge?.stderr.write(chunk)),
        ]
      );

      const module = await this.loadModule();
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

  private loadModule(): Promise<WebAssembly.Module> {
    if (this.modulePromise) {
      return this.modulePromise;
    }

    this.modulePromise = (async () => {
      const response = await fetch(this.wasmURL);
      if (!response.ok) {
        throw new Error(`failed to load ${this.wasmURL.pathname}: ${response.status} ${response.statusText}`);
      }

      return await WebAssembly.compile(await response.arrayBuffer());
    })();

    return this.modulePromise;
  }
}
