import {
  WebTUISceneRuntime,
  type WebTUISceneRuntimeOptions,
} from "webtuigui";
import {
  encodeResizeControlMessage,
  type BrowserWASIBridge,
} from "webtuigui";

import {
  SharedInputQueueWriter,
  createSharedInputQueue,
  type SharedInputQueueBuffers,
} from "./wasi-input-queue.ts";

const workerModuleURL = new URL("./wasm-scene-worker.js", import.meta.url);

interface WorkerStartMessage {
  type: "start";
  wasmURL: string;
  environment: Record<string, string>;
  inputQueue: SharedInputQueueBuffers;
}

interface WorkerOutputMessage {
  type: "stdout" | "stderr";
  chunk: Uint8Array;
}

interface WorkerExitMessage {
  type: "exit";
  code: number;
}

interface WorkerErrorMessage {
  type: "error";
  message: string;
}

type WorkerMessage = WorkerOutputMessage | WorkerExitMessage | WorkerErrorMessage;

export interface WasmSceneResizeEvent {
  sceneId: string;
  columns: number;
  rows: number;
  cellWidth?: number;
  cellHeight?: number;
}

export interface WasmSceneRuntimeHandle {
  readonly descriptor: WebTUISceneRuntime["descriptor"];
  sendInput(chunk: Uint8Array): void;
}

export interface WasmSceneRuntimeFactoryOptions {
  onSceneResize?(event: WasmSceneResizeEvent): void;
  onRuntimeCreated?(runtime: WasmSceneRuntimeHandle): void;
}

export function createWasmSceneRuntimeFactory(
  wasmURL: URL,
  factoryOptions: WasmSceneRuntimeFactoryOptions = {}
): (options: WebTUISceneRuntimeOptions) => WebTUISceneRuntime {
  return (options) => {
    const runtime = new WasmSceneRuntime(options, wasmURL, factoryOptions);
    factoryOptions.onRuntimeCreated?.(runtime);
    return runtime;
  };
}

class WasmSceneRuntime extends WebTUISceneRuntime {
  private readonly bridge?: BrowserWASIBridge;
  private readonly wasmURL: URL;
  private readonly onSceneResize?: (event: WasmSceneResizeEvent) => void;
  private readonly inputQueue?: SharedInputQueueBuffers;
  private readonly inputWriter?: SharedInputQueueWriter;

  private detachResizeListener?: () => void;
  private worker?: Worker;
  private didMount = false;

  constructor(
    options: WebTUISceneRuntimeOptions,
    wasmURL: URL,
    factoryOptions: WasmSceneRuntimeFactoryOptions
  ) {
    let inputQueue: SharedInputQueueBuffers | undefined;
    let inputWriter: SharedInputQueueWriter | undefined;

    try {
      inputQueue = createSharedInputQueue();
      inputWriter = new SharedInputQueueWriter(inputQueue);
    } catch (error) {
      console.error("[WebExample] failed to create shared stdin queue", error);
    }

    super({
      ...options,
      onInput: (chunk) => {
        try {
          inputWriter?.write(chunk);
        } catch (error) {
          console.error("[WebExample] failed to enqueue terminal input", error);
        }
      },
    });

    this.bridge = options.bridge;
    this.wasmURL = wasmURL;
    this.onSceneResize = factoryOptions.onSceneResize;
    this.inputQueue = inputQueue;
    this.inputWriter = inputWriter;
  }

  override async mount(): Promise<void> {
    await super.mount();
    if (this.didMount) {
      return;
    }

    this.didMount = true;
    this.detachResizeListener = this.bridge?.subscribeResize((columns, rows, cellWidth, cellHeight) => {
      this.onSceneResize?.({
        sceneId: this.descriptor.id,
        columns,
        rows,
        cellWidth,
        cellHeight,
      });
      this.inputWriter?.write(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
    });

    const initialColumns = Number(this.bridge?.environment.TUIGUI_COLUMNS ?? "0") || 0;
    const initialRows = Number(this.bridge?.environment.TUIGUI_ROWS ?? "0") || 0;
    if (!this.bridge && initialColumns > 0 && initialRows > 0) {
      this.onSceneResize?.({
        sceneId: this.descriptor.id,
        columns: initialColumns,
        rows: initialRows,
      });
    }

    if (!this.inputQueue || !this.inputWriter || !this.bridge) {
      this.writeOutput(
        "\r\nWebExampleApp requires SharedArrayBuffer-backed stdin. Serve the app with COOP/COEP headers.\r\n"
      );
      return;
    }

    this.worker = new Worker(workerModuleURL, { type: "module" });
    this.worker.addEventListener("message", (event: MessageEvent<WorkerMessage>) => {
      this.handleWorkerMessage(event.data);
    });
    this.worker.addEventListener("error", (event) => {
      this.bridge?.stderr.write(
        `\nWebExample worker failed: ${event.message || "unknown worker error"}\n`
      );
    });

    const environment = { ...this.bridge.environment };

    const message: WorkerStartMessage = {
      type: "start",
      wasmURL: this.wasmURL.href,
      environment,
      inputQueue: this.inputQueue,
    };
    this.worker.postMessage(message);
  }

  override dispose(): void {
    this.detachResizeListener?.();
    this.inputWriter?.close();
    this.worker?.terminate();
    super.dispose();
  }

  private handleWorkerMessage(
    message: WorkerMessage
  ): void {
    switch (message.type) {
    case "stdout":
      this.bridge?.stdout.write(message.chunk);
      break;
    case "stderr":
      this.bridge?.stderr.write(message.chunk);
      break;
    case "exit":
      if (message.code !== 0) {
        this.bridge?.stderr.write(`\nWebExampleApp exited with code ${message.code}.\n`);
      }
      break;
    case "error":
      this.bridge?.stderr.write(`\nFailed to start WebExampleApp: ${message.message}\n`);
      break;
    }
  }
}
