import {
  WebHostSceneRuntime,
  type WebHostSceneRuntimeOptions,
} from "../WebHostSceneRuntime.ts";
import {
  encodeResizeControlMessage,
  type BrowserWASIBridge,
} from "./BrowserWASIBridge.ts";

import {
  SharedInputQueueWriter,
  createSharedInputQueue,
  type SharedInputQueueBuffers,
} from "./SharedInputQueue.ts";

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
  readonly descriptor: WebHostSceneRuntime["descriptor"];
  sendInput(chunk: Uint8Array): void;
}

export interface WasmSceneRuntimeFactoryOptions {
  onSceneResize?(event: WasmSceneResizeEvent): void;
  onRuntimeCreated?(runtime: WasmSceneRuntimeHandle): void;
  workerModuleURL?: string | URL;
}

export function createWasmSceneRuntimeFactory(
  wasmURL: URL,
  factoryOptions: WasmSceneRuntimeFactoryOptions = {}
): (options: WebHostSceneRuntimeOptions) => WebHostSceneRuntime {
  return (options) => {
    const runtime = new WasmSceneRuntime(options, wasmURL, factoryOptions);
    factoryOptions.onRuntimeCreated?.(runtime);
    return runtime;
  };
}

class WasmSceneRuntime extends WebHostSceneRuntime {
  private readonly bridge?: BrowserWASIBridge;
  private readonly wasmURL: URL;
  private readonly onSceneResize?: (event: WasmSceneResizeEvent) => void;
  private readonly workerModuleURL: string | URL;
  private readonly inputQueue?: SharedInputQueueBuffers;
  private readonly inputWriter?: SharedInputQueueWriter;

  private detachResizeListener?: () => void;
  private worker?: Worker;
  private didMount = false;

  constructor(
    options: WebHostSceneRuntimeOptions,
    wasmURL: URL,
    factoryOptions: WasmSceneRuntimeFactoryOptions
  ) {
    let inputQueue: SharedInputQueueBuffers | undefined;
    let inputWriter: SharedInputQueueWriter | undefined;

    try {
      inputQueue = createSharedInputQueue();
      inputWriter = new SharedInputQueueWriter(inputQueue);
    } catch (error) {
      console.error("[SwiftTUIWeb] failed to create shared stdin queue", error);
    }

    super({
      ...options,
      onInput: (chunk) => {
        try {
          inputWriter?.write(chunk);
        } catch (error) {
          console.error("[SwiftTUIWeb] failed to enqueue terminal input", error);
        }
      },
    });

    this.bridge = options.bridge;
    this.wasmURL = wasmURL;
    this.onSceneResize = factoryOptions.onSceneResize;
    this.workerModuleURL = factoryOptions.workerModuleURL ?? workerModuleURL;
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
        "\r\nSwiftTUI WASI browser runtime requires SharedArrayBuffer-backed stdin. Serve the app with COOP/COEP headers.\r\n"
      );
      return;
    }

    this.worker = new Worker(this.workerModuleURL, { type: "module" });
    this.worker.addEventListener("message", (event: MessageEvent<WorkerMessage>) => {
      this.handleWorkerMessage(event.data);
    });
    this.worker.addEventListener("error", (event) => {
      this.bridge?.stderr.write(
        `\nSwiftTUI WASI worker failed: ${event.message || "unknown worker error"}\n`
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
        this.bridge?.stderr.write(`\nSwiftTUI WASI app exited with code ${message.code}.\n`);
      }
      break;
    case "error":
      this.bridge?.stderr.write(`\nFailed to start SwiftTUI WASI app: ${message.message}\n`);
      break;
    }
  }
}
