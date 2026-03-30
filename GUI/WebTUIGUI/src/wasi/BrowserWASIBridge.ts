import { StdIOPipe } from "./StdIOPipe.ts";

export interface BrowserWASIBridgeOptions {
  sceneId: string;
  columns: number;
  rows: number;
  environment?: Record<string, string>;
}

export interface BrowserWASIOutputSink {
  writeOutput(text: string): void;
  writeError?(text: string): void;
  resize(columns: number, rows: number): void;
}

export class BrowserWASIBridge {
  readonly stdin = new StdIOPipe();
  readonly stdout = new StdIOPipe();
  readonly stderr = new StdIOPipe();
  readonly environment: Record<string, string>;

  private detachStdout?: () => void;
  private detachStderr?: () => void;
  private readonly resizeListeners = new Set<(columns: number, rows: number) => void>();

  constructor(options: BrowserWASIBridgeOptions) {
    this.environment = {
      TUIGUI_MODE: "browser",
      TUIGUI_SCENE: options.sceneId,
      TUIGUI_COLUMNS: String(Math.max(1, options.columns)),
      TUIGUI_ROWS: String(Math.max(1, options.rows)),
      ...options.environment,
    };
  }

  bindOutput(
    sink: BrowserWASIOutputSink
  ): void {
    this.detachStdout?.();
    this.detachStderr?.();
    this.detachStdout = this.stdout.subscribe((chunk) => {
      sink.writeOutput(new TextDecoder().decode(chunk));
    });
    this.detachStderr = this.stderr.subscribe((chunk) => {
      sink.writeError?.(new TextDecoder().decode(chunk));
    });
  }

  resize(
    columns: number,
    rows: number
  ): void {
    const normalizedColumns = Math.max(1, columns);
    const normalizedRows = Math.max(1, rows);
    this.environment.TUIGUI_COLUMNS = String(normalizedColumns);
    this.environment.TUIGUI_ROWS = String(normalizedRows);
    this.stdin.write(encodeResizeControlMessage(columns, rows));
    for (const listener of this.resizeListeners) {
      listener(normalizedColumns, normalizedRows);
    }
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    this.stdin.write(chunk);
  }

  subscribeResize(
    listener: (columns: number, rows: number) => void
  ): () => void {
    this.resizeListeners.add(listener);
    return () => {
      this.resizeListeners.delete(listener);
    };
  }

  dispose(): void {
    this.detachStdout?.();
    this.detachStderr?.();
    this.resizeListeners.clear();
    this.stdin.close();
    this.stdout.close();
    this.stderr.close();
  }
}

export function encodeResizeControlMessage(
  columns: number,
  rows: number
): Uint8Array {
  return new TextEncoder().encode(`\u001Eresize:${Math.max(1, columns)}:${Math.max(1, rows)}\n`);
}
